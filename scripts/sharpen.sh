#!/usr/bin/env bash
# Sharpen a raw research topic. Prints the sharpened topic to stdout.
# Required env: RAW_TOPIC, DEPTH, FORMAT.
# Optional env (re-sharpen): PREVIOUS_SHARPENED, USER_FEEDBACK, PREVIOUS_SUB_TOPICS.
# PREVIOUS_SUB_TOPICS is only meaningful alongside PREVIOUS_SHARPENED — its content
# is what the prior bot comment proposed under "### Sub-topics".

set -euo pipefail

: "${RAW_TOPIC:?RAW_TOPIC is required}"
: "${DEPTH:=standard}"
: "${FORMAT:=auto}"

SCOUT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
SHARPEN_PROMPT="$(cat "$SCOUT_DIR/skills/scout/sharpen.md")"

input="Raw topic: ${RAW_TOPIC}
Depth: ${DEPTH}
Format: ${FORMAT}"

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

claude --dangerously-skip-permissions \
       --print \
       --append-system-prompt "$SHARPEN_PROMPT" \
       "$input"
