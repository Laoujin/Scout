#!/usr/bin/env bash
# Glue between the issue-event workflow and the existing research pipeline.
# Parses the sharpened TOPIC out of BOT_COMMENT_BODY, fetches RAW_TOPIC + DEPTH +
# FORMAT from the originating issue body, then exec's into scripts/run.sh.
#
# Required env: BOT_COMMENT_BODY, ISSUE_NUMBER, GH_TOKEN, GH_REPO.

set -euo pipefail

: "${BOT_COMMENT_BODY:?BOT_COMMENT_BODY is required}"
: "${ISSUE_NUMBER:?ISSUE_NUMBER is required}"
: "${GH_TOKEN:?GH_TOKEN is required}"
: "${GH_REPO:?GH_REPO is required}"

# Sharpened topic — content of the scout-topic fenced block in the bot comment.
TOPIC="$(printf '%s' "$BOT_COMMENT_BODY" | awk '
  /^```scout-topic[[:space:]]*$/ { in_block=1; next }
  /^```[[:space:]]*$/ && in_block { exit }
  in_block { print }
')"

if [ -z "$TOPIC" ]; then
  echo "Error: could not extract scout-topic block from bot comment." >&2
  exit 1
fi

# Fetch original issue body for raw topic + depth + format.
issue_body="$(gh issue view "$ISSUE_NUMBER" --repo "$GH_REPO" --json body --jq .body)"

# Extract a multi-line section between two ### headers in the issue form body.
extract_section() {
  local label="$1"
  printf '%s' "$issue_body" | awk -v target="### $label" '
    $0 == target { in_block=1; next }
    /^### / && in_block { exit }
    in_block { print }
  '
}

# Trim leading + trailing blank lines.
trim_blanks() {
  sed -e '/./,$!d' | sed -e ':a' -e '/^[[:space:]]*$/{$d;N;ba' -e '}'
}

RAW_TOPIC="$(extract_section Topic | trim_blanks)"
DEPTH="$(extract_section Depth | trim_blanks | head -n 1)"
FORMAT="$(extract_section Format | trim_blanks | head -n 1)"

[ -n "$RAW_TOPIC" ] || RAW_TOPIC="$TOPIC"
[ -n "$DEPTH" ]     || DEPTH=standard
[ -n "$FORMAT" ]    || FORMAT=auto

export TOPIC RAW_TOPIC DEPTH FORMAT ISSUE_NUMBER

SCOUT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
exec bash "$SCOUT_DIR/scripts/run.sh"
