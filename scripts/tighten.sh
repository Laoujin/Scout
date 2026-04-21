#!/usr/bin/env bash
# Sharpen a raw research topic. Prints the sharpened topic to stdout.
# Required env: RAW_TOPIC, DEPTH, FORMAT.
# Optional env: PREVIOUS_SHARPENED, USER_FEEDBACK (for re-tighten on user feedback).

set -euo pipefail

: "${RAW_TOPIC:?RAW_TOPIC is required}"
: "${DEPTH:=standard}"
: "${FORMAT:=auto}"

SCOUT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
TIGHTEN_PROMPT="$(cat "$SCOUT_DIR/skills/scout/tighten.md")"

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

claude --dangerously-skip-permissions \
       --print \
       --append-system-prompt "$TIGHTEN_PROMPT" \
       "$input"
