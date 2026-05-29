#!/usr/bin/env bash
# Resume a decomposed expedition: re-run only the sub-topics that failed, then
# re-synthesize. Triggered by ticking "Re-run failed sub-topics" on the rerun
# comment that rerun-comment.sh posts.
#
# It reuses run-decompose.sh as-is: by pointing it at the existing expedition
# folder (which already holds the successful children on Atlas main) and
# feeding it the full sub-topic list, run-decompose's _child_is_success resume
# logic skips the children that succeeded and re-runs only the placeholders.
#
# Required env: BOT_COMMENT_BODY, ISSUE_NUMBER, GH_TOKEN, GH_REPO.

set -euo pipefail

: "${BOT_COMMENT_BODY:?BOT_COMMENT_BODY is required}"
: "${ISSUE_NUMBER:?ISSUE_NUMBER is required}"
: "${GH_TOKEN:?GH_TOKEN is required}"
: "${GH_REPO:?GH_REPO is required}"

SCOUT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
source "$SCOUT_DIR/scripts/lib-rerun-parse.sh"

parse_rerun_expedition "$BOT_COMMENT_BODY"
if [ -z "$RERUN_EXPEDITION" ]; then
  echo "Error: no <!-- scout-rerun: ... --> marker found in comment." >&2
  exit 1
fi

ATLAS_REPO="${ATLAS_REPO:-git@github.com:Laoujin/atlas.git}"
ATLAS_DIR="$SCOUT_DIR/atlas-checkout"
rm -rf "$ATLAS_DIR"
git clone --filter=blob:none --depth=1 "$ATLAS_REPO" "$ATLAS_DIR"

PARENT_DIR="$ATLAS_DIR/research/$RERUN_EXPEDITION"
if [ ! -d "$PARENT_DIR" ]; then
  echo "Error: expedition not found in Atlas: research/$RERUN_EXPEDITION" >&2
  exit 1
fi
MANIFEST="$PARENT_DIR/manifest.json"
if [ ! -f "$MANIFEST" ]; then
  echo "Error: research/$RERUN_EXPEDITION has no manifest.json; cannot reconstruct sub-topics." >&2
  exit 1
fi

# Rebuild the sub-topic list run-decompose consumes. All children are listed;
# the resume logic re-runs only the failed ones.
SUB_TOPICS_TSV="$(manifest_to_subtopics "$MANIFEST")"

# Date is the YYYY-MM-DD prefix of the expedition folder.
DATE="${RERUN_EXPEDITION:0:10}"

# Parent topic comes from the published expedition frontmatter. run-decompose
# re-quotes it, so stripping the outer quotes here is enough.
PARENT_TOPIC="$(awk '
  /^---[[:space:]]*$/ { n++; next }
  n==1 && /^topic:/ { sub(/^topic:[[:space:]]*/, ""); print; exit }
' "$PARENT_DIR/index.md")"
PARENT_TOPIC="${PARENT_TOPIC#\"}"; PARENT_TOPIC="${PARENT_TOPIC%\"}"
[ -n "$PARENT_TOPIC" ] || PARENT_TOPIC="$RERUN_EXPEDITION"

echo "[rerun-from-issue] resuming research/$RERUN_EXPEDITION ($(printf '%s\n' "$SUB_TOPICS_TSV" | grep -c .) sub-topics)" >&2

export PARENT_DIR PARENT_TOPIC DATE
export SUB_TOPICS_TSV ATLAS_REPO ISSUE_NUMBER GH_TOKEN GH_REPO
exec bash "$SCOUT_DIR/scripts/run-decompose.sh"
