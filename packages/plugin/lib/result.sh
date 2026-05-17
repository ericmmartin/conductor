#!/usr/bin/env bash
# result.sh — write the result JSON the orchestrator (Phase 2) will read.
#
# Schema (Phase 0 minimum, will grow):
#   {
#     "issue_number": <int>,
#     "status": "done" | "needs_human" | "failed" | "blocked",
#     "pr_number": <int|null>,
#     "branch": <string|null>,
#     "worktree": <string|null>,
#     "tokens_used": <int|null>,
#     "model": <string|null>,
#     "errors": [<string>, ...]
#   }

set -euo pipefail

# result_write <issue_number> <status> [pr_number] [branch] [worktree] [tokens] [model]
result_write() {
  local issue_number="${1:?result_write requires an issue number}"
  local status="${2:?result_write requires a status}"
  local pr_number="${3:-}"
  local branch="${4:-}"
  local worktree="${5:-}"
  local tokens="${6:-}"
  local model="${7:-}"

  local out_dir="${CONDUCTOR_REPO_ROOT}/.conductor/results"
  mkdir -p "$out_dir"
  local out_file="${out_dir}/issue-${issue_number}.json"

  # Build the JSON with jq so quoting is correct.
  jq -n \
    --argjson issue "$issue_number" \
    --arg status "$status" \
    --arg pr_number "$pr_number" \
    --arg branch "$branch" \
    --arg worktree "$worktree" \
    --arg tokens "$tokens" \
    --arg model "$model" '
    {
      issue_number: $issue,
      status: $status,
      pr_number: (if $pr_number == "" then null else ($pr_number | tonumber) end),
      branch:     (if $branch == ""    then null else $branch end),
      worktree:   (if $worktree == ""  then null else $worktree end),
      tokens_used:(if $tokens == ""    then null else ($tokens | tonumber) end),
      model:      (if $model == ""     then null else $model end),
      errors: []
    }
  ' > "$out_file"

  echo "$out_file"
}
