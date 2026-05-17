#!/usr/bin/env bash
# gh.sh — GitHub wrappers used by conductor skills.
#
# Requires: gh CLI (authenticated), jq.
# Loads after profile.sh so CONDUCTOR_* env vars are set.

set -euo pipefail

# gh_issue_status <issue_number>
# Prints the issue's current Project status (e.g., "Ready", "In Progress").
# Empty string if the issue is not on the project board.
gh_issue_status() {
  local issue_number="${1:?gh_issue_status requires an issue number}"
  local repo
  repo="$(_gh_repo_slug)"

  gh api graphql -f query='
    query($owner: String!, $repo: String!, $number: Int!) {
      repository(owner: $owner, name: $repo) {
        issue(number: $number) {
          projectItems(first: 20) {
            nodes {
              project { number }
              fieldValues(first: 20) {
                nodes {
                  ... on ProjectV2ItemFieldSingleSelectValue {
                    field { ... on ProjectV2SingleSelectField { name } }
                    name
                  }
                }
              }
            }
          }
        }
      }
    }
  ' -F owner="${repo%/*}" -F repo="${repo#*/}" -F number="$issue_number" \
    | jq -r --arg field "$CONDUCTOR_STATUS_FIELD" --argjson proj "$CONDUCTOR_PROJECT_NUMBER" '
        .data.repository.issue.projectItems.nodes
        | map(select(.project.number == $proj))
        | first
        | .fieldValues.nodes[]?
        | select(.field.name == $field)
        | .name
      '
}

# gh_claim_issue <issue_number>
# Atomically claim by swapping Project status from Ready → In Progress.
# Returns 0 on success, non-zero if the issue isn't in Ready state.
gh_claim_issue() {
  local issue_number="${1:?gh_claim_issue requires an issue number}"
  local current
  current="$(gh_issue_status "$issue_number")"
  if [[ "$current" != "$CONDUCTOR_READY_STATUS" ]]; then
    echo "gh_claim_issue: issue #${issue_number} is not Ready (current: ${current:-not on board})" >&2
    return 1
  fi
  gh_set_status "$issue_number" "In Progress"
  gh_add_label "$issue_number" "conductor:in-progress"
}

# gh_set_status <issue_number> <status_name>
# Set the Project Status field to a given option name.
gh_set_status() {
  local issue_number="${1:?gh_set_status requires an issue number}"
  local status_name="${2:?gh_set_status requires a status name}"
  local repo
  repo="$(_gh_repo_slug)"

  # Fetch project + field IDs, and the option ID for the target status.
  local meta
  meta="$(gh api graphql -f query='
    query($owner: String!, $repo: String!, $number: Int!) {
      repository(owner: $owner, name: $repo) {
        issue(number: $number) {
          projectItems(first: 20) {
            nodes {
              id
              project {
                id
                number
                fields(first: 50) {
                  nodes {
                    ... on ProjectV2SingleSelectField {
                      id
                      name
                      options { id name }
                    }
                  }
                }
              }
            }
          }
        }
      }
    }
  ' -F owner="${repo%/*}" -F repo="${repo#*/}" -F number="$issue_number")"

  local item_id project_id field_id option_id
  item_id="$(jq -r --argjson proj "$CONDUCTOR_PROJECT_NUMBER" '
    .data.repository.issue.projectItems.nodes[] | select(.project.number == $proj) | .id
  ' <<<"$meta")"
  project_id="$(jq -r --argjson proj "$CONDUCTOR_PROJECT_NUMBER" '
    .data.repository.issue.projectItems.nodes[] | select(.project.number == $proj) | .project.id
  ' <<<"$meta")"
  field_id="$(jq -r --argjson proj "$CONDUCTOR_PROJECT_NUMBER" --arg field "$CONDUCTOR_STATUS_FIELD" '
    .data.repository.issue.projectItems.nodes[] | select(.project.number == $proj) | .project.fields.nodes[] | select(.name == $field) | .id
  ' <<<"$meta")"
  option_id="$(jq -r --argjson proj "$CONDUCTOR_PROJECT_NUMBER" --arg field "$CONDUCTOR_STATUS_FIELD" --arg target "$status_name" '
    .data.repository.issue.projectItems.nodes[] | select(.project.number == $proj) | .project.fields.nodes[] | select(.name == $field) | .options[] | select(.name == $target) | .id
  ' <<<"$meta")"

  if [[ -z "$item_id" || -z "$project_id" || -z "$field_id" || -z "$option_id" ]]; then
    echo "gh_set_status: failed to resolve Project metadata for issue #${issue_number} (status: ${status_name})" >&2
    return 1
  fi

  gh api graphql -f query='
    mutation($project: ID!, $item: ID!, $field: ID!, $option: String!) {
      updateProjectV2ItemFieldValue(input: {
        projectId: $project, itemId: $item, fieldId: $field,
        value: { singleSelectOptionId: $option }
      }) { projectV2Item { id } }
    }
  ' -F project="$project_id" -F item="$item_id" -F field="$field_id" -F option="$option_id" >/dev/null
}

# gh_set_ready_at <issue_number>
# Write the current ISO date to the Ready At Date field. Idempotent (skip if already set).
gh_set_ready_at() {
  local issue_number="${1:?gh_set_ready_at requires an issue number}"
  # TODO Phase 2 — the daemon writes this on first observation at Ready. The plugin spike doesn't need it.
  return 0
}

# gh_add_label <issue_number> <label>
gh_add_label() {
  local issue_number="${1:?gh_add_label requires an issue number}"
  local label="${2:?gh_add_label requires a label}"
  gh issue edit "$issue_number" --add-label "$label" >/dev/null
}

# gh_remove_label <issue_number> <label>
gh_remove_label() {
  local issue_number="${1:?gh_remove_label requires an issue number}"
  local label="${2:?gh_remove_label requires a label}"
  gh issue edit "$issue_number" --remove-label "$label" >/dev/null
}

# gh_post_comment <issue_number> <body>
gh_post_comment() {
  local issue_number="${1:?gh_post_comment requires an issue number}"
  local body="${2:?gh_post_comment requires a body}"
  gh issue comment "$issue_number" --body "$body" >/dev/null
}

# gh_issue_body <issue_number>
# Print the issue body to stdout.
gh_issue_body() {
  local issue_number="${1:?gh_issue_body requires an issue number}"
  gh issue view "$issue_number" --json body --jq '.body'
}

# gh_issue_title <issue_number>
gh_issue_title() {
  local issue_number="${1:?gh_issue_title requires an issue number}"
  gh issue view "$issue_number" --json title --jq '.title'
}

# Internal: derive owner/repo from the current git remote.
_gh_repo_slug() {
  ( cd "$CONDUCTOR_REPO_ROOT" && gh repo view --json nameWithOwner --jq '.nameWithOwner' )
}
