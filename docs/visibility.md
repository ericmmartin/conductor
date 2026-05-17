# Visibility

GitHub is the dashboard. Layered, no UI framework, GitHub-first. Four surfaces, each with a focused job.

## 1. GitHub itself, used deliberately

On every state transition the orchestrator posts (or updates) a *single, structured* comment on the issue: what it did, which skill, which model, how many tokens, current session-utilization at the time, links to PR/worktree. Labels reflect status. Project status field mirrored.

When you open an issue, you see the full operational history inline with the conversation. Routine state transitions update an orchestrator-owned comment in place rather than posting new ones, so the issue's comment timeline stays human-readable.

## 2. Surfacing event log on the GH PR

Two complementary surfaces on the PR itself:

**A maintained "Conductor activity" section in the PR description.** The orchestrator owns a block between `<!-- conductor:start -->` and `<!-- conductor:end -->` markers and rewrites it on every state transition. Always shows the current state, the last action, the most recent skill spawn (model + tokens + duration), and a tiny inline timeline. The PR description is the one place every reviewer looks first, so this surface puts orchestrator status in the right place.

**A single threaded comment on the PR** containing the full event log for that PR. Updated by editing the comment, not by posting new ones. Format: a reverse-chronological list of events with timestamps, skill names, token counts, and any errors. This is the "show me everything" view for debugging.

The combination (PR description block + single threaded comment + per-issue status comment) gives full visibility inside GitHub without spamming notifications or flooding the comments tab.

## 3. Structured JSONL event log

Every state transition, skill spawn, gate trip, and error is one JSON line in `~/.conductor/events.jsonl`. `tail -f`, `jq`, `grep` all work. Stable field names. No log levels theater — one event per real event.

This is the operator's primary debugging surface. When something feels off, this is where you start.

## 4. Tiny static HTML status page

The daemon serves a single static HTML page at `GET /` and the underlying JSON at `GET /status`. About 200 lines, no build step, no framework. Renders:

- Daemon health
- Slot occupancy (X of N)
- Per-project state — active with current issue / stalled with reason / idle with next-issue preview
- Last 20 runs
- Current usage % and which gates are tripped
- FIFO ordering of next 10 projects waiting for a slot
- Tokens by skill (last 7d)

If you outgrow it later, drop in a Next.js app — the JSON contract is the same.

## 5. `/conductor:status` plugin command

Same data, three surfaces. One query module backs all three (status page, JSON endpoint, plugin command).

## Notifications — Teams-Bot + Discord

Teams-Bot threads replies per issue (Microsoft Bot Framework OAuth via `MICROSOFT_APP_ID`/`MICROSOFT_APP_PASSWORD`); each issue gets one root message and all subsequent updates are replies in that thread. Discord posts via incoming webhook. Configure in the profile per-repo:

```yaml
notifications:
  teams_bot:
    channel_id_env: TEAMS_CHANNEL_PROJECT_A     # value lives in env, not committed
    tenant_id_env: MICROSOFT_TENANT_ID
  discord:
    webhook_env: DISCORD_WEBHOOK_PROJECT_A
```

All sensitive values (Teams channel IDs, tenant IDs, webhook URLs) are referenced by env var name. The profile is safe to commit; the values live in env. See [profile-reference.md](./profile-reference.md#whats-safe-to-commit).

What gets notified — high-attention events only:

- **Project stalls** — an in-flight issue moves to `:validating`, `:blocked-discovery`, `:blocked-dependency`, `:blocked-review`, or `:blocked-conflict`. Work in that project has halted until you act.
- State machine errors and gate trips that block work.
- `:validated` request waiting more than 24h.
- Qodo review-changes-requested without auto-response possible.
- Cross-project dependency blocked.

Routine state transitions go to GitHub comments only, not notifications.
