#!/usr/bin/env bash
# Sharpen a raw research topic. Prints the sharpened topic to stdout.
# Required env: RAW_TOPIC, DEPTH.
# Optional env (re-sharpen): PREVIOUS_SHARPENED, USER_FEEDBACK, PREVIOUS_SUB_TOPICS,
#                             PREVIOUS_SERIES.
# Optional env: SCOUT_PROFILE_FILE (default /home/runner/.scout/profile.yml),
#               SERIES_MANIFEST (YAML list of existing Atlas series).
#               Path to a YAML profile; if file is non-empty, its content is
#               appended to the prompt as a "User profile:" block.
# PREVIOUS_SUB_TOPICS is only meaningful alongside PREVIOUS_SHARPENED — its content
# is what the prior bot comment proposed under "### Sub-topics".
# PREVIOUS_SERIES is likewise only meaningful alongside PREVIOUS_SHARPENED.

set -euo pipefail

: "${RAW_TOPIC:?RAW_TOPIC is required}"
: "${DEPTH:=standard}"

SCOUT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
source "$SCOUT_DIR/scripts/lib-models.sh"
SHARPEN_PROMPT="$(cat "$SCOUT_DIR/skills/scout/sharpen.md")"

input="Raw topic: ${RAW_TOPIC}
Depth: ${DEPTH}"

if [ -n "${PREVIOUS_SHARPENED:-}" ]; then
  input+="
Previous sharpened proposal: ${PREVIOUS_SHARPENED}"
fi
if [ -n "${USER_FEEDBACK:-}" ]; then
  input+="
User feedback to incorporate: ${USER_FEEDBACK}"
fi
if [ -n "${PREVIOUS_SUB_TOPICS:-}" ]; then
  input+="
Previous sub-topics:
${PREVIOUS_SUB_TOPICS}"
fi
if [ -n "${PREVIOUS_SERIES:-}" ]; then
  input+="
Previous series:
${PREVIOUS_SERIES}"
fi
if [ -n "${SERIES_MANIFEST:-}" ]; then
  input+="
Existing series:
${SERIES_MANIFEST}"
fi

PROFILE_FILE="${SCOUT_PROFILE_FILE:-/home/runner/.scout/profile.yml}"
if [ -s "$PROFILE_FILE" ]; then
  input+="
User profile:
$(cat "$PROFILE_FILE")"
fi

claude --dangerously-skip-permissions \
       --model "$SCOUT_MODEL_BASE" \
       --print \
       --append-system-prompt "$SHARPEN_PROMPT" \
       "$input"
