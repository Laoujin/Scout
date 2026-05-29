#!/usr/bin/env bash
# Helpers for the "re-run failed sub-topics" flow.
#
# The rerun comment posted by rerun-comment.sh carries:
#   - A list of failed sub-topics with their reasons (display only)
#   - A `- [ ] **Re-run failed sub-topics**` checkbox
#   - A hidden marker naming the expedition folder to resume into:
#       <!-- scout-rerun: 2026-05-25-some-expedition-slug -->
#
# Functions:
#   parse_rerun_expedition <body>  -> RERUN_EXPEDITION  (folder name)
#   parse_rerun_start      <body>  -> RERUN_START       ("true"|"false")
#   manifest_to_subtopics  <file>  -> prints SUB_TOPICS_TSV for run-decompose.sh

# Extract the expedition folder name from the hidden marker.
parse_rerun_expedition() {
  local body="$1"
  RERUN_EXPEDITION="$(printf '%s' "$body" \
    | grep -oE '<!-- scout-rerun:[[:space:]]*[^[:space:]]+[[:space:]]*-->' \
    | head -1 \
    | sed -E 's/<!-- scout-rerun:[[:space:]]*//; s/[[:space:]]*-->$//')"
  export RERUN_EXPEDITION
}

# Detect whether `- [x] **Re-run failed sub-topics**` is ticked.
parse_rerun_start() {
  local body="$1"
  if printf '%s' "$body" | grep -qiE '^\s*[-*][[:space:]]+\[[xX]\][[:space:]]+\*\*Re-run failed sub-topics\*\*'; then
    RERUN_START=true
  else
    RERUN_START=false
  fi
  export RERUN_START
}

# Reconstruct the SUB_TOPICS_TSV (title|depth|rationale|checked) that
# run-decompose.sh consumes, from an expedition manifest.json. ALL children are
# emitted as checked=true; run-decompose's _child_is_success skips the ones that
# already succeeded, so only the failed placeholders are re-run before the
# synthesis pass re-runs over the full set.
manifest_to_subtopics() {
  local manifest="$1"
  jq -r '.[] | [.title, .depth, "", "true"] | join("|")' "$manifest"
}
