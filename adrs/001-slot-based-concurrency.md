# ADR 001 — Slot-based concurrency with strict sequential-per-project

**Status:** Accepted
**Date:** 2026-05-15

## Context

The general-purpose predecessor dispatched issues with concurrency-at-the-issue-level: pick up N ready issues at a time, work them in parallel. On one high-volume repo, this produced 10 PRs all branched off the same `main` simultaneously. As each merged, every subsequent PR developed conflicts. Resolving them turned what should have been hours of orchestration into days of manual conflict surgery.

The root cause: parallel branches off a stale base inevitably conflict. The more parallelism, the worse it scales.

## Decision

Concurrency is **slot-based** with a default cap of 2. A "slot" is permission to do orchestrator work right now, not a permanent assignment.

Within a project, work is **strictly sequential**: once an issue is picked up, no other issue from that project gets picked up until the first ships (merged + versioned + tagged + released). Every new branch in a project therefore starts from a base that already includes the previous issue's work.

Across projects, work is parallel up to the slot cap.

Stalled projects (in-flight issue at `:validating`, `:blocked-*`) release their slot so other projects can use it. The stalled project's own queue stays frozen until the block resolves.

## Consequences

**Positive:**
- The intra-project conflict surface collapses to zero (except for human-introduced conflicts).
- A single stuck issue doesn't choke all parallelism — the slot frees up.
- The "did this work get done?" mental model is clean: one issue per project at a time.

**Negative:**
- Per-project throughput is capped at one-at-a-time. A repo with 20 ready issues processes them serially, not in parallel.
- Stalls can chain: if project X's issue waits 3 days for `:validated`, that slot keeps getting taken by project Y, project Z, etc., and project X just waits.

**Mitigations considered and rejected:**
- *Per-project concurrency override.* Would re-introduce the conflict problem; not worth it.
- *Auto-rebase before merge.* Possible, but adds complexity and isn't reliable when conflicts are semantic, not textual.
- *Priority lanes for stalled projects.* Defer until observed to be a real problem.

## Alternatives considered

- **Issue-level concurrency with auto-rebase** — the predecessor's model plus a rebase step. Rejected because semantic conflicts (e.g., two PRs renaming the same function differently) don't rebase cleanly.
- **One slot per project, no global cap** — would mean N concurrent projects = N concurrent Claude sessions, hard to gate on session utilization.
- **Pure FIFO at the issue level across all repos** — drops project as a coordination unit; same conflict problem as the predecessor.

## Related

- See [concurrency-model.md](../docs/concurrency-model.md) for full mechanics.
- See [ADR 005 — Usage gating, not budgets](./005-usage-gating-not-budgets.md) for how slots interact with global usage gates.
