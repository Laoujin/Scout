#!/usr/bin/env bash
# Deterministic GitHub-issue helper for the local /scout flow: opens a provenance
# issue carrying the verbatim originating prompt, and later comments the published
# URL + closes it. EVERY gh failure is non-fatal — research/publish must never
# block on issue plumbing. The target repo is derived from $SCOUT_DIR's origin
# remote; auth is gh's stored credentials (no token env needed).
#
# Usage:
#   ISSUE=$(SCOUT_DIR=<dir> bash local-issue.sh open "<title>" <prompt-file>)
#   SCOUT_DIR=<dir> bash local-issue.sh close "<num>" "<url>"
set -uo pipefail   # deliberately NOT -e: gh errors are handled, not fatal

SCOUT_DIR="${SCOUT_DIR:-$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)}"

# owner/repo from the origin remote. Handles SSH, HTTPS, and host-alias forms by
# dropping .git, turning ':' into '/', then taking the last two path segments.
_repo_slug() {
  local url
  url="$(git -C "$SCOUT_DIR" remote get-url origin 2>/dev/null)" || return 1
  [ -n "$url" ] || return 1
  url="${url%.git}"; url="${url//:/\/}"
  local repo rest owner
  repo="${url##*/}"; rest="${url%/*}"; owner="${rest##*/}"
  [ -n "$owner" ] && [ -n "$repo" ] || return 1
  printf '%s/%s' "$owner" "$repo"
}

cmd_open() {
  local title="$1" body_file="$2" repo num
  repo="$(_repo_slug)" || { echo "[local-issue] no origin remote; skipping issue" >&2; return 0; }
  [ -f "$body_file" ] || { echo "[local-issue] prompt file not found: $body_file" >&2; return 0; }
  num="$(gh issue create --repo "$repo" --title "$title" --body-file "$body_file" 2>/dev/null \
         | grep -oE '[0-9]+$' | tail -1)"
  if [ -n "$num" ]; then printf '%s\n' "$num"; else echo "[local-issue] issue create failed; continuing" >&2; fi
}

cmd_close() {
  local num="$1" url="$2" repo
  [ -n "$num" ] || { echo "[local-issue] no issue number; skipping close" >&2; return 0; }
  repo="$(_repo_slug)" || return 0
  gh issue comment "$num" --repo "$repo" --body "Published: $url" 2>/dev/null \
    || echo "[local-issue] comment failed; continuing" >&2
  gh issue close "$num" --repo "$repo" 2>/dev/null \
    || echo "[local-issue] close failed; continuing" >&2
}

case "${1:-}" in
  open)  shift; cmd_open "$@" ;;
  close) shift; cmd_close "$@" ;;
  *) echo "usage: local-issue.sh {open <title> <prompt-file> | close <num> <url>}" >&2; exit 2 ;;
esac
