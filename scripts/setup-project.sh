#!/usr/bin/env bash
# setup-project.sh — ensures the dev-loop GitHub Project (board) has ALL the
# state machine columns. The "columns" of a Project v2 are the options of the
# single-select `Status` field.
#
# ⚠️ Projects v2 can only be managed via GraphQL / `gh` with the `project` scope.
#    This runs LOCALLY (or wherever `gh` is authenticated) — NOT on routine VMs /
#    Claude Code web, where the Projects GraphQL is gated. (setup-labels.sh does
#    have an API backend because labels live in REST; Projects v2 has no REST.)
#
# Requires: gh (authenticated, `project` scope) + jq.
#
# Usage:
#   ./scripts/setup-project.sh                                  # auto-discover/create by title
#   PROJECT_OWNER=<owner> PROJECT_NUMBER=7 ./scripts/setup-project.sh   # specific board
#   DRY_RUN=1 ./scripts/setup-project.sh                        # print without mutating
#
# Env:
#   PROJECT_OWNER       (default: auto-detected from the current git remote)
#                       org or user that owns the Project; REQUIRED if it cannot
#                       be auto-detected
#   PROJECT_OWNER_TYPE  (default: organization) organization | user
#   PROJECT_TITLE       (default: dev-loop)     title used to auto-discover/create
#   PROJECT_NUMBER      (optional)              if given, used directly (title ignored)
#   STATUS_FIELD        (default: Status)       single-select field name = columns
#   PROJECT_REPLACE=1   (default: 0)            keeps EXACTLY the 12 canonical columns
#                                               (deletes the default Todo/In Progress and
#                                               any other non-canonical ones; items in
#                                               deleted columns lose their Status).
#                                               Default is additive (preserves existing).
#   DRY_RUN=1                                   does not execute the mutation
set -euo pipefail

OWNER="${PROJECT_OWNER:-}"
OWNER_TYPE="${PROJECT_OWNER_TYPE:-organization}"
TITLE="${PROJECT_TITLE:-dev-loop}"
NUMBER="${PROJECT_NUMBER:-}"
STATUS_FIELD="${STATUS_FIELD:-Status}"
REPLACE="${PROJECT_REPLACE:-0}"
DRY_RUN="${DRY_RUN:-0}"

command -v gh >/dev/null || { echo "ERROR: gh (CLI) missing. setup-project runs locally, not on a VM." >&2; exit 1; }
command -v jq >/dev/null || { echo "ERROR: jq missing" >&2; exit 1; }
case "$OWNER_TYPE" in organization|user) ;; *) echo "ERROR: PROJECT_OWNER_TYPE must be organization|user" >&2; exit 1;; esac

# --- resolve owner (env > gh > git remote; never a silent default) -----------
if [ -z "$OWNER" ]; then
  repo_nwo="$(gh repo view --json nameWithOwner -q .nameWithOwner 2>/dev/null || true)"
  if [ -z "$repo_nwo" ]; then
    origin_url="$(git remote get-url origin 2>/dev/null || true)"
    if [ -n "$origin_url" ]; then
      # Supports git@host:owner/repo(.git) and https://host/owner/repo(.git)
      repo_nwo="$(sed -E 's#^(git@[^:]+:|[a-zA-Z+]+://[^/]+/)##; s#\.git$##' <<<"$origin_url")"
    fi
  fi
  [[ "$repo_nwo" == */* ]] && OWNER="${repo_nwo%%/*}"
fi
if [ -z "$OWNER" ]; then
  echo "ERROR: could not determine the Project owner." >&2
  echo "Usage: PROJECT_OWNER=<org-or-user> $0   (or run inside a clone with an 'origin' remote)" >&2
  exit 1
fi

# Canonical columns = README states (name|color|description). Color = Projects v2
# enum: GRAY BLUE GREEN YELLOW ORANGE RED PINK PURPLE.
COLUMNS=(
  "Triage|ORANGE|triage:pending"
  "Needs review|YELLOW|prd:needs-review"
  "Refine|YELLOW|prd:refine"
  "Approved|GREEN|prd:approved"
  "Plan review|BLUE|prd:plan-review"
  "Plan approved|GREEN|prd:plan-approved"
  "Building|BLUE|prd:building"
  "Arch review|PURPLE|prd:arch-review"
  "Ready for review|BLUE|prd:ready-for-review"
  "Done|PURPLE|prd:done"
  "Blocked|RED|prd:blocked"
  "Discarded|GRAY|prd:discarded"
)

canonical_json() {
  local out="[]" row name color desc
  for row in "${COLUMNS[@]}"; do
    IFS='|' read -r name color desc <<<"$row"
    out="$(jq -c --arg n "$name" --arg c "$color" --arg d "$desc" \
      '. + [{name:$n,color:$c,description:$d}]' <<<"$out")"
  done
  echo "$out"
}

# Converts a JSON array [{name,color,description}] into the GraphQL options list.
opts_block() { jq -r '.[] | "{name:\(.name|@json),color:\(.color),description:\(.description // ""|@json)}"' | paste -sd, -; }

# --- 1. resolve the Project (id + number) ------------------------------------
resolve_project() {
  if [ -n "$NUMBER" ]; then
    gh project view "$NUMBER" --owner "$OWNER" --format json
    return
  fi
  local found
  found="$(gh project list --owner "$OWNER" --format json \
    | jq -c --arg t "$TITLE" 'first(.projects[] | select(.title==$t)) // empty')"
  if [ -n "$found" ]; then echo "$found"; return; fi
  echo "No Project '$TITLE' exists in $OWNER." >&2
  if [ "$DRY_RUN" = "1" ]; then
    echo "[dry-run] gh project create --owner $OWNER --title \"$TITLE\"" >&2
    echo ""; return
  fi
  echo "Creating..." >&2
  gh project create --owner "$OWNER" --title "$TITLE" --format json
}

project_json="$(resolve_project)"
if [ -z "$project_json" ]; then
  echo "[dry-run] Board does not exist — it would be created with these columns:" >&2
  canonical_json | jq -r '.[].name' | sed 's/^/  - /'
  exit 0
fi
PID="$(jq -r '.id' <<<"$project_json")"
PNUM="$(jq -r '.number' <<<"$project_json")"
echo "Project: $TITLE (#$PNUM) — $OWNER [$OWNER_TYPE]"

# --- 2. read the Status field (id + existing options) ------------------------
field_json="$(gh api graphql -f query='
query($o:String!,$n:Int!){
  '"$OWNER_TYPE"'(login:$o){
    projectV2(number:$n){
      field(name:"'"$STATUS_FIELD"'"){
        ... on ProjectV2SingleSelectField { id options { id name color description } }
      }
    }
  }
}' -F o="$OWNER" -F n="$PNUM" | jq -c ".data.${OWNER_TYPE}.projectV2.field")"

existing="$(jq -c '(.options // []) | map({name,color,description:(.description // "")})' <<<"$field_json" 2>/dev/null || echo "[]")"
FIELD_ID="$(jq -r '.id // empty' <<<"$field_json")"

# Additive (default): preserves existing options (by name) + adds the missing
# canonical ones. REPLACE=1: keeps exactly the 12 canonical columns.
if [ "$REPLACE" = "1" ]; then
  merged="$(canonical_json)"
else
  merged="$(jq -c -n --argjson ex "$existing" --argjson ca "$(canonical_json)" '
    ($ex) + [ $ca[] | select(.name as $n | ($ex | map(.name) | index($n)) | not) ]')"
fi

echo "Resulting columns ($(jq 'length' <<<"$merged")):"
jq -r '.[].name' <<<"$merged" | sed 's/^/  - /'

if [ "$DRY_RUN" = "1" ]; then echo "[dry-run] no changes applied."; exit 0; fi

block="$(opts_block <<<"$merged")"

# --- 3. create or update the Status field with all the columns ---------------
if [ -n "$FIELD_ID" ]; then
  gh api graphql -f query='
    mutation{ updateProjectV2Field(input:{
      fieldId:"'"$FIELD_ID"'", singleSelectOptions:['"$block"']
    }){ projectV2Field{ ... on ProjectV2SingleSelectField { options{ name } } } } }' \
    | jq -r '.data.updateProjectV2Field.projectV2Field.options[].name' | sed 's/^/  ✓ /'
else
  echo "Field '$STATUS_FIELD' does not exist — creating it with the columns..." >&2
  cblock="$(opts_block <<<"$(canonical_json)")"
  gh api graphql -f query='
    mutation{ createProjectV2Field(input:{
      projectId:"'"$PID"'", dataType:SINGLE_SELECT, name:"'"$STATUS_FIELD"'",
      singleSelectOptions:['"$cblock"']
    }){ projectV2Field{ ... on ProjectV2SingleSelectField { options{ name } } } } }' \
    | jq -r '.data.createProjectV2Field.projectV2Field.options[].name' | sed 's/^/  ✓ /'
fi
echo "Done."
