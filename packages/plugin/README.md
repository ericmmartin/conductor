# conductor-plugin

The Claude Code plugin half of [conductor](https://github.com/ericmmartin/conductor). Skills (commands) work standalone from any machine with `claude` CLI, `gh` CLI, `git`, and `yq` installed.

## Install

```bash
claude plugin install github:ericmmartin/conductor#main --path packages/plugin
```

## Phase 0 status

This is the spike. The only working command is `/conductor:work`, and it does the minimum to validate the end-to-end shell: read a target repo's `.conductor/profile.yml`, claim the named issue, create a worktree, spawn `claude -p` with a one-line prompt, and write a result JSON.

The actual implementation skill, address loop, ship, status — all Phase 1 and later. See [the phased plan](../../docs/phased-plan.md).

## Dependencies

The shell skills depend on:

- `gh` CLI (authenticated to your account)
- `git` (with worktree support)
- `yq` ([mikefarah/yq](https://github.com/mikefarah/yq), v4+)
- `jq`

Install on macOS:

```bash
brew install gh git yq jq
```
