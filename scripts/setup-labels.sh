#!/usr/bin/env bash
# setup-labels.sh — create all conductor labels in the target repo.
#
# Usage:
#   ./scripts/setup-labels.sh [repo-slug]
#
# Default repo is the current dir's gh-detected origin.

set -euo pipefail

REPO_SLUG="${1:-}"
if [[ -z "$REPO_SLUG" ]]; then
  REPO_SLUG="$(gh repo view --json nameWithOwner --jq '.nameWithOwner')"
fi

echo "Creating conductor labels in ${REPO_SLUG}..."

create_label() {
  local name="$1"
  local color="$2"
  local description="$3"
  if gh label list -R "$REPO_SLUG" --search "$name" --json name --jq '.[].name' | grep -Fxq "$name"; then
    echo "  ✓ $name (exists)"
  else
    gh label create "$name" --color "$color" --description "$description" -R "$REPO_SLUG" >/dev/null
    echo "  + $name"
  fi
}

# State labels (mirror Project status)
create_label "conductor:ready"              "0e8a16" "Conductor state: ready to pick up"
create_label "conductor:in-progress"        "1d76db" "Conductor state: being implemented"
create_label "conductor:in-review"          "d4c5f9" "Conductor state: in code review"
create_label "conductor:validating"         "fbca04" "Conductor state: awaiting human validation"
create_label "conductor:validated"          "0e8a16" "Conductor state: human validated, ready to merge"
create_label "conductor:done"               "cccccc" "Conductor state: shipped"

# Block labels (project releases its slot while these are applied)
create_label "conductor:blocked-discovery"  "b60205" "Block: needs human decision"
create_label "conductor:blocked-dependency" "b60205" "Block: cross-project dependency"
create_label "conductor:blocked-review"     "b60205" "Block: Qodo failed to start within timeout"
create_label "conductor:blocked-conflict"   "b60205" "Block: merge conflict"

# Behavior labels
create_label "conductor:qodo-reviewed"      "5319e7" "Qodo has reviewed this PR; do not re-trigger"
create_label "skip-code-review"             "fbca04" "Skip Qodo review for this issue's PR"

echo "✅ Labels ready."
