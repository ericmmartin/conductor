# Concurrency model

Conductor's concurrency unit is the **active slot**, not the issue. A slot is "permission to do orchestrator work right now." Default cap: 2.

## The rules

**Within a project, work is strictly sequential.** Once the orchestrator picks an issue in project X, no other issue from project X gets picked up until that issue ships — merged, versioned, tagged, released. This eliminates a conflict problem the predecessor hit on a high-volume repo (10 parallel PRs branching from the same base, inevitable conflicts on merge). Each new branch in a project starts from a base that already includes the previous issue's work.

**Across projects, work is parallel up to the slot cap.** Two projects can have an in-flight issue at the same time. They share the global Claude usage budget (gates apply globally — see [usage-gating.md](./usage-gating.md)), but their queues are independent.

## Slots and stalls

A project **consumes a slot** when it has an in-flight issue the orchestrator can advance (any state where `/work`, `/address`, or `/ship` is the next action).

A project **releases its slot** when its in-flight issue lands in a state where the orchestrator can do nothing more:

- `:validating` — `deploy_and_validate` mode waiting for the `conductor:validated` label.
- `:blocked-discovery` — implementation surfaced something that needs a human decision.
- `:blocked-dependency` — a cross-project dep is broken or its target hasn't merged yet.
- `:blocked-review` — Qodo failed to start within 60s of `/agentic_review` trigger.
- `:blocked-conflict` — merge attempt failed (rare with sequential-per-project).

A stalled project's queue **stays frozen**. The in-flight issue is paused, and no other issue from that project gets picked up. The slot frees so another project can use it.

When the human resolves the block (adds `:validated`, resolves the blocking discovery, or the upstream dep merges), the project re-requests a slot on the next poll. If a slot is free, it claims one and continues the in-flight issue's remaining steps.

See [operational-mechanics.md](./operational-mechanics.md#block-types-and-how-humans-resolve-them) for the human-resolution paths.

## Selection logic each cycle

1. For each project, identify the current state of its in-flight issue (if any). Determine whether the project wants a slot (has orchestrator-actionable work) or doesn't (stalled or fully done).
2. Currently-occupied slots = projects with an active in-flight issue.
3. Available slots = `cap - occupied`.
4. For each idle project, compute its "next issue" by running the DAG scheduler over its `:ready` issues, then FIFO by `Ready at` among the unblocked. (Order is re-computed each cycle, so priority changes humans make on the Project board take effect on the next poll.)
5. Sort idle eligible projects by their next issue's `Ready at` (oldest first).
6. Assign available slots to the head of that list.

## Configuration

```yaml
# ~/.conductor/config.yml
concurrency: 2
repos:
  - ~/projects/project-a
  - ~/projects/project-b
  - ~/projects/personal-app
poll_interval_seconds: 600
```

Per-repo `.conductor/profile.yml` is unchanged. See [profile-reference.md](./profile-reference.md).

## Manual override (plugin mode, anywhere)

The plugin can be invoked from anywhere — your laptop, the NUC console, a separate dev machine. It doesn't need a direct connection to the daemon. Coordination happens entirely through GitHub.

When you run `/conductor:work #42` from any plugin install:

1. The plugin queries GitHub for the issue's current Project status and labels.
2. If status is `In progress` / `In review` / `Validating` (anything between picked-up and shipped), it refuses with a message naming the current state and any associated PR. Pass `--force` to override — you own the conflict risk.
3. Otherwise it attempts to atomically claim the issue by swapping the Project status from `Ready` → `In progress` (and the corresponding label). The swap is the mutex.
4. If the swap succeeds, work proceeds. If it fails (another orchestrator or plugin instance claimed it in between), the plugin reports the conflict and exits cleanly.

No connection to the NUC required. GitHub holds the lock. The daemon's poller treats issues claimed by a plugin instance the same as ones it claimed itself — it sees the `:in-progress` status, knows it's covered, doesn't touch it.

If you `--force`-override and the daemon was already working on the same issue, both runs will produce divergent worktrees and one will lose at PR-creation time. Don't do this unless you have a reason.

## Cross-project dependencies

Supported, with guardrails. Issues can declare cross-repo deps in the body:

```
Dependencies: #41, project-a#42, project-b#17
```

Bare `#N` refers to the current repo. `repo#N` refers to issues in another repo the daemon is watching. The DAG scheduler builds the union graph across all watched repos each cycle; an issue is unblocked only when all its deps are merged (or closed-as-completed).

Guardrails on first observation of a cross-repo dep:

- **Target must exist** — `repo#N` resolves to a real issue. Otherwise: `:blocked-dependency` label + comment.
- **Target must not be closed-without-merge** — if it was abandoned, the dep is permanently broken. Same `:blocked-dependency` treatment.
- **No cycles across the union graph** — if A in repo X depends on B in repo Y, and Y's B depends back on A, the cycle detector catches it and both issues get `:blocked-dependency`.

A project does not consume a slot while one of its issues is `:blocked-dependency` — the issue is waiting on something outside the orchestrator's control.

When the upstream dep merges, the dependent issue is re-evaluated on the next poll and moves to `:ready` automatically. No human intervention needed for the happy path.

## Why this works

The motivating incident was caused by N parallel PRs all forked from the same `main`. The predecessor dispatched them concurrently because its concurrency model was issue-level, not project-level. Sequential per project means: PR A merges → main advances → branch for issue B is created from the new main → no conflict with A's changes. The conflict surface inside a project collapses to whatever the human introduces by hand.

Stalled-frees-the-slot is the design's other key move. Without it, a single `:validating` hold could lock up a slot for days. With it, your throughput degrades gracefully — N stalled projects don't reduce total throughput, they just shift active work to other projects.

The claim step still mutex-locks per-issue via the GitHub label swap, so even if you spin up two daemons against the same repo set, they won't double-claim. The slot cap is per-daemon; two daemons mean 2× slots in aggregate (which you usually don't want — run one daemon).

See [ADR 001 — Slot-based concurrency](../adrs/001-slot-based-concurrency.md) for the full rationale.
