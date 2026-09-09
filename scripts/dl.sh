#!/usr/bin/env bash
# dl.sh — dev-loop CLI to query and move PRDs/triages (GitHub Issues) without
# rebuilding the label/state logic on every request.
#
# Requires: curl, jq and $GITHUB_TOKEN (or $GH_TOKEN) in the environment. Does NOT
# require `gh` (routine VMs don't have it; they do expose the token).
#
# Usage:
#   scripts/dl.sh status                          Panel of everything waiting on the owner
#   scripts/dl.sh triage                          Open triages (triage:pending)
#   scripts/dl.sh prds [state]                    PRDs by state (or all, ordered by lifecycle)
#   scripts/dl.sh show <n>                         Issue detail (labels, state, body)
#   scripts/dl.sh prd-prs <n>                      PRs linked to a PRD (searches "<repo>#<n>" cross-references)
#   scripts/dl.sh resolve-triage <n> "<decision>" ["note"]   Comment + triage:done + close
#   scripts/dl.sh prd-label <n> <prd:state> ["note"]         Compare-and-set of the state label
#   scripts/dl.sh approve <n> ["note"]            Shortcut: prd-label <n> prd:approved
#   scripts/dl.sh comment <n> "<text>"            Comment on an issue
#   scripts/dl.sh help
#
# Environment variables:
#   REPO      (default: auto-detected from the current git remote; REQUIRED if
#             it cannot be determined — the script fails with a usage message)
#   DRY_RUN=1 prints write calls instead of executing them
set -euo pipefail

TOKEN="${GITHUB_TOKEN:-${GH_TOKEN:-}}"
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
  echo "Usage: REPO=<owner>/<repo> scripts/dl.sh <command>   (or run inside a clone with an 'origin' remote)" >&2
  exit 1
fi
API="https://api.github.com/repos/$REPO"
REPO_NAME="${REPO#*/}"

# Lifecycle order (README § "State machine"). Used to sort `prds`.
PRD_STATES=(
  prd:needs-review prd:refine prd:approved prd:plan-review prd:plan-approved
  prd:building prd:arch-review prd:ready-for-review prd:blocked prd:done prd:discarded
)
# States that require owner action (highlighted in `status`).
OWNER_ACTION=(triage:pending prd:needs-review prd:ready-for-review prd:blocked)

die() { echo "ERROR: $*" >&2; exit 1; }
[ -n "$TOKEN" ] || die "GITHUB_TOKEN/GH_TOKEN missing from the environment"
command -v jq   >/dev/null || die "jq missing"
command -v curl >/dev/null || die "curl missing"

# --- HTTP helpers ---------------------------------------------------------
_curl() {
  curl -sS \
    -H "Authorization: Bearer $TOKEN" \
    -H "Accept: application/vnd.github+json" \
    -H "X-GitHub-Api-Version: 2022-11-28" "$@"
}

api_read() { _curl "$API$1"; }

api_write() { # api_write <METHOD> <path> [json-body]
  local method="$1" path="$2" body="${3:-}"
  if [ "$DRY_RUN" = "1" ]; then
    echo "[dry-run] $method $path ${body:+→ $body}" >&2
    return 0
  fi
  local tmp code args
  tmp="$(mktemp)"
  args=(-sS -o "$tmp" -w '%{http_code}' -X "$method"
        -H "Authorization: Bearer $TOKEN"
        -H "Accept: application/vnd.github+json"
        -H "X-GitHub-Api-Version: 2022-11-28")
  [ -n "$body" ] && args+=(-d "$body")
  # A curl failure (network/DNS) leaves $code empty; treat it as an error and always clean up $tmp.
  if ! code="$(curl "${args[@]}" "$API$path")" || [ -z "$code" ] || [ "$code" -ge 300 ]; then
    echo "ERROR ${code:-curl-failed} on $method $path:" >&2
    [ -s "$tmp" ] && { jq -r '.message // .' "$tmp" >&2 2>/dev/null || cat "$tmp" >&2; }
    rm -f "$tmp"; return 1
  fi
  rm -f "$tmp"
}

# All open issues (excluding PRs), cached per invocation.
# TODO(pagination): fetches a single page of 100. Fine with <100 open issues;
# if the loop exceeds 100, follow the `Link: rel="next"` header or `status`/`prds`/`triage`
# will silently truncate and hide PRDs.
_OPEN_CACHE=""
open_issues() {
  [ -n "$_OPEN_CACHE" ] || _OPEN_CACHE="$(api_read "/issues?state=open&per_page=100")"
  echo "$_OPEN_CACHE"
}

# Prints "#n [labels] title" lines for the open issues with a given label.
_by_label() { # _by_label <label>
  open_issues | jq -r --arg L "$1" '
    if type=="array" then
      .[] | select(.pull_request|not)
          | select([.labels[].name] | index($L))
          | "  #\(.number)  \(.title[0:78])"
    else empty end'
}

# --- commands -------------------------------------------------------------
cmd_status() {
  echo "== Waiting on the OWNER ($REPO) =="
  echo
  echo "▸ Triage to resolve (triage:pending):"
  local out; out="$(_by_label triage:pending)"; echo "${out:-  (none)}"
  echo
  echo "▸ PRDs waiting for your approval (prd:needs-review):"
  out="$(_by_label prd:needs-review)"; echo "${out:-  (none)}"
  echo
  echo "▸ PRDs ready for your review/merge (prd:ready-for-review):"
  out="$(_by_label prd:ready-for-review)"; echo "${out:-  (none)}"
  echo
  echo "▸ Blocked PRDs (prd:blocked):"
  out="$(_by_label prd:blocked)"; echo "${out:-  (none)}"
  echo
  echo "-- In progress (informational, no owner action) --"
  local st
  for st in prd:refine prd:approved prd:plan-review prd:plan-approved prd:building prd:arch-review; do
    out="$(_by_label "$st")"
    [ -n "$out" ] && { echo "▸ $st:"; echo "$out"; }
  done
}

cmd_triage() {
  local rows; rows="$(_by_label triage:pending)"
  if [ -z "$rows" ]; then echo "No pending triages (triage:pending)."; return; fi
  echo "== Pending triages =="
  echo "$rows"
  echo
  echo "Resolve:  scripts/dl.sh resolve-triage <n> \"PRD: 1,3\" | \"none\" | \"all\" [\"note\"]"
}

cmd_prds() {
  local filter="${1:-}"
  if [ -n "$filter" ]; then
    [[ "$filter" == prd:* ]] || filter="prd:$filter"
    local rows; rows="$(_by_label "$filter")"
    echo "== PRDs [$filter] =="
    echo "${rows:-  (none)}"
    return
  fi
  echo "== Open PRDs (by lifecycle) =="
  local st rows
  for st in "${PRD_STATES[@]}"; do
    rows="$(_by_label "$st")"
    [ -n "$rows" ] && { echo "▸ $st"; echo "$rows"; }
  done
}

cmd_show() {
  local n="${1:?usage: show <n>}"
  api_read "/issues/$n" | jq -r '
    if .number then
      "#\(.number)  [\(.state)]  \([(.labels // [])[].name]|join(", "))",
      "Title: \(.title)",
      "Updated: \(.updated_at)   Comments: \(.comments)",
      "URL: \(.html_url)",
      "",
      (.body // "(no body)")
    else "ERROR: \(.message // "could not fetch the issue")" end'
}

cmd_comment() {
  local n="${1:?usage: comment <n> \"text\"}" body="${2:?text missing}"
  api_write POST "/issues/$n/comments" "$(jq -n --arg b "$body" '{body:$b}')" \
    && echo "✓ commented on #$n"
}

cmd_prd_prs() {
  # Lists the PRs that reference the PRD, via the issue timeline's `cross-referenced`
  # events (GitHub creates them when a PR mentions "<repo>#<n>", which is exactly how
  # the loop links its PRs with "Part of <repo>#<n>"). Repo-scoped endpoint — the
  # global search (/search/issues) is blocked in scoped sessions.
  local n="${1:?usage: prd-prs <n>}"
  echo "== PRs linked to PRD #$n (cross-references) =="
  # Note: in the timeline's Issue representation, .source.issue.pull_request only carries
  # URLs (not merged_at/state); the real state lives in .source.issue.state (open/closed).
  # TODO(pagination): the timeline paginates too — a PRD with >100 events would truncate PRs.
  local rows
  rows="$(api_read "/issues/$n/timeline?per_page=100" | jq -r '
    if type=="array" then
      [ .[] | select(.event=="cross-referenced") | .source.issue
        | select(. != null) | select(.pull_request != null)
        | "  \(.repository.full_name)#\(.number)  [\(.state)]  \(.title[0:60])" ]
      | unique[]
    else empty end')"
  echo "${rows:-  (none — no PRs reference \"$REPO_NAME#$n\" yet)}"
}

cmd_approve() { cmd_prd_label "${1:?usage: approve <n> [\"note\"]}" prd:approved "${2:-}"; }

cmd_resolve_triage() {
  local n="${1:?usage: resolve-triage <n> \"decision\" [\"note\"]}"
  local decision="${2:?decision missing (e.g. \"none\" or \"PRD: 1,3\")}"
  local note="${3:-}"

  # A single read of the issue, reused below (avoids duplicate API calls).
  local issue; issue="$(api_read "/issues/$n")"
  echo "$issue" | jq -e '.number' >/dev/null 2>&1 || die "could not fetch issue #$n"

  # PREFLIGHT: only act if it is still triage:pending (idempotency).
  local labels; labels="$(echo "$issue" | jq -r '[.labels[].name]|join(" ")')"
  if [[ " $labels " != *" triage:pending "* ]]; then
    echo "PREFLIGHT: #$n is not triage:pending (labels: $labels) — nothing to do."; return 0
  fi

  local body="$decision"; [ -n "$note" ] && body="$decision — $note"
  cmd_comment "$n" "$body"

  # Replaces triage:pending with triage:done, preserves the rest.
  local kept; kept="$(echo "$issue" \
    | jq -c '[.labels[].name | select(. != "triage:pending")] + ["triage:done"]')"
  api_write PUT "/issues/$n/labels" "{\"labels\":$kept}" && echo "✓ label → triage:done"
  api_write PATCH "/issues/$n" '{"state":"closed","state_reason":"not_planned"}' \
    && echo "✓ #$n closed"
}

cmd_prd_label() {
  local n="${1:?usage: prd-label <n> <prd:state> [\"note\"]}"
  local new="${2:?target label missing (e.g. prd:approved)}"
  local note="${3:-}"
  [[ "$new" == prd:* ]] || die "the target label must start with 'prd:' (given: $new)"

  local issue; issue="$(api_read "/issues/$n")"
  echo "$issue" | jq -e '.number' >/dev/null 2>&1 || die "could not fetch issue #$n"

  # Compare-and-set: removes any current prd:*, adds the new one, preserves src:*/triage:*.
  local labels; labels="$(echo "$issue" | jq -c '[.labels[].name]')"
  local kept; kept="$(echo "$labels" | jq -c --arg N "$new" \
    '[.[] | select(startswith("prd:")|not)] + [$N]')"
  echo "  labels: $labels → $kept"
  api_write PUT "/issues/$n/labels" "{\"labels\":$kept}" && echo "✓ #$n → $new"
  [ -n "$note" ] && cmd_comment "$n" "$note"
}

# Prints the header comment block (robust to length changes).
cmd_help() { awk 'NR>1 && /^#/{sub(/^# ?/,"");print;next} NR>1{exit}' "$0"; }

# --- dispatch -------------------------------------------------------------
cmd="${1:-help}"; shift || true
case "$cmd" in
  status)         cmd_status "$@" ;;
  triage)         cmd_triage "$@" ;;
  prds)           cmd_prds "$@" ;;
  show)           cmd_show "$@" ;;
  prd-prs)        cmd_prd_prs "$@" ;;
  comment)        cmd_comment "$@" ;;
  resolve-triage) cmd_resolve_triage "$@" ;;
  prd-label)      cmd_prd_label "$@" ;;
  approve)        cmd_approve "$@" ;;
  help|-h|--help) cmd_help ;;
  *)              echo "Unknown command: $cmd" >&2; cmd_help; exit 1 ;;
esac
