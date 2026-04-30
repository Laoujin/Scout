#!/usr/bin/env bash
# Glue between the issue-event workflow and the research pipeline.
# Inspects the bot comment to decide between single-pass run.sh and
# decomposed run-decompose.sh.
#
# Required env: BOT_COMMENT_BODY, ISSUE_NUMBER, GH_TOKEN, GH_REPO.

set -euo pipefail

: "${BOT_COMMENT_BODY:?BOT_COMMENT_BODY is required}"
: "${ISSUE_NUMBER:?ISSUE_NUMBER is required}"
: "${GH_TOKEN:?GH_TOKEN is required}"
: "${GH_REPO:?GH_REPO is required}"

SCOUT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
source "$SCOUT_DIR/scripts/lib-issue-parse.sh"

# Topic — content of the scout-topic fenced block in the bot comment.
TOPIC="$(printf '%s' "$BOT_COMMENT_BODY" | awk '
  /^```scout-topic[[:space:]]*$/ { in_block=1; next }
  /^```[[:space:]]*$/ && in_block { exit }
  in_block { print }
')"

if [ -z "$TOPIC" ]; then
  echo "Error: could not extract scout-topic block from bot comment." >&2
  exit 1
fi

# Original issue body for raw topic + depth.
issue_body="$(gh issue view "$ISSUE_NUMBER" --repo "$GH_REPO" --json body --jq .body)"
parse_issue_body "$issue_body"

# Determine routing: decompose vs single-pass.
parse_start_choice "$BOT_COMMENT_BODY"
parse_sub_topics   "$BOT_COMMENT_BODY"

if [ "$START_CHOICE" = "decompose" ] && [ "${#SUB_TOPICS[@]}" -gt 0 ]; then
  echo "[research-from-issue] routing: decompose (${#SUB_TOPICS[@]} sub-topics)" >&2
  SUB_TOPICS_TSV="$(printf '%s\n' "${SUB_TOPICS[@]}")"

  ATLAS_REPO="${ATLAS_REPO:-git@github.com:Laoujin/atlas.git}"
  ATLAS_DIR="$SCOUT_DIR/atlas-checkout"
  rm -rf "$ATLAS_DIR"
  git clone --filter=blob:none --depth=1 "$ATLAS_REPO" "$ATLAS_DIR"
  source "$SCOUT_DIR/scripts/slug.sh"
  DATE="$(date +%F)"
  PARENT_SLUG="$(slugify "$TOPIC")"
  n=2
  while [ -d "$ATLAS_DIR/research/${DATE}-${PARENT_SLUG}" ]; do
    PARENT_SLUG="$(slugify "$TOPIC")-${n}"
    n=$((n+1))
  done
  PARENT_DIR="$ATLAS_DIR/research/${DATE}-${PARENT_SLUG}"
  mkdir -p "$PARENT_DIR"

  export PARENT_DIR PARENT_TOPIC="$TOPIC" DATE
  export SUB_TOPICS_TSV ATLAS_REPO ISSUE_NUMBER GH_TOKEN GH_REPO
  exec bash "$SCOUT_DIR/scripts/run-decompose.sh"
fi

# Single-pass fallback (covers START_CHOICE=as_one and the "no Sub-topics
# present" case from before this feature shipped).
echo "[research-from-issue] routing: single-pass" >&2
[ -n "$RAW_TOPIC" ] || RAW_TOPIC="$TOPIC"
export TOPIC RAW_TOPIC DEPTH ISSUE_NUMBER
exec bash "$SCOUT_DIR/scripts/run.sh"
