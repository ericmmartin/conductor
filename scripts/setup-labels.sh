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

# State labels (mirror Project status).
declare -A STATE_LABELS=(
  ["conductor:ready"]="0e8a16"
  ["conductor:in-progress"]="1d76db"
  ["conductor:in-review"]="d4c5f9"
  ["conductor:validating"]="fbca04"
  ["conductor:validated"]="0e8a16"
  ["conductor:done"]="cccccc"
)

# Block labels (project releases its slot while these are applied).
declare -A BLOCK_LABELS=(
  ["conductor:blocked-discovery"]="b60205"
  ["conductor:blocked-dependency"]="b60205"
  ["conductor:blocked-review"]="b60205"
  ["conductor:blocked-conflict"]="b60205"
)

# Behavior labels.
declare -A BEHAVIOR_LABELS=(
  ["conductor:qodo-reviewed"]="5319e7"
  ["skip-code-review"]="fbca04"
)

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

for label in "${!STATE_LABELS[@]}"; do
  create_label "$label" "${STATE_LABELS[$label]}" "Conductor state"
done

for label in "${!BLOCK_LABELS[@]}"; do
  create_label "$label" "${BLOCK_LABELS[$label]}" "Conductor block (releases slot)"
done

create_label "conductor:qodo-reviewed" "5319e7" "Qodo has reviewed this PR; do not re-trigger"
create_label "skip-code-review" "fbca04" "Skip Qodo review for this issue's PR"

echo "✅ Labels ready."
