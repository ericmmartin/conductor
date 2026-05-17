# Skills reference

Every `/conductor:*` command. Skills are stateless and self-contained. They can be invoked manually via the plugin or dispatched by the daemon.

## Core SDLC

### `/conductor:init`
Onboard a repo. Creates conductor labels in the repo, scaffolds `.conductor/profile.yml` from a template, validates the GitHub Project setup, copies default subagent prompts into `.conductor/reviewers/`. One-time per repo.

### `/conductor:spec`
Convert a raw idea or one-line issue into a properly structured spec (acceptance criteria, dependencies, scope). Runs Sonnet by default at high effort. Optional — you can write issues by hand and skip this.

### `/conductor:work <issue#>`
The main implementation skill. Claims the issue (atomic Project status swap), creates a worktree, runs the implementation per the issue's acceptance criteria, runs the configured quality gates, opens a PR. Default model: Opus at high effort.

If invoked manually on an issue another conductor instance has already claimed, refuses with a clear message. Pass `--force` to override.

### `/conductor:address <pr#>`
Iterate Qodo's comments on a PR. For each comment: decides validity, fixes valid findings, rebuts invalid ones, files out-of-scope findings as new issues, replies per-comment, resolves threads. Pushes fixes as one commit (or one per logical group). Default model: Sonnet at medium effort.

See [qodo-integration.md](./qodo-integration.md#addressing-qodos-findings) for the full flow.

### `/conductor:ship <pr#>`
Merge the PR, bump the version per the profile's `version.source`, write a changelog entry, create a Git tag, create a GitHub Release. Default model: Haiku at low effort (mostly bookkeeping).

### `/conductor:review`
Run the subagent reviewers (`code-review.md`, `security-review.md`, `ux-review.md`) from `.conductor/reviewers/` against a worktree or PR diff. Used internally by `/conductor:work` before opening a PR. Can be invoked manually for a second opinion. Default model: Sonnet at medium effort.

### `/conductor:reflect`
Post-mortem on a shipped issue. Reviews what happened, surfaces patterns, suggests improvements. Optional. Default model: Sonnet at medium effort.

### `/conductor:audit`
Detects ecosystem from the profile or repo files and runs the appropriate audit tool (`npm audit`, `pip-audit`, `cargo audit`, `go list -m`). Replaces the predecessor's four separate audit skills. Default model: Haiku at low effort.

## Operational

### `/conductor:status`
Print daemon health, slot occupancy, per-project state, current usage, gate states, and the next 10 projects in the queue. Reads from the daemon's SQLite via the `/status` JSON endpoint or local DB. Same data as the status page and the JSON endpoint — one query module, three surfaces.

### `/conductor:pause [reason]`
Manually pause the daemon. No new work picked up; in-flight work continues. Useful before a manual deployment or when you need the orchestrator out of the way.

### `/conductor:resume`
Resume a manually paused daemon.

### `/conductor:usage`
Token usage report. Default view: tokens per skill over the last 7 days, per model. Flags:
- `--repo <name>` — filter to one repo
- `--since <duration>` — e.g., `7d`, `24h`, `30d`
- `--by skill|repo|model|issue`

### `/conductor:reflect-usage`
Reads the usage table, identifies optimization candidates (skills above expected token bands, Opus usage not benefiting from Opus-tier reasoning), reports concrete suggestions. Run when you want to refine model routing. Default model: Sonnet at high effort.

## Periodic

### `/conductor:digest`
Generates the daily shipped-issues summary. Commits to `docs/digests/{date}.md` and/or notifies Teams-Bot/Discord per the profile's `digest.output` setting. Runs on the cron schedule defined in the profile, or invoke manually. Default model: Haiku at low effort (mostly summarization of structured data).

### `/conductor:triage` (Phase 6)
Backlog hygiene. Checks new issues for similarity to open or recently-shipped issues, flags potential duplicates or file-overlap conflicts as comments on the new issue. Does not block — humans decide what to do. See [periodic-skills.md](./periodic-skills.md#conductortriage--backlog-hygiene-phase-6).
