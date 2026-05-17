# ADR 005 — Usage gating, not budgets

**Status:** Accepted
**Date:** 2026-05-15

## Context

The general-purpose predecessor tracked dollars: per-issue cost caps, monthly hard caps, a pre-flight estimator that tried to predict how much an issue would cost before spawning Claude, a `budget:` tag on issues for per-issue overrides. The system reported MTD spend, alerted on budget breaches, paused on the monthly hard cap.

In practice this was theater. The actual constraint on conductor's operation isn't dollars (the marginal cost per issue is small relative to any meaningful budget cap) — it's **Claude session token utilization**. When the 5h utilization window approaches its limit, no amount of remaining dollar budget matters; the next Claude call will fail or be throttled.

Tracking and gating on dollars created a second-class signal that didn't drive operational behavior. The system needed both: budget guards (to satisfy the abstraction) AND usage probes (to actually decide what to do). Two systems, one source of truth.

## Decision

Conductor tracks Claude session utilization. Three gates, asymmetric:

| Action | Skip if usage ≥ |
|---|---|
| Start new work | 80% |
| Address PR feedback | 85% |
| Ship | 90% |

Above 90%, the daemon idles. Below 80%, all actions are allowed.

**The entire dollar-based budget layer is deleted.** No per-issue caps, no monthly caps, no pre-flight estimator, no `budget:` tag.

Issues that need more Claude resource get a heavier model (`model: opus`) or more effort (`effort: maximum`) per-issue, not a bigger dollar cap.

The usage probe lives in `packages/orchestrator/src/gates/usage.ts`, ported from the project-specific predecessor's session-limit module (attributed to [nsanden/claude-rate-monitor](https://github.com/nsanden/claude-rate-monitor)).

## Consequences

**Positive:**
- One signal, one decision pathway. No dual-source-of-truth confusion.
- The probe directly reflects what would actually break the orchestrator (session exhaustion), not a proxy.
- Asymmetric thresholds preserve headroom for in-flight work to complete, which is the right value tradeoff.
- The token-usage attribution table is kept (for `/conductor:reflect-usage` and post-hoc analysis) — we still know per-skill token spend, we just don't gate on dollars derived from it.

**Negative:**
- No "I want to spend at most $X this month" affordance. If you care about dollars, observe the spend (via `/conductor:usage` and ccusage) and adjust the gates or model defaults.
- The probe depends on the Claude OAuth credentials file being readable (`~/.claude/.credentials.json`). Acceptable for the target deployment (NUC or laptop with the user logged in).

## Alternatives considered

- **Keep budgets, drop usage gates** — leaves the real failure mode (session exhaustion) unguarded.
- **Both** — dual-source-of-truth; rejected as the predecessor already proved this is overhead.
- **Token bucket per skill** — interesting but adds a layer between the probe and the gate; not worth it for the gain.

## Related

- See [usage-gating.md](../docs/usage-gating.md) for the full mechanics.
- See the predecessor's session-limit module for the probe code being ported.
