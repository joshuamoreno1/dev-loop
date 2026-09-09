#!/usr/bin/env bash
# setup-labels.sh — idempotent bootstrap of the dev-loop state machine labels.
#
# Two backends (auto-detected):
#   - gh  : local setup with an authenticated `gh` CLI.
#   - api : REST API with curl + $GITHUB_TOKEN/$GH_TOKEN — for routine VMs and
#           Claude Code web/app, where `gh` is NOT installed (only the token).
#
# Usage:
#   REPO=<owner>/<repo> ./scripts/setup-labels.sh                # auto-detects backend
#   LABELS_BACKEND=api GITHUB_TOKEN=ghp_xxx ./scripts/setup-labels.sh
#   DRY_RUN=1 ./scripts/setup-labels.sh                          # print without executing
#
# REPO is auto-detected from the current git remote (gh or `git remote get-url origin`)
# when unset; if it cannot be determined, the script fails with a usage message.
set -euo pipefail

TOKEN="${GITHUB_TOKEN:-${GH_TOKEN:-}}"
BACKEND="${LABELS_BACKEND:-}"
DRY_RUN="${DRY_RUN:-0}"

# --- resolve target repo (env > gh > git remote; never a silent default) -----
REPO="${REPO:-}"
if [ -z "$REPO" ]; then
  REPO="$(gh repo view --json nameWithOwner -q .nameWithOwner 2>/dev/null || true)"
fi
if [ -z "$REPO" ]; then
  origin_url="$(git remote get-url origin 2>/dev/null || true)"
  if [ -n "$origin_url" ]; then
    # Supports git@host:owner/repo(.git) and https://host/owner/repo(.git)
    REPO="$(sed -E 's#^(git@[^:]+:|[a-zA-Z+]+://[^/]+/)##; s#\.git$##' <<<"$origin_url")"
  fi
fi
if [ -z "$REPO" ] || [[ "$REPO" != */* ]]; then
  echo "ERROR: could not determine the target repository." >&2
  echo "Usage: REPO=<owner>/<repo> $0   (or run inside a clone with an 'origin' remote)" >&2
  exit 1
fi
API="https://api.github.com/repos/$REPO"

# --- Source of truth: name|color|description ---------------------------------
# SINGLE list; both backends consume it (no duplication). Keep in sync with the
# state machine in the README.
LABELS=(
  "prd:needs-review|FBCA04|PRD generated, waiting for the owner's approval"
  "prd:refine|FEF2C0|The owner requests a refinement pass (R7 incorporates it)"
  "prd:approved|0E8A16|The owner approved → enters Gate A (plan review)"
  "prd:plan-review|A2EEEF|Implementation plan under review (Gate A)"
  "prd:plan-approved|2EA043|Plan passed review → ready for R2 to implement"
  "prd:building|1D76DB|Implementation in progress"
  "prd:arch-review|5319E7|PRs open, under architecture review (Gate B)"
  "prd:ready-for-review|0052CC|CI green + comments resolved + gate approved — ready for the owner"
  "prd:done|6F42C1|Merged"
  "prd:blocked|B60205|OPEN QUESTIONS or unresolved blocker"
  "prd:discarded|6E7781|PRD discarded by the owner — will not be implemented"
  "triage:pending|D93F0B|Meeting candidates (Granola/Meet) waiting for the owner's selection"
  "triage:done|C2E0C6|Triage resolved"
  "src:granola|BFD4F2|Source: Granola meeting"
  "src:meet|BFD4F2|Source: Google Meet transcript/note"
  "src:slack|BFD4F2|Source: Slack message"
)

# --- backend autodetect ------------------------------------------------------
if [ -z "$BACKEND" ]; then
  if command -v gh >/dev/null 2>&1; then BACKEND=gh
  elif [ -n "$TOKEN" ]; then BACKEND=api
  else echo "ERROR: no backend available — install gh or export GITHUB_TOKEN/GH_TOKEN" >&2; exit 1
  fi
fi
if [ "$BACKEND" = "api" ]; then
  command -v jq   >/dev/null || { echo "ERROR: api backend requires jq" >&2; exit 1; }
  command -v curl >/dev/null || { echo "ERROR: api backend requires curl" >&2; exit 1; }
  [ -n "$TOKEN" ] || { echo "ERROR: api backend requires GITHUB_TOKEN/GH_TOKEN" >&2; exit 1; }
fi

# --- backends ----------------------------------------------------------------
create_gh() { # name color desc
  gh label create "$1" --color "$2" --description "$3" --repo "$REPO" --force >/dev/null
}

create_api() { # name color desc — POST; if it already exists (422) PATCH (idempotent, = --force)
  local name="$1" color="$2" desc="$3" tmp code enc
  tmp="$(mktemp)"
  code="$(curl -sS -o "$tmp" -w '%{http_code}' -X POST \
    -H "Authorization: Bearer $TOKEN" -H "Accept: application/vnd.github+json" \
    -H "X-GitHub-Api-Version: 2022-11-28" \
    -d "$(jq -n --arg n "$name" --arg c "$color" --arg d "$desc" '{name:$n,color:$c,description:$d}')" \
    "$API/labels")" || { echo "  ✗ $name (curl failed)" >&2; rm -f "$tmp"; return 1; }
  if [ "$code" = "422" ]; then                       # already exists → update
    enc="$(jq -rn --arg s "$name" '$s|@uri')"
    code="$(curl -sS -o "$tmp" -w '%{http_code}' -X PATCH \
      -H "Authorization: Bearer $TOKEN" -H "Accept: application/vnd.github+json" \
      -H "X-GitHub-Api-Version: 2022-11-28" \
      -d "$(jq -n --arg c "$color" --arg d "$desc" '{color:$c,description:$d}')" \
      "$API/labels/$enc")" || { echo "  ✗ $name (curl failed)" >&2; rm -f "$tmp"; return 1; }
  fi
  case "$code" in
    2*) rm -f "$tmp" ;;
    *)  echo "  ✗ $name (HTTP $code): $(jq -r '.message // .' "$tmp" 2>/dev/null)" >&2
        rm -f "$tmp"; return 1 ;;
  esac
}

run_backend() { case "$BACKEND" in gh) create_gh "$@";; api) create_api "$@";; esac; }

# --- main --------------------------------------------------------------------
mode=""; [ "$DRY_RUN" = "1" ] && mode=" (dry-run)"
echo "Labels in $REPO — backend: $BACKEND$mode"
fail=0
for row in "${LABELS[@]}"; do
  IFS='|' read -r name color desc <<<"$row"
  if [ "$DRY_RUN" = "1" ]; then
    printf '  [dry-run] %-22s #%s  %s\n' "$name" "$color" "$desc"
    continue
  fi
  if run_backend "$name" "$color" "$desc"; then echo "  ✓ $name"; else fail=1; fi
done
[ "$fail" = "0" ] && echo "Done." || { echo "Finished with errors." >&2; exit 1; }
