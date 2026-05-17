# Workflow modes

Two modes declared per-repo in the profile. The orchestrator behaves differently after PR creation based on which is set.

## `ship_when_green` (default for most repos)

1. PR opens. Qodo auto-reviews (because PR author is your user, not a bot — see [qodo-integration.md](./qodo-integration.md#bot-account-mostly-dont)).
2. If Qodo leaves comments, `/conductor:address` enumerates them, fixes valid findings, rebuts invalid ones, files out-of-scope findings as new issues, replies per-comment, and resolves threads.
3. When CI is green, Qodo has been addressed, and any required human reviewers approved, the orchestrator merges and runs `/conductor:ship` (version bump, changelog, tag, release).

## `deploy_and_validate` (for repos that deploy feature branches to staging for QA)

1. Same through PR open + Qodo + address.
2. When CI is green and Qodo addressed, the orchestrator does *not* merge. It posts a "ready for validation" comment on the PR and waits. The CI process itself handles the feature-branch deploy and surfaces the deploy URL.
3. A human validates the feature env and adds the `conductor:validated` label (or comments `/conductor validated`).
4. On `:validated`, the orchestrator merges, ships, etc.

The project's slot is **released** while waiting at the validation gate — see [concurrency-model.md](./concurrency-model.md#slots-and-stalls).

## Configuration

```yaml
# in .conductor/profile.yml
workflow:
  mode: deploy_and_validate
```

Both modes share the same merge/ship logic — they differ only in whether there's a human gate between "PR ready" and "merge."

## No per-issue manual flag

The only pre-merge human gate is `deploy_and_validate` mode at the repo level — used only by repos with a true staging/preview environment that requires human QA before production.

Anything a human wants to verify *after* a merge gets filed as a new issue (a regular `:ready` issue the orchestrator picks up like any other), not as a gate on the original work. Post-deployment verification doesn't pause the orchestrator.

See [ADR 003 — Mandated GitHub Projects](../adrs/003-mandated-gh-projects.md) for related collapse decisions.
