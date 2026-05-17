# ADR 003 — Mandated GitHub Projects

**Status:** Accepted
**Date:** 2026-05-15

## Context

The general-purpose predecessor supported two modes of operation:

1. **Label-only mode** — issues live in the repo, no Project board, queue signal is a ready label.
2. **Projects mode** — issues live on a Project board, queue signal is the `Ready` status.

Supporting both was responsible for a meaningful chunk of the predecessor's poller complexity: different queue queries (REST vs GraphQL), different claim strategies (label swap vs status field write), different status-update code paths, different reconciliation logic. The branching ripples through `pr-monitor.ts`, `reconciler.ts`, and the status page.

In practice, every repo we'd want to run conductor on benefits from a Project board — better visibility, custom fields (priority, sprint, owner), and a single canonical view of state. Label-only mode was kept "for simplicity" but added complexity, not removed it.

## Decision

Conductor requires a GitHub Project per repo. No label-only mode. The Project board must have:

- A `Status` single-select field with options including `Ready`, `In progress`, `In review`, `Done` (and `Validating` for repos using `deploy_and_validate` mode). The GH Projects default template provides the first four out of the box. Blocked-ness is tracked via labels, not a status option.
- A `Ready at` custom Date field (orchestrator-written) used as the FIFO sort key.

Labels still exist and are mirrored to the Project status field, but Projects are the source of truth. **On conflict (drift between label and status), Project status wins** — the human manages the board; the orchestrator follows.

## Consequences

**Positive:**
- One queue signal, one claim strategy, one status-update path. Poller drops ~200 LOC of branching.
- Project boards give the human a UI to re-prioritize, re-assign, and see the full system state without leaving GitHub.
- Custom fields (e.g., `Ready at`, sprint, owner) are first-class.

**Negative:**
- Onboarding a repo requires a one-time Project setup. Mitigated by `/conductor:init` scaffolding most of it.
- Repos without a Project literally cannot use conductor. Acceptable given target audience.

## Alternatives considered

- **Keep both modes** — rejected. The complexity tax isn't worth the savings.
- **Project-only with auto-create** — auto-creating a Project on first conductor run is possible but invasive. Better to make the human do it once and confirm.

## Related

- See [github-setup.md](../docs/github-setup.md) for the setup checklist.
- See [concurrency-model.md](../docs/concurrency-model.md#selection-logic-each-cycle) for how the FIFO `Ready at` field is used.
