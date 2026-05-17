# GitHub setup

Conductor requires a GitHub Project per repo. Every onboarded repo needs the same setup, scriptable via `/conductor:init`.

## What you need on each repo

1. **A GitHub Project** (org-level or repo-level), with the issue stream added.
2. **A Status single-select field** with these options at minimum: `Ready`, `In progress`, `In review`, `Done`. Add `Validating` only if the repo uses `deploy_and_validate` workflow mode. (The GH Projects default template ships with `Backlog`, `Ready`, `In progress`, `In review`, `Done` — those four required options are already there if you don't rename them. No `Blocked` status needed — blocked-ness is tracked via labels, not status.)
3. **A `Ready at` Date field** (custom) that conductor writes on first observation of each issue at status `Ready`. This is the FIFO sort key — see below. (Field name is case-sensitive and matches whatever you put in the profile.)
4. **The conductor labels** in the repo: `conductor:ready`, `:in-progress`, `:in-review`, `:validating`, `:validated`, `:blocked-discovery`, `:blocked-dependency`, `:blocked-review`, `:blocked-conflict`, `:done`. Plus the optional `skip-code-review` opt-out label if you're using it.
5. **The repo's `.conductor/profile.yml`** with at minimum the `project` section pointing at the above:

```yaml
project:
  number: 1
  status_field: Status
  ready_status: Ready
  ready_at_field: Ready at
```

`/conductor:init` scaffolds steps 3–5 automatically. Steps 1–2 are manual (one-time per repo).

## Why Projects are mandated, not optional

The general-purpose predecessor supported both label-only and Projects modes. That branch was responsible for a meaningful chunk of the poller complexity (different queue signals, different claim strategies, different status-update paths). Mandating Projects collapses this.

See [ADR 003 — Mandated GitHub Projects](../adrs/003-mandated-gh-projects.md).

## Label ↔ Status sync

Sync is bidirectional and atomic at the orchestrator boundary. Every transition does both: label swap + Project status field update, in one logical operation.

A reconciler runs each cycle to fix any drift (humans changing one but not the other from the GH UI). **On conflict, Project status wins** — you manage the board; the orchestrator follows your hand.

## FIFO sort key — `Ready at`

The orchestrator writes a custom `Ready at` Date field to each issue the first time it observes the issue at status `Ready`. That field becomes the FIFO key when multiple idle projects compete for an open slot.

Why not use GitHub's built-in fields:

- `Created` is fixed at issue birth — irrelevant to when work became ready to pick up.
- `Updated` fires on any field change (label edits, comments, custom field tweaks) — too noisy to use as a queue key.
- No built-in status-transition timestamp exists.

A dedicated `Ready at` field is unambiguous and lives in GitHub (source of truth). Humans can adjust it manually from the Project UI to re-prioritize without editing labels or the daemon's DB.

The built-in `Created/Closed/Updated` fields are still worth adding to your Project — they power complementary visibility: `Closed - Created` gives lead time per issue, and `Updated > 7 days ago` flags stale items for the daily digest.

## Cross-project dependencies

Conductor supports cross-repo dependencies declared in the issue body:

```
Dependencies: #41, project-a#42, project-b#17
```

Bare `#N` is the current repo; `repo#N` is another repo the daemon watches. See [concurrency-model.md](./concurrency-model.md#cross-project-dependencies) for the full mechanics and guardrails.

## Authentication

The orchestrator (and each plugin install) uses `gh` CLI's authentication. Default: your own user (`ericmmartin`). The PAT needs scopes for issues, PRs, projects (write to status fields), and labels.

If a repo uses `author: bot` (branch protection requiring a separate approver), add a second PAT for the bot account as `GITHUB_TOKEN_BOT` in env. See [qodo-integration.md](./qodo-integration.md#bot-account-mostly-dont).
