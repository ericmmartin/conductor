# Working on Conductor

This file orients any Claude Code session in this repo. Read it first.

## What this is

Conductor is an autonomous SDLC orchestrator for GitHub-based projects. Picks up issues from a Project board, implements them, drives them through Qodo review, ships them. Two packages: a Claude Code plugin (bash skills) and an optional TypeScript daemon.

Start with [`docs/README.md`](./docs/README.md) for the guided index, [`docs/architecture.md`](./docs/architecture.md) for the shape, and [`adrs/`](./adrs/) for the "why" behind each big decision.

## Current state (as of last update)

- **Phase 0 in progress.** Architecture is settled; spike plugin scaffold has landed in `packages/plugin/`; validation against a throwaway issue is pending.
- **Daemon (`packages/orchestrator/`) is empty.** That's Phase 2.
- **GitHub Project #11** on `ericmmartin/conductor` is the source of truth for issue state. Status options: `Backlog`, `Ready`, `In progress`, `In review`, `Done`. Custom Date field: `Ready at`.
- **Six Phase 0 issues** are filed and live on Project #11 in `Ready`. Run `gh issue list -R ericmmartin/conductor --label conductor:ready` to see them with bodies.
- **Repo is public**, MIT-licensed, dogfooded (its own `.conductor/profile.yml` exists).

See [`docs/phased-plan.md`](./docs/phased-plan.md) for what's in each phase.

## How Eric works

- **Eric makes decisions; you execute.** When you hit a design call, surface the tradeoff and ask. Don't silently pick.
- **Don't over-write.** This is a public repo. Never commit secrets, tokens, hardcoded user paths, or internal company references. The `.conductor/profile.yml` model puts sensitive values behind `*_env` field names; literal sensitive values are a validator failure.
- **Don't reach for scripts when direct tools exist.** This is a Claude Code session — you have his shell, his `gh` auth, his filesystem. Use them directly.
- **Be concise.** No long explanations for simple actions. Surface decisions; otherwise just do the work.
- **Models per skill** — when invoking work, use opus/high; address/review/reflect use sonnet/medium; ship/audit/digest use haiku/low; spec and reflect-usage use sonnet/high. Per-issue overrides via `model:` / `effort:` keyword lines in the issue body. See [`docs/usage-gating.md`](./docs/usage-gating.md).

## Constraints to remember

- **GitHub is the source of truth.** Issue state lives in labels + Project status. SQLite (when it exists) is never authoritative.
- **Project status wins on conflict** with labels. Eric manages the board; conductor follows.
- **One issue per project at a time.** Strict sequential within a project. See [`docs/concurrency-model.md`](./docs/concurrency-model.md).
- **One-pass Qodo.** After Qodo's first review, address everything, push, done. Never re-trigger. See [`docs/qodo-integration.md`](./docs/qodo-integration.md).
- **Phase 0–1 is pure bash.** No TS, no npm install needed for the plugin. The shell deps are `gh`, `git`, `yq`, `jq`.

## Immediate next work (Phase 0)

The six Phase 0 issues, in order:

1. **#? — Set up npm workspaces and TypeScript configs.** Infra for Phase 2; not blocking the spike but unblocks #2.
2. **#? — Implement `shared/profile-schema.ts` (Zod).** Source-of-truth schema.
3. **#? — Harden `plugin/lib/profile.sh` with tests.** Already drafted; needs Bats tests.
4. **#? — Harden `plugin/lib/gh.sh` with tests.** Already drafted; needs Bats tests + error-path coverage.
5. **#? — `/conductor:work` spike command.** Already drafted in `packages/plugin/commands/work.md`; needs to actually run.
6. **#? — Validate spike end-to-end.** File a throwaway issue, run `/conductor:work` on it, confirm every step works.

(Run `gh issue list -R ericmmartin/conductor --label conductor:ready` for the real numbers.)

The fastest path to a working spike is to skip ahead to #6's acceptance criteria first — file a throwaway issue and run `/conductor:work` against it. Whatever breaks tells you what to fix in #3–#5. Issues #1 and #2 are infra and can come after.

## Repo structure (the parts that exist)

```
conductor/
├── .conductor/profile.yml          # dogfooded profile
├── README.md                       # public-facing landing
├── LICENSE                         # MIT
├── CHANGELOG.md                    # populated by /conductor:ship eventually
├── docs/                           # 13 docs, see docs/README.md
├── adrs/                           # 6 architecture decision records
├── examples/                       # 3 sample profiles for other repos
└── packages/
    └── plugin/                     # Phase 0 spike: plugin.json + commands/work.md + lib/*.sh
        ├── .claude-plugin/plugin.json
        ├── commands/work.md
        ├── lib/{profile,gh,git,result}.sh
        └── README.md
```

`packages/orchestrator/` and `packages/shared/` don't exist yet. They land in Phase 2.

## When in doubt

Read the relevant doc in `docs/`. If the docs and code disagree, the code is wrong (Phase 0 is too early for the docs to drift). If a design tradeoff comes up that the ADRs don't cover, ask Eric before deciding.
