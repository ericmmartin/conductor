---
name: conductor:work
description: Pick up a Ready issue from the configured Project board, claim it, create a worktree, and dispatch implementation to Claude. Phase 0 spike — minimal end-to-end shell only.
---

# /conductor:work

Spike implementation. Drives a single issue from `Ready` to `In Progress`, creates a worktree, and spawns Claude with a one-line prompt to validate the end-to-end pipeline.

## Usage

```
/conductor:work <issue-number>
```

The current working directory must be the root of the target repo (the one with `.conductor/profile.yml`).

## What this Phase 0 version does

1. Validates the target repo has a `.conductor/profile.yml`.
2. Reads the profile (project number, status field, default branch, etc.).
3. Checks the issue is at status `Ready` on the configured Project board.
4. Claims the issue by atomically swapping Project status `Ready → In Progress` and adding the `conductor:in-progress` label.
5. Creates a git worktree at `.git/worktrees-out/issue-<N>` on a new branch `conductor/issue-<N>` from the profile's default branch.
6. Spawns `claude -p` with a one-line prompt referencing the issue title and body.
7. Writes a result JSON at `.conductor/results/issue-<N>.json`.
8. Posts a "spike complete" comment on the issue.

## What this Phase 0 version does NOT do

These come later phases:

- Run the quality gates from the profile (Phase 1).
- Run subagent reviewers (Phase 1).
- Open a PR (Phase 1).
- Address Qodo feedback (Phase 3).
- Ship/merge/version-bump (Phase 1 for /ship, Phase 3 for the full flow).
- Set the `Ready At` Project field (Phase 2 — daemon's job).
- Handle session-utilization gates (Phase 2).

## Implementation

```bash
#!/usr/bin/env bash
set -euo pipefail

ISSUE_NUMBER="${1:?Usage: /conductor:work <issue-number>}"

PLUGIN_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
source "${PLUGIN_DIR}/lib/profile.sh"
source "${PLUGIN_DIR}/lib/gh.sh"
source "${PLUGIN_DIR}/lib/git.sh"
source "${PLUGIN_DIR}/lib/result.sh"

# Resolve the repo root (current working dir, must contain .conductor/profile.yml).
REPO_ROOT="$(pwd)"
profile_load "$REPO_ROOT"

echo "📋 conductor:work spike — issue #${ISSUE_NUMBER} in ${CONDUCTOR_NAME}"

# 1. Claim the issue (atomic Project status swap).
echo "🔒 Claiming issue..."
if ! gh_claim_issue "$ISSUE_NUMBER"; then
  echo "❌ Failed to claim issue. Check that it's in Ready status on Project #${CONDUCTOR_PROJECT_NUMBER}."
  exit 1
fi

# 2. Create worktree.
echo "🌳 Creating worktree..."
WORKTREE_PATH="$(git_create_worktree "$ISSUE_NUMBER")"
BRANCH="conductor/issue-${ISSUE_NUMBER}"
echo "   → ${WORKTREE_PATH}"

# 3. Fetch issue context.
ISSUE_TITLE="$(gh_issue_title "$ISSUE_NUMBER")"
ISSUE_BODY="$(gh_issue_body "$ISSUE_NUMBER")"

# 4. Spawn Claude with a minimal prompt (spike — proves the wiring, not the implementation).
echo "🤖 Spawning Claude..."
PROMPT="You are working on GitHub issue #${ISSUE_NUMBER}: ${ISSUE_TITLE}

Issue body:
${ISSUE_BODY}

This is the Phase 0 spike of conductor. Do not implement anything yet — just acknowledge that you received the issue context and print a one-line summary of what you would do."

CLAUDE_OUTPUT="$(cd "$WORKTREE_PATH" && claude -p "$PROMPT" --output-format json 2>&1 || echo '{"error": "claude invocation failed"}')"

# 5. Write result JSON.
RESULT_FILE="$(result_write "$ISSUE_NUMBER" "done" "" "$BRANCH" "$WORKTREE_PATH" "" "spike")"
echo "📝 Result written to ${RESULT_FILE}"

# 6. Post a completion comment.
gh_post_comment "$ISSUE_NUMBER" "Conductor spike completed end-to-end on commit $(git -C "$WORKTREE_PATH" rev-parse --short HEAD). Worktree at \`${WORKTREE_PATH}\`. Claude output captured in \`${RESULT_FILE}\`. This is Phase 0 — no real implementation work was attempted."

echo "✅ Spike complete for issue #${ISSUE_NUMBER}"
```
