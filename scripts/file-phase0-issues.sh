#!/usr/bin/env bash
# file-phase0-issues.sh — file the six Phase 0 issues in the conductor repo.
#
# Usage:
#   ./scripts/file-phase0-issues.sh [repo-slug] [project-number]
#
# - repo-slug defaults to the current gh-detected origin.
# - project-number, if provided, adds each issue to that Project and sets it to Ready.
#   If omitted, issues are created in the repo only; you'll add them to the project manually.

set -euo pipefail

REPO_SLUG="${1:-}"
PROJECT_NUMBER="${2:-}"
if [[ -z "$REPO_SLUG" ]]; then
  REPO_SLUG="$(gh repo view --json nameWithOwner --jq '.nameWithOwner')"
fi
REPO_OWNER="${REPO_SLUG%/*}"

echo "Filing Phase 0 issues in ${REPO_SLUG}..."
if [[ -n "$PROJECT_NUMBER" ]]; then
  echo "Will add to Project #${PROJECT_NUMBER} and set Status=Ready."
else
  echo "Skipping Project add (no project number given)."
fi

# Helper: create an issue with title + body file, optionally add to Project.
create_issue() {
  local title="$1"
  local body="$2"
  local labels="$3"

  local issue_url
  issue_url="$(gh issue create -R "$REPO_SLUG" --title "$title" --body "$body" --label "$labels")"
  local issue_number="${issue_url##*/}"
  echo "  + #${issue_number}: ${title}"

  if [[ -n "$PROJECT_NUMBER" ]]; then
    # Add to project
    gh project item-add "$PROJECT_NUMBER" --owner "$REPO_OWNER" --url "$issue_url" >/dev/null
    # Set Status field to Ready — uses field/option name resolution
    local item_id
    item_id="$(gh project item-list "$PROJECT_NUMBER" --owner "$REPO_OWNER" --format json --limit 200 \
      | jq -r --arg url "$issue_url" '.items[] | select(.content.url == $url) | .id')"
    local field_id option_id
    field_id="$(gh project field-list "$PROJECT_NUMBER" --owner "$REPO_OWNER" --format json \
      | jq -r '.fields[] | select(.name == "Status") | .id')"
    option_id="$(gh project field-list "$PROJECT_NUMBER" --owner "$REPO_OWNER" --format json \
      | jq -r '.fields[] | select(.name == "Status") | .options[] | select(.name == "Ready") | .id')"
    gh project item-edit --id "$item_id" --project-id "$(gh project view "$PROJECT_NUMBER" --owner "$REPO_OWNER" --format json | jq -r '.id')" \
      --field-id "$field_id" --single-select-option-id "$option_id" >/dev/null
  fi

  echo "$issue_number"
}

# --- Phase 0 issue bodies ---

ISSUE_1=$(cat <<'EOF'
## Goal
Stand up the monorepo skeleton so subsequent Phase 0 issues have a place to land code.

## Acceptance criteria
- Root `package.json` with npm workspaces declaring `packages/*`
- `packages/plugin/package.json` (no deps yet beyond what the spike needs)
- `packages/orchestrator/package.json` (stub; populated in Phase 2)
- `packages/shared/package.json` (stub; populated in Phase 2)
- `tsconfig.base.json` at the root with shared strict-mode settings
- Per-package `tsconfig.json` extending the base
- `pnpm-workspace.yaml` or equivalent (whatever package manager we settle on)

## Notes
The plugin (Phase 0–1) is pure bash and doesn't actually need TypeScript yet. The TS setup is forward-looking for the orchestrator (Phase 2) and the shared types package. Setting it up now means Phase 2 work doesn't get derailed by infra.

## Out of scope
- Drizzle schema (Phase 2)
- Actual TS source files (Phase 1+)

semver: minor
EOF
)

ISSUE_2=$(cat <<'EOF'
## Goal
Define and validate the `.conductor/profile.yml` schema in one place, used by both the orchestrator (Phase 2 TS) and the plugin (Phase 0+ bash).

## Acceptance criteria
- `packages/shared/src/profile-schema.ts` exports a Zod schema for the full profile (see `docs/profile-reference.md`)
- All sensitive fields are `*_env` only (validator rejects literal `channel_id`, `tenant_id`, etc.)
- `loadProfile(path: string): Profile` reads + validates + returns typed object
- Unit tests covering: valid profile loads cleanly, invalid profile (missing required field) fails with a clear error, profile with a literal sensitive value fails with a pointer to the offending field

## Notes
This is the source-of-truth schema. The shell `lib/profile.sh` reader is a parallel implementation for `yq`-based access; both must stay consistent with what this Zod schema accepts.

Dependencies: #1

semver: minor
EOF
)

ISSUE_3=$(cat <<'EOF'
## Goal
Bash-side profile reader used by all shell skills. Already stubbed in the Phase 0 spike; this issue is to harden it and add coverage.

## Acceptance criteria
- `packages/plugin/lib/profile.sh` exposes `profile_load`, `profile_get`, and the documented `CONDUCTOR_*` env vars
- Validates required fields the same way the Zod schema does (name, project.number)
- Bats (or equivalent) test file: `packages/plugin/lib/profile.test.sh`
- Tests cover: valid profile loads, missing file errors clearly, missing required field errors clearly, default values applied for optional fields

## Notes
Keep behavior in sync with `shared/src/profile-schema.ts` (#2). When that schema changes, this reader changes too — or the Zod schema should be the only source and the shell side reads via a Node helper.

Dependencies: #2

semver: patch
EOF
)

ISSUE_4=$(cat <<'EOF'
## Goal
Minimal gh CLI wrappers for the operations skills need: claim, status update, comment, label, body fetch.

## Acceptance criteria
- `packages/plugin/lib/gh.sh` exposes: `gh_issue_status`, `gh_claim_issue`, `gh_set_status`, `gh_add_label`, `gh_remove_label`, `gh_post_comment`, `gh_issue_body`, `gh_issue_title`
- Atomic claim: `gh_claim_issue` only succeeds if the issue is currently `Ready`; concurrent claims fail cleanly with non-zero exit
- All functions tolerate non-existent issues and surface a clear error message
- Bats test file with mocked `gh` for the happy paths and the failure paths

## Notes
The Phase 0 spike already has a working draft. This issue is to test it, harden the error handling, and add the missing functions for Phase 1 (PR creation, etc., come in #5 not here).

Dependencies: #1

semver: patch
EOF
)

ISSUE_5=$(cat <<'EOF'
## Goal
The spike `/conductor:work` command — minimal end-to-end pipeline. Validates the shell works before adding actual implementation logic in Phase 1.

## Acceptance criteria
- `packages/plugin/commands/work.md` exists with the conductor:work command
- Running `/conductor:work <issue-number>` on a real `:ready` issue:
  - Reads the profile from cwd's `.conductor/profile.yml`
  - Claims the issue (Project status `Ready` → `In progress`, adds `conductor:in-progress` label)
  - Creates a worktree at `.git/worktrees-out/issue-<N>` on branch `conductor/issue-<N>` from the default branch
  - Spawns `claude -p` with a one-line prompt referencing the issue title and body
  - Writes `results/issue-<N>.json` matching the minimum schema
  - Posts a "spike completed" comment on the issue
- Failure modes handled gracefully: issue not ready, profile missing, worktree path conflict

## Notes
The Phase 0 spike implementation is already drafted. This issue closes when we've actually run it against a real throwaway issue and confirmed every step works.

Dependencies: #3, #4

semver: minor
EOF
)

ISSUE_6=$(cat <<'EOF'
## Goal
End-to-end validation of the Phase 0 spike on a throwaway issue. The goal isn't to ship anything real — it's to prove the shell works.

## Acceptance criteria
- File a throwaway issue (e.g., "Test conductor:work spike") and set it to Ready on the Project board
- Run `/conductor:work <throwaway-issue-number>` from a freshly cloned conductor repo
- Confirm: Project status moves to In progress, `conductor:in-progress` label is applied, a worktree is created at the expected path, Claude is invoked and writes its result JSON, the spike-complete comment is posted
- Document any rough edges encountered as new issues (Phase 1 polish)

## Notes
This is the Phase 0 exit criteria. When this issue ships, Phase 0 is done and Phase 1 can begin.

Dependencies: #5

semver: patch
EOF
)

# --- Create them ---

NUM_1=$(create_issue "Phase 0: Set up npm workspaces and TypeScript configs" "$ISSUE_1" "conductor:ready")
NUM_2=$(create_issue "Phase 0: Implement shared/profile-schema.ts (Zod)" "$ISSUE_2" "conductor:ready")
NUM_3=$(create_issue "Phase 0: Harden plugin/lib/profile.sh with tests" "$ISSUE_3" "conductor:ready")
NUM_4=$(create_issue "Phase 0: Harden plugin/lib/gh.sh with tests" "$ISSUE_4" "conductor:ready")
NUM_5=$(create_issue "Phase 0: /conductor:work spike command" "$ISSUE_5" "conductor:ready")
NUM_6=$(create_issue "Phase 0: Validate spike end-to-end on a throwaway issue" "$ISSUE_6" "conductor:ready")

echo ""
echo "✅ Filed Phase 0 issues:"
echo "   #${NUM_1}: workspaces"
echo "   #${NUM_2}: profile-schema.ts (deps: #${NUM_1})"
echo "   #${NUM_3}: profile.sh (deps: #${NUM_2})"
echo "   #${NUM_4}: gh.sh (deps: #${NUM_1})"
echo "   #${NUM_5}: /conductor:work (deps: #${NUM_3}, #${NUM_4})"
echo "   #${NUM_6}: validate spike (deps: #${NUM_5})"

if [[ -z "$PROJECT_NUMBER" ]]; then
  echo ""
  echo "Note: issues were not added to a Project. Open the Project in GH UI and add them manually,"
  echo "or re-run with: $0 $REPO_SLUG <project-number>"
fi
