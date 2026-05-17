# Conductor

Autonomous SDLC orchestrator for GitHub-based projects. Picks up issues from a Project board, implements them, opens PRs, drives them through Qodo review, and ships — with a Claude Code plugin for manual control and an optional daemon for unattended runs.

**Status:** Pre-Phase 0. The architecture is settled; the code is not yet written. See [docs/phased-plan.md](./docs/phased-plan.md).

## What it does

```
Human creates issue in GitHub Project (status: Ready)
         │
         ▼
   ┌───────────────┐    Implements, opens PR, drives Qodo
   │  /work        │    review, addresses feedback, ships
   │  /address     │    (version bump, changelog, tag, release)
   │  /ship        │
   └───────┬───────┘
           │
           ▼
   Merged + released + GitHub Project status: Done
```

The same skills run from your laptop (Claude Code plugin) or from an always-on daemon (NUC, server, wherever). GitHub is the source of truth — labels and Project status are the state machine; the daemon's database is transient operational state.

## Quick install

```bash
# Claude Code plugin (laptop)
claude plugin install github:ericmmartin/conductor#main --path packages/plugin

# Daemon (optional, for unattended runs)
npm install -g github:ericmmartin/conductor#main --workspaces orchestrator
```

To onboard a repo: drop a `.conductor/profile.yml` in it, create a GitHub Project with conductor's status options, run `/conductor:init`. See [docs/github-setup.md](./docs/github-setup.md).

## Documentation

Start with [docs/README.md](./docs/README.md) for a guided index.

For the design rationale and trade-offs behind each major decision, see [adrs/](./adrs/).

## License

[MIT](./LICENSE).
