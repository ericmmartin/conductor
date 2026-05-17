#!/usr/bin/env bash
# profile.sh — read .conductor/profile.yml fields via yq
#
# Usage:
#   source "$(dirname "$0")/lib/profile.sh"
#   profile_load /path/to/repo
#   echo "$CONDUCTOR_PROJECT_NUMBER"
#
# Sets these env vars from the profile (caller must `profile_load <repo>` first):
#   CONDUCTOR_PROFILE_PATH       — absolute path to the loaded profile.yml
#   CONDUCTOR_REPO_ROOT          — absolute path to the repo root
#   CONDUCTOR_NAME               — profile.name
#   CONDUCTOR_PROJECT_NUMBER     — profile.project.number
#   CONDUCTOR_STATUS_FIELD       — profile.project.status_field (default: "Status")
#   CONDUCTOR_READY_STATUS       — profile.project.ready_status (default: "Ready")
#   CONDUCTOR_READY_AT_FIELD     — profile.project.ready_at_field (default: "Ready At")
#   CONDUCTOR_DEFAULT_BRANCH     — profile.branches.default
#   CONDUCTOR_AUTHOR             — profile.author (default: "user")
#   CONDUCTOR_WORKFLOW_MODE      — profile.workflow.mode (default: "ship_when_green")

set -euo pipefail

profile_load() {
  local repo_root="${1:?profile_load requires repo path}"
  if [[ ! -d "$repo_root" ]]; then
    echo "profile_load: not a directory: $repo_root" >&2
    return 1
  fi

  local profile_path="${repo_root}/.conductor/profile.yml"
  if [[ ! -f "$profile_path" ]]; then
    echo "profile_load: no .conductor/profile.yml in $repo_root" >&2
    return 1
  fi

  if ! command -v yq >/dev/null 2>&1; then
    echo "profile_load: yq is required (brew install yq)" >&2
    return 1
  fi

  export CONDUCTOR_PROFILE_PATH="$profile_path"
  export CONDUCTOR_REPO_ROOT="$repo_root"
  export CONDUCTOR_NAME="$(yq '.name' "$profile_path")"
  export CONDUCTOR_PROJECT_NUMBER="$(yq '.project.number' "$profile_path")"
  export CONDUCTOR_STATUS_FIELD="$(yq '.project.status_field // "Status"' "$profile_path")"
  export CONDUCTOR_READY_STATUS="$(yq '.project.ready_status // "Ready"' "$profile_path")"
  export CONDUCTOR_READY_AT_FIELD="$(yq '.project.ready_at_field // "Ready At"' "$profile_path")"
  export CONDUCTOR_DEFAULT_BRANCH="$(yq '.branches.default' "$profile_path")"
  export CONDUCTOR_AUTHOR="$(yq '.author // "user"' "$profile_path")"
  export CONDUCTOR_WORKFLOW_MODE="$(yq '.workflow.mode // "ship_when_green"' "$profile_path")"

  if [[ "$CONDUCTOR_NAME" == "null" || -z "$CONDUCTOR_NAME" ]]; then
    echo "profile_load: profile.name is required" >&2
    return 1
  fi
  if [[ "$CONDUCTOR_PROJECT_NUMBER" == "null" || -z "$CONDUCTOR_PROJECT_NUMBER" ]]; then
    echo "profile_load: profile.project.number is required" >&2
    return 1
  fi
}

# profile_get <yq-path> [default]
# Read an arbitrary profile field. Returns default (or empty) if null.
profile_get() {
  local query="${1:?profile_get requires a yq path}"
  local default="${2:-}"
  local value
  value="$(yq "$query" "$CONDUCTOR_PROFILE_PATH" 2>/dev/null || echo "null")"
  if [[ "$value" == "null" || -z "$value" ]]; then
    echo "$default"
  else
    echo "$value"
  fi
}
