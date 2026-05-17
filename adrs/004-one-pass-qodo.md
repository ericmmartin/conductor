# ADR 004 — One-pass Qodo

**Status:** Accepted
**Date:** 2026-05-15

## Context

Qodo (`qodo-code-review`) is the only code-review reviewer in scope today. It doesn't use GitHub's formal "request changes" review mechanism — it posts inline comments on the diff plus a summary comment.

The natural orchestrator pattern would be: detect Qodo's review, run `/conductor:address` to fix findings, push the fix, **wait for Qodo to re-review the fix**, address again if needed, loop until clean. This is the back-and-forth pattern most code-review tools assume.

That pattern has two real problems:
1. **Unbounded loop risk.** Qodo could keep finding things, especially as the address pass introduces new code. Each iteration costs Claude tokens.
2. **Time-to-merge balloons.** A PR with 3 round-trips through Qodo could sit in `:in-review` for hours, blocking the project's slot.

## Decision

Conductor runs Qodo **once per PR**. The flow:

1. PR opens. Orchestrator waits 30s for Qodo to start auto-reviewing.
2. If Qodo doesn't start, post `/agentic_review` from the authenticated user account.
3. Wait for Qodo's final review comment.
4. Dispatch `/conductor:address` with the full set of comments. Address fixes them in one pass, replies per-comment, resolves threads.
5. Proceed to merge (or `:validating` for `deploy_and_validate` mode).

The orchestrator does **not** trigger Qodo again. The comment-existence check at the start of the trigger flow ensures even repeated polls don't re-trigger — once a `qodo-code-review` final review comment exists on the PR, the flow short-circuits to address.

Any new issues introduced by the address commits are caught by CI or by human review at merge time.

## Consequences

**Positive:**
- Predictable PR latency. One review, one address, ship.
- No risk of Qodo loops eating tokens indefinitely.
- The orchestrator's PR state machine has fewer states.

**Negative:**
- If `/conductor:address` genuinely misses something Qodo would have caught on a second pass, that issue ships and has to be fixed in a follow-up PR.
- For high-quality-bar projects, a human might want a second Qodo pass; conductor doesn't offer that automatically. Workaround: human comments `/agentic_review` themselves; conductor sees the new review and re-runs `/conductor:address`.

## Alternatives considered

- **N passes** — bounded loop (e.g., max 3 passes). Adds complexity, only marginally safer than 1 pass.
- **Re-trigger if the address commit is "large"** — heuristic, brittle.
- **Always re-trigger, but block the loop with usage gates** — relies on gates as a circuit breaker, which is the wrong layer for the abstraction.

## Related

- See [qodo-integration.md](../docs/qodo-integration.md#addressing-qodos-findings) for the full flow.
