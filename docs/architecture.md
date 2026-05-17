# Architecture

Conductor is an autonomous SDLC orchestrator that picks up issues from a GitHub Project board, implements them, opens PRs, drives them through Qodo review, and ships — with a Claude Code plugin for manual control and an optional daemon for unattended runs.

It's a successor to two earlier orchestrators built by the same author — one general-purpose and feature-complete but with too much accumulated abstraction surface, and one project-specific and lean but hardwired to its host repo. Conductor keeps the parts that proved durable in both and drops what didn't pay rent.

## The three pieces

```
┌────────────────────────────────────────────────────────────────┐
│             GitHub (source of truth, mandated Projects)        │
│   Issues · Labels ⇄ Project Status · PRs · Reviews · Comments  │
└──────────────────▲──────────────────────────────▲──────────────┘
                   │                              │
        ┌──────────┴──────────┐        ┌──────────┴──────────┐
        │   packages/plugin/  │        │ packages/orchestrator/
        │   (Claude Code,     │        │ (optional daemon,    │
        │    bash skills)     │◄──────►│  TS, Node 22+,       │
        │                     │ result │  multi-repo, FIFO)   │
        │  /spec  /work       │  json  │                      │
        │  /address /ship     │        │  poller              │
        │  /review /reflect   │        │  scheduler (DAG)     │
        │  /audit  /status    │        │  usage gates × 4     │
        │                     │        │  pr-monitor (Qodo)   │
        └──────────┬──────────┘        └──────────┬──────────┘
                   │                              │
                   └──────────┬───────────────────┘
                              ▼
                   ┌─────────────────────┐
                   │  shared state       │
                   │  - profile.yml      │ ← per repo, in repo
                   │  - .conductor/db    │ ← orchestrator only (Drizzle/SQLite)
                   │  - events.jsonl     │
                   └─────────────────────┘
```

Skills are stateless and write a tight result JSON. The orchestrator is optional but expected for unattended runs. State lives in three places: GitHub (canonical), the per-repo `profile.yml` (declarative config), and the orchestrator's SQLite (transient operational state, never authoritative).

## What ports from the general-purpose predecessor

- **Skill + profile model.** Skills are self-contained, profiles are per-repo declarative. One TS function in `shared/` reads the profile and returns a typed object, used identically by skills (via a small shell helper) and the orchestrator.
- **Label-based state machine on GitHub.** Labels are atomic and visible. The claim-via-label-swap pattern is sound; every label change is also mirrored to the GitHub Project status field in the same operation. See [github-setup.md](./github-setup.md).
- **Subagent review prompts as editable markdown** in `.conductor/reviewers/`. Defaults shipped with the plugin; copied into each repo on `/conductor:init` so teams can edit per-project.
- **Quality gates as bash commands declared in the profile** — port verbatim. This was the cleanest portability mechanism in the predecessor.
- **Slim mode / full mode split.** Plugin works without daemon; daemon drives the same skills.

## What ports from the project-specific predecessor

- **DAG scheduler** (`detectCycles`, `selectRunnableIssues`). Issues declare `Dependencies: #41, repo#42` in the body; scheduler resolves topological order and only dispatches what's unblocked.
- **Qodo review loop** — actually wired in the predecessor today. Port the working code: PR monitor watches for `qodo-code-review` review threads, triggers `/conductor:address`, validates response stays in scope, creates new issues for out-of-scope findings. Reviewer identity is a profile field.
- **Result-file handoff**: skills write `results/issue-{N}.json` with a small schema; the orchestrator reads asynchronously.
- **Graceful shutdown** (SIGTERM → drain → 10-min timeout → force-kill) and **timezone-aware active-hours**.
- **Issue body parser** (deps including cross-repo refs, `semver:`, `model:` overrides) as a pure function.
- **Session-utilization probe**, adapted from [nsanden/claude-rate-monitor](https://github.com/nsanden/claude-rate-monitor). Port as-is, preserve attribution.

## What conductor deliberately does NOT do

These exist in one or both of the predecessors and were intentionally cut. See [adrs/](../adrs/) for the reasoning per-decision.

- **Five of seven notification providers.** Keep `teams-bot.ts` (Bot Framework OAuth, threaded replies) and `discord.ts` (webhook). Drop regular `teams.ts` webhook (no threading), Slack, generic-webhook, SMTP, Resend.
- **HTML-string-template dashboard.** See [visibility.md](./visibility.md) for what replaced it.
- **Raw-SQL-string schema with no migrations.** Drizzle from day one.
- **Four separate audit skills.** One `/conductor:audit` that dispatches per ecosystem.
- **30-field result envelope.** Trim to `issue_number`, `status`, `pr_number?`, `branch?`, `worktree?`, `tokens_used`, `model`, `errors[]`.
- **Speculative profile knobs**: `worktree_mode`, `authorship_model: split`, `conflict_strategy: notify`, `peak_avoidance`. None survive.
- **Embedded self-update logic.** Once extracted, install via GitHub and update via `npm update`.
- **Daily `docs/summaries/{date}.md` commit pattern.** Replaced by JSONL event log and the `/conductor:digest` skill.
- **Label-only mode** (operating on issues without a Project). Projects are mandated.
- **The entire budget layer** — per-issue caps, monthly caps, pre-flight estimator, `budget:` tags. Replaced by usage-aware gating. See [usage-gating.md](./usage-gating.md).
- **The `[manual]` flag on issues.** The only pre-merge human gate is `deploy_and_validate` mode at the repo level.

## What it gives you, concretely

One tool, same shape on every project. Drop a `.conductor/profile.yml` into a repo, install the plugin (and optionally the daemon), point it at a GitHub Project, and the SDLC loop runs. The general-purpose predecessor's flexibility lives in the profile, not in the code. The project-specific predecessor's discipline lives in the orchestrator, not in the repo.
