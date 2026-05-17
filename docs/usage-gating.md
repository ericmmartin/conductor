# Usage gating

Conductor doesn't track dollars. It tracks Claude session utilization. Three asymmetric thresholds gate which kinds of work the orchestrator can do.

## The thresholds

Gates are **global** (Claude session utilization is a global resource) and apply regardless of which project's slot is asking.

| Action | Skip if usage ≥ | Why |
|---|---|---|
| **Start new** (claim a `:ready` issue, run `/conductor:work`) | 80% | Most expensive operation; preserve headroom |
| **Address feedback** (run `/conductor:address` on a `:in-review` issue) | 85% | Don't abandon mostly-done work; allow finishing |
| **Ship** (run `/conductor:ship` on an approved issue) | 90% | Cheapest operation; finish what you started |

Above 90%, the daemon idles entirely until usage drops. On usage drop below the relevant threshold, work resumes in priority order: ship-ready first (clear the runway), then address, then start new.

**Interaction with project slots:** if usage is 82% and both slots are occupied, both active projects can continue addressing or shipping their in-flight issues, but neither can pick a *new* issue when its current one ships — the slot stays open until usage drops below 80%. A slot is "permission to do orchestrator work"; the gates determine *which kinds* of work that permission covers.

**Why escalating thresholds work:** the value-of-completion grows as an issue moves through its SDLC. An issue 90% through is more painful to abandon than one not yet started. The 5-pp headroom between gates means an issue you start at 79% has buffer to finish even if utilization climbs during the run.

See [ADR 005 — Usage gating, not budgets](../adrs/005-usage-gating-not-budgets.md) for why the entire dollar-based budget layer was deleted.

## How the probe works

Conductor reads Claude session utilization from a 1-token probe against the Anthropic API. The code lives in `packages/orchestrator/src/gates/usage.ts`, adapted verbatim from [nsanden/claude-rate-monitor](https://github.com/nsanden/claude-rate-monitor) (attribution preserved in the source comment).

Mechanism:

1. Read `~/.claude/.credentials.json` for the OAuth token.
2. Send `POST /v1/messages` with a 1-token request and the `anthropic-beta: oauth-2025-04-20` header.
3. Parse `anthropic-ratelimit-unified-5h-utilization` (and the 7d variant) from the response headers.
4. Cache the result for 60 seconds.
5. Fall back to `ccusage` CLI for per-block budget tracking if the probe fails.

The probe runs at the top of every poll cycle and before each new claim.

## Model routing

Declared per-skill in the profile, defaultable per-repo. Each skill can also set an `effort` value (Claude's extended-thinking budget):

```yaml
models:
  default:
    model: sonnet
    effort: medium
  skills:
    triage:   { model: haiku,  effort: low }
    audit:    { model: haiku,  effort: low }
    ship:     { model: haiku,  effort: low }
    address:  { model: sonnet, effort: medium }
    review:   { model: sonnet, effort: medium }
    spec:     { model: sonnet, effort: high }
    work:     { model: opus,   effort: high }    # default work is heavy
```

Per-issue overrides go in the issue body as plain keyword lines (same pattern as `semver: patch`):

```
model: opus
effort: maximum
```

No `budget:` tag — issues that need more resource get a heavier model or more effort, not a bigger dollar cap.

## Other pause states

Simpler, with their own predicates and resume conditions:

- **Rate-limit pause** — 429 from Claude or GitHub. Resume after API's `retry-after` plus jitter.
- **Active-hours pause** — outside the configured window. See below.
- **Manual pause** — operator-set via `/conductor:pause` and `/conductor:resume`.

No budget pause. No session-quota pause as a separate state — it's just usage ≥ 90%.

## Outside active hours

Several modes, configurable per-daemon:

```yaml
# in ~/.conductor/config.yml
active_hours:
  timezone: America/Los_Angeles
  windows:
    - days: [Mon, Tue, Wed, Thu, Fri]
      start: "05:00"
      end: "11:00"
  outside_window:
    mode: complete_only        # alternatives below
    reduce_concurrency_to: 1   # used only when mode = reduce_concurrency
```

Modes:

- **`complete_only`** (recommended default) — finish in-flight work but pick up no new issues. Lets current work drain naturally. Nothing piles up but nothing starts.
- **`pause`** — fully idle. In-flight issues sit at their current state until window opens. Use if you want zero token burn outside hours.
- **`reduce_concurrency`** — keep running but cap concurrency to `reduce_concurrency_to`. Useful if you want one project to keep going at night.
- **`reduce_models`** — keep running but downgrade all skills to Haiku. Cheaper continuation.

## Concurrency × usage interaction

With concurrency 1, the 80/85/90 thresholds map cleanly to one issue's lifecycle. With concurrency 2+, N projects burn tokens in parallel, so usage climbs faster and the thresholds get hit sooner relative to work done.

Conductor does not preemptively scale the thresholds. Reasons:

- At low concurrency (1–2), the parallel-burn effect is mild. Worth observing first.
- The token-usage attribution table gives you the data to tune. After a week at concurrency 2 you'll see whether the 80% start threshold leaves enough headroom for two parallel projects to ship.
- If it turns out concurrency 2 needs the start threshold dropped to 70%, that's a one-line config change in `usage_gates`. No code change needed.

What conductor *will* do automatically: show projected usage on the status page. Each in-flight project's recent token burn rate × estimated time-to-completion → a "projected usage at completion" number. Lets you see whether starting a third project right now would push you over 90% before the current two finish.

## Pickup after a usage reset

Claude's 5h utilization window resets every 5 hours; the 7d window rolls daily. When usage drops below a threshold, the orchestrator should automatically resume — no manual intervention.

The state is already preserved across pauses, because:

- **Every state transition is written to GitHub** (label + Project status) and the orchestrator's SQLite *before* the work starts. So a usage-gate pause never loses state — the issue is at whatever GitHub says.
- **In-flight issues** that were paused mid-skill — the spawned Claude process completes naturally (graceful drain) or is killed at the end of the current skill. On resume, the orchestrator inspects the issue's GH state and either re-runs the skill from scratch (typical) or picks up at the next state-machine step (if the prior skill completed and wrote its result file).
- **The poller is idempotent** — every cycle re-evaluates all repos' Project boards from scratch. There's no "queue position" to lose. When the gate re-opens, the next poll just picks up the highest-priority eligible work.

Concretely on resume:

1. Usage probe shows ≥ 90% → daemon enters gate-paused state, current skill drains, poller stops dispatching.
2. Usage probe later shows < 80% (5h window reset) → daemon exits gate-paused state.
3. Next poll cycle: scheduler runs as normal. Projects with in-flight issues that need a next action (address, ship) get prioritized over starting-new-work because the 85/90 thresholds opened sooner than 80% during the climb back down.
4. Status page reflects the resume; an event-log line records the gate-cleared transition.

Operationally there's nothing for you to do.

## Per-skill token tracking and review

The usage attribution table (`(issue_number, repo, skill, model, effort, input_tokens, output_tokens, started_at, ended_at)`) supports queries via:

- **`/conductor:usage`** — plugin command. Default view: tokens per skill over the last 7 days, per model. Flags: `--repo <name>`, `--since <duration>`, `--by skill|repo|model|issue`.
- **Status page section "Tokens by skill (last 7d)"** — a tiny table showing each skill's average and p95 token spend.
- **`/conductor:reflect-usage`** — a once-in-a-while skill that reads the table, identifies optimization candidates (skills above some expected token band, or skills whose Opus usage produces outputs that didn't benefit from Opus-tier reasoning), and reports. Output: a markdown report with concrete suggestions like "drop `audit` to Haiku effort=low — last 30 days averaged 12K tokens, p95 18K, all output was deterministic format conversions."

One table, three surfaces, one reflection skill. See [skills-reference.md](./skills-reference.md) for the full command list.
