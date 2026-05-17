#!/usr/bin/env bash
# git.sh — git/worktree helpers used by conductor skills.

set -euo pipefail

# git_create_worktree <issue_number>
# Create a worktree at .git/worktrees/issue-<N> with a branch named
# conductor/issue-<N>, based on the profile's default branch.
# Prints the absolute worktree path on success.
git_create_worktree() {
  local issue_number="${1:?git_create_worktree requires an issue number}"
  local branch="conductor/issue-${issue_number}"
  local worktree_path="${CONDUCTOR_REPO_ROOT}/.git/worktrees-out/issue-${issue_number}"

  (
    cd "$CONDUCTOR_REPO_ROOT"
    git fetch origin "$CONDUCTOR_DEFAULT_BRANCH" --quiet
    # If the branch already exists, reuse it. Otherwise create from default branch.
    if git show-ref --verify --quiet "refs/heads/${branch}"; then
      git worktree add -B "$branch" "$worktree_path" "origin/${CONDUCTOR_DEFAULT_BRANCH}" >/dev/null
    else
      git worktree add -b "$branch" "$worktree_path" "origin/${CONDUCTOR_DEFAULT_BRANCH}" >/dev/null
    fi
  )

  echo "$worktree_path"
}

# git_remove_worktree <issue_number>
git_remove_worktree() {
  local issue_number="${1:?git_remove_worktree requires an issue number}"
  local worktree_path="${CONDUCTOR_REPO_ROOT}/.git/worktrees-out/issue-${issue_number}"
  (
    cd "$CONDUCTOR_REPO_ROOT"
    git worktree remove --force "$worktree_path" 2>/dev/null || true
  )
}
