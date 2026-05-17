# Conductor — Documentation

## Start here

- **[Architecture](./architecture.md)** — what conductor is, the three-piece shape, what it ports from its predecessors, what it deliberately doesn't do.
- **[Phased plan](./phased-plan.md)** — what gets built when, in what order, with stop-and-reassess points.

## How the system runs

- **[Concurrency model](./concurrency-model.md)** — slot-based, strictly sequential within a project, FIFO across competing projects.
- **[Workflow modes](./workflow-modes.md)** — `ship_when_green` vs `deploy_and_validate`.
- **[Usage gating](./usage-gating.md)** — 80/85/90 thresholds on Claude session utilization, model routing, active hours, post-reset behavior, per-skill token tracking.
- **[Qodo integration](./qodo-integration.md)** — review trigger flow, one-pass-only semantics, comment-by-comment address.
- **[GitHub setup](./github-setup.md)** — mandated Project board, label/status sync, `Ready At` FIFO key, cross-project dependencies.
- **[Operational mechanics](./operational-mechanics.md)** — adaptive polling, block types, manual override from anywhere, Drizzle migration conflicts.
- **[Visibility](./visibility.md)** — how to see what conductor is doing across GitHub, JSONL logs, a tiny status page, and notifications.
- **[Periodic skills](./periodic-skills.md)** — daily digest of shipped issues, backlog triage (Phase 6).

## Reference

- **[Profile reference](./profile-reference.md)** — full `.conductor/profile.yml` schema.
- **[Skills reference](./skills-reference.md)** — every `/conductor:*` command.

## Why we made the calls we made

See [adrs/](../adrs/) for short Architecture Decision Records on the big trade-offs.
