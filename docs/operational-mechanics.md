# Operational mechanics

A handful of things that didn't fit neatly into the other docs.

## Polling cadence — adaptive, not fixed

The project-specific predecessor polls every 10 minutes. That's right for the daemon-wide "is there new ready work anywhere?" question but wrong for an active issue mid-flight where a Qodo comment landing now means the orchestrator should respond in seconds, not minutes.

The new model uses **three poll cadences**, all running in the same daemon:

- **Daemon-wide poll (default 10 min)** — checks every watched repo's Project board for new `Ready` issues, runs the reconciler, refreshes the usage probe. Cheap GH API calls; the cadence determines how fast new work enters the system.
- **Active-PR poll (default 30 sec)** — for every PR currently in `:in-review` or being-addressed state, poll for new Qodo comments, review thread updates, CI status changes. Stops automatically when the PR moves to a terminal state (merged, blocked, etc.). Spins back up if the PR re-enters a watched state.
- **Validation poll (default 5 min)** — for every PR in `:validating` (deploy_and_validate waiting for `conductor:validated`), poll for the label or `/conductor validated` comment. Slower because humans take longer than CI.

All three cadences are configurable in `~/.conductor/config.yml`. The active-PR poll is the one most worth tuning if you find Qodo response handling feels sluggish.

This collapses the "an issue takes an hour, why poll every 10 min" concern — the daemon-wide poll *is* every 10 min, but the active-issue's PR is polled every 30 sec for things that actually matter to it. Webhook delivery is Phase 5 polish; adaptive polling gets you 90% of the responsiveness with 5% of the infrastructure (no public URL needed).

## Block types and how humans resolve them

Four block labels, each with a clear resolution path:

| Label | Cause | How to resolve |
|---|---|---|
| `conductor:blocked-discovery` | During work, the skill surfaced a question or decision that needs a human (architectural ambiguity, missing acceptance criteria, etc.). | Read the orchestrator's comment explaining what's needed. Edit the issue body, add clarification, or comment. Remove the label. Orchestrator resumes on the next active-PR poll. |
| `conductor:blocked-dependency` | A cross-project dep (`project-a#42`) is broken — target doesn't exist, was closed without merge, or a cycle was detected. | Fix the dependency declaration in the issue body (edit out, point to a different issue, etc.). Remove the label. Orchestrator re-evaluates. If the dep simply hasn't merged yet, no action needed — the label clears automatically when the upstream merges. |
| `conductor:blocked-review` | Qodo failed to start within 60s of the `/agentic_review` trigger. | Investigate Qodo (rate-limited? service degraded?). When ready, comment `/agentic_review` on the PR yourself, or trigger via Qodo UI. The orchestrator's active-PR poll detects the new review attempt and continues. Remove the label once review starts. |
| `conductor:blocked-conflict` | A merge attempt failed due to a Git conflict (shouldn't happen with sequential-per-project, but possible if a human merges something unrelated mid-PR). | Pull the worktree locally, resolve, push. Comment `/conductor retry` on the PR. The orchestrator re-attempts the merge. |

All four free the project's slot. None require restarting the daemon.

## Drizzle migration conflicts

Mostly a non-issue with sequential-per-project (the next branch always starts from a base that includes the previous migration). If two issues both add migrations and one ships first, the second's migration file timestamp will conflict only if both were generated against the pre-merge base. Drizzle's CLI complains loudly when this happens, which becomes a `:blocked-conflict` via the same mechanism above.

For belt-and-suspenders: the `audit` skill includes a check for "migration files newer than this branch's base" and warns at PR creation time. Doesn't block, just surfaces in the PR description's Conductor activity block (see [visibility.md](./visibility.md#surfacing-event-log-on-the-gh-pr)).

## Manual override from anywhere

The plugin can be invoked from any machine without a connection to the daemon. Coordination happens through GitHub. See [concurrency-model.md](./concurrency-model.md#manual-override-plugin-mode-anywhere) for the full mechanics.

## SQLite and recovery

The daemon keeps a Drizzle-backed SQLite database (WAL mode) at `~/.conductor/conductor.db`. It holds:

- **Token usage attribution** — one row per skill spawn with model, effort, tokens in/out, timestamps. Powers `/conductor:usage`, `/conductor:reflect-usage`, the status page.
- **Active-PR tracking** — which PRs are being monitored, last poll time, last seen Qodo activity. Drives the active-PR poll cadence.
- **Cached usage probe** — 60s TTL on the Anthropic API probe so we don't hit it every cycle.
- **Manual pause state** — set by `/conductor:pause`, cleared by `/conductor:resume`.
- **Reconciler bookkeeping** — last reconciled state per project for drift detection.

SQLite is **never authoritative for issue state.** Issue state lives in GitHub (labels + Project status). The poller is idempotent — every cycle re-evaluates all repos' Project boards from scratch. There's no "queue position" stored anywhere that can get out of sync.

### Failure modes and recovery

**Daemon crash (any reason).** On restart, the poller queries every watched repo's Project board, finds in-flight issues by their status, and resumes from where GitHub says they are. SQLite is consulted for the active-PR tracking (so we know what to poll fast vs slow), but if SQLite is empty or stale, the next daemon-wide poll will rebuild it within 10 minutes. No queue state is ever lost.

**Crash mid-skill spawn (e.g., daemon killed while `/conductor:work` was running).** The Claude process is its own subprocess and either:
- **Completes naturally** before being killed (write-protected by graceful shutdown, 10-min drain) — writes `results/issue-{N}.json` as planned. On daemon restart, the runner reads the result file and advances state.
- **Is killed mid-flight** — no result file. On restart, the orchestrator sees the issue still at `:in-progress` on GitHub with no PR yet. Default behavior: re-spawn the skill from scratch (worktree is reused or recreated). The skill is idempotent — running it twice on the same issue produces the same final state.

**Crash between writing a label and writing the Project status field.** This is the dangerous "two-phase write" case. The reconciler runs each cycle and notices the drift; it reconciles toward Project status (which wins on conflict). One poll cycle of latency on resume.

**Network interruption (GitHub API down, Anthropic API down).** Poller retries with backoff. No state lost; just delayed.

**SQLite file corruption or accidental deletion.** Token usage history is lost (that's the only data SQLite owns authoritatively). State of in-flight work is fully reconstructible from GitHub — on next poll, the daemon discovers all in-flight issues and resumes from their current state. The active-PR poll tracking rebuilds within 10 minutes (next daemon-wide poll re-finds active PRs).

If you care about preserving token-usage history across machine moves or disk failures, periodically `cp ~/.conductor/conductor.db ~/.conductor/conductor.db.bak`. There's no automated backup — for a personal tool, manual is fine.

**Mid-merge or mid-ship crash.** `/conductor:ship` is the most failure-sensitive — it bumps versions, writes changelog, creates tags. If it crashes mid-ship, the partial work is on a git branch; the orchestrator detects the partial state on resume (version bumped but no tag, or tag exists but no GitHub Release) and completes the remaining steps. The project-specific predecessor already has this "detect dangling version bump on the base branch" pattern; port it to the new ship logic.

**Worktree corruption.** Worktrees are per-issue under `worktrees/issue-{N}/`. If one is corrupted, delete it and let the runner recreate. Worktrees never hold uncommitted state worth recovering — committed work is on the PR branch, which lives on GitHub.

### What's not recoverable

- **Token usage history before the last SQLite backup.** Annoying but not load-bearing for operation; can be partially reconstructed by querying GitHub for shipped PRs and inferring spend from the per-issue activity comments (which include token counts).
- **The JSONL event log** (`~/.conductor/events.jsonl`) if you delete it. Useful for forensics but not operational state.

The design philosophy: state lives where it's authoritative (GitHub), and everything else is a cache. Lose the cache, take a one-poll-cycle hit, and you're back.

---

## Distribution

Install from GitHub:

```bash
# Claude Code plugin
claude plugin install github:ericmmartin/conductor#main --path packages/plugin

# Daemon
npm install -g github:ericmmartin/conductor#main --workspaces orchestrator
```

Pin to a tag for reproducibility:

```bash
npm install -g github:ericmmartin/conductor#v0.3.0
```

Updates: `npm update -g github:ericmmartin/conductor#main`.

Public npm publication is deferred to Phase 5. Until then, GitHub install is the path.
