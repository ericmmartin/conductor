# Profile reference

The per-repo profile lives at `.conductor/profile.yml`. Plain YAML — human-friendly, comment-supporting, multiline strings for prose, standard parsers in every language (`yaml` npm package for TS, `yq` for shell). One shared schema defined in `shared/profile-schema.ts` (Zod), one parser, validated on every load.

## Full example

```yaml
# .conductor/profile.yml
name: project-a

stack:
  primary: nextjs
  secondary: python
  db: postgres

project:
  number: 1
  status_field: Status
  ready_status: Ready
  ready_at_field: Ready at

branches:
  default: preview
  pr_target: preview

workflow:
  mode: deploy_and_validate    # alternatives: ship_when_green

review:
  default: required             # alternatives: skip
  skip_label: skip-code-review
  start_wait_seconds: 30        # how long to wait for Qodo before posting /agentic_review

# Default: use the daemon's authenticated user (your account). Qodo auto-fires on PR open.
# Set to `bot` only if branch protection requires a separate approver; you'll then need to
# post /agentic_review manually after PR open to trigger Qodo on bot-authored PRs.
author: user

gates:
  - name: lint
    command: npm run lint
  - name: typecheck
    command: npm run typecheck
  - name: test
    command: npm test
  - name: build
    command: npm run build

reviewers:
  bots:
    - qodo-code-review

models:
  default:
    model: sonnet
    effort: medium
  skills:
    audit:          { model: haiku,  effort: low }
    ship:           { model: haiku,  effort: low }
    digest:         { model: haiku,  effort: low }
    spec:           { model: sonnet, effort: high }
    reflect-usage:  { model: sonnet, effort: high }
    work:           { model: opus,   effort: high }     # default work is heavy
    # address, review, reflect default to sonnet/medium

usage_gates:
  start: 80
  address: 85
  ship: 90

notifications:
  teams_bot:
    channel_id_env: TEAMS_CHANNEL_PROJECT_A     # value lives in env, not committed
    tenant_id_env: MICROSOFT_TENANT_ID
  discord:
    webhook_env: DISCORD_WEBHOOK_PROJECT_A

version:
  source: package.json          # alternatives: pyproject.toml | cargo.toml | git-tag | none
  changelog: keepachangelog     # alternatives: conventional | none

digest:
  output: markdown              # alternatives: notification | both
  schedule: "0 18 * * *"        # daily 6pm

notes: |
  Project A uses deploy-and-validate because feature branches deploy to staging
  for QA before merge. The team is monitored in the Teams channel during business
  hours; Discord is for after-hours alerts only.
```

## Field reference

### `name` (string, required)
The display name of the project. Used in notifications and the status page.

### `stack` (object, required)
- `primary` (string): main stack (`nextjs`, `python`, `node`, `react`, etc.)
- `secondary` (string, optional): secondary stack
- `db` (string, optional): database (`postgres`, `mariadb`, `sqlite`, etc.)

### `project` (object, required)
- `number` (int): GitHub Project number
- `status_field` (string): name of the Status field on the Project board
- `ready_status` (string): the option value that means "pick this up" (typically `Ready`)
- `ready_at_field` (string): the custom Date field conductor writes when it first observes an issue at `ready_status`. Used as the FIFO key.

### `branches` (object, required)
- `default` (string): the base branch new PRs target
- `pr_target` (string): the branch PRs are merged into (often same as default)

### `workflow` (object, required)
- `mode` (`ship_when_green` | `deploy_and_validate`): see [workflow-modes.md](./workflow-modes.md)

### `review` (object, required)
- `default` (`required` | `skip`): the default behavior for new PRs
- `skip_label` / `require_label` (string): the label that flips the default for a specific issue
- `start_wait_seconds` (int, default 30): how long to wait for Qodo's "review in progress" comment before posting `/agentic_review`

### `author` (`user` | `bot`, default `user`)
Whether PRs open as the daemon's authenticated user or a separate bot account. See [qodo-integration.md](./qodo-integration.md#bot-account-mostly-dont).

### `gates` (array, required)
List of quality gate commands. Each entry has `name` and `command`. Gates run in order; failure on any halts the work.

### `reviewers` (object, required)
- `bots` (array of strings): GitHub usernames of bot reviewers conductor watches. Currently only `qodo-code-review` is supported in the address flow.

### `models` (object, required)
- `default.model` and `default.effort`: fallback for any skill not explicitly listed
- `skills` (object): per-skill overrides. Keys are skill names (`work`, `address`, `ship`, etc.); values are `{ model, effort }` objects.

Models: `haiku`, `sonnet`, `opus`. Effort: `low`, `medium`, `high`, `maximum`.

### `usage_gates` (object, optional)
Per-repo overrides for the global thresholds. Defaults are 80/85/90.
- `start` (0-100): skip starting new work above this %
- `address` (0-100): skip addressing PR feedback above this %
- `ship` (0-100): skip shipping above this %

### `notifications` (object, optional)
- `teams_bot.channel_id_env` (string): name of env var holding the Teams channel internal ID
- `teams_bot.tenant_id_env` (string): name of env var holding the Microsoft tenant ID
- `discord.webhook_env` (string): name of env var holding the Discord webhook URL

**All sensitive values are referenced by env var name, never committed as literals.** See the "What's safe to commit" section below.

### `version` (object, required)
- `source` (string): which file holds the version (`package.json`, `pyproject.toml`, `cargo.toml`, `git-tag`, `none`)
- `changelog` (`keepachangelog` | `conventional` | `none`)

### `digest` (object, optional)
- `output` (`markdown` | `notification` | `both`, default `markdown`)
- `schedule` (cron string): when the digest runs

### `notes` (multiline string, optional)
Free-form notes for the humans who read this profile. Not parsed by anything; just for context.

## What's safe to commit

The profile (`.conductor/profile.yml`) is committed to the target repo. It must contain **no sensitive values**, only:

- **Settings** — stack, gates, workflow mode, review behavior, model routing, usage gates, version source. Safe.
- **Env var names** — `webhook_env: DISCORD_WEBHOOK_X`, `channel_id_env: TEAMS_CHANNEL_X`. Safe; the name is just a pointer, not the secret.
- **Public identifiers** — GitHub Project number, status field name, reviewer bot names (`qodo-code-review`), version source file (`package.json`). Safe.

The profile must **not** contain:

- Webhook URLs, tokens, passwords, API keys, OAuth secrets.
- Microsoft tenant IDs, Teams channel IDs, channel webhook URLs.
- Any value you wouldn't want a stranger to have if they cloned your repo.

The Zod schema in `shared/profile-schema.ts` accepts only the `*_env` forms for sensitive fields. If you write `channel_id: "19:xxx@thread.tacv2"` literally, validation fails with a clear error pointing at the offending field. The daemon refuses to start on an invalid profile. The plugin refuses to dispatch skills.

### Local overlay (`.conductor/profile.local.yml`)

For everything that's neither a settings change shared with the team nor a secret (e.g., a debug-mode model override you want to keep to yourself), a `.conductor/profile.local.yml` overlay is loaded after the main profile and merges over it. This file is in the repo's `.gitignore` by default and never committed.

Example:

```yaml
# .conductor/profile.local.yml — gitignored
usage_gates:
  start: 60     # I'm testing; more conservative than team default
models:
  skills:
    work: { model: sonnet, effort: high }   # downgrading from opus locally
```

Add `.conductor/profile.local.yml` to your repo's `.gitignore` (conductor's own `/conductor:init` skill does this automatically).

---

## Per-issue overrides

Stay in the issue body as plain keyword lines (same pattern as `semver: patch`):

```
semver: patch
model: opus
effort: maximum
Dependencies: #41, project-a#42, project-b#17
```

The issue body parser pulls these by line prefix. No structured block needed.

## Daemon config

The daemon itself reads `~/.conductor/config.yml`:

```yaml
concurrency: 2
repos:
  - ~/projects/project-a
  - ~/projects/project-b
  - ~/projects/personal-app
poll_interval_seconds: 600

active_hours:
  timezone: America/Los_Angeles
  windows:
    - days: [Mon, Tue, Wed, Thu, Fri]
      start: "05:00"
      end: "11:00"
  outside_window:
    mode: complete_only
    reduce_concurrency_to: 1

active_pr_poll_seconds: 30
validation_poll_seconds: 300
```

See [usage-gating.md](./usage-gating.md#outside-active-hours) for the active-hours modes.
