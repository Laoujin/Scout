#!/usr/bin/env bash
# Helpers for parsing the candidacy-comment body shape posted by views-comment.sh.
#
# The candidacy comment carries:
#   - Display rows like `- [x] <slug>` or `- [x] **<title>** — register: <view>`
#   - A final `- [ ] **Start creating the HTML pages**` checkbox
#   - A hidden machine-readable block:
#       <!-- scout-view-targets-start -->
#       ```scout-view-targets
#       { "items": [ {...}, ... ] }
#       ```
#       <!-- scout-view-targets-end -->
#
# Functions exported:
#   parse_view_targets  -> VIEW_TARGETS_JSON  (string, the raw JSON text)
#   parse_view_ticks    -> VIEW_TICKS         (associative array, slug -> "true"|"false")
#   parse_views_start   -> VIEWS_START        ("true"|"false")

# Extract the JSON inside the scout-view-targets fenced block.
parse_view_targets() {
  local body="$1"
  VIEW_TARGETS_JSON=""
  VIEW_TARGETS_JSON="$(printf '%s' "$body" | awk '
    /^```scout-view-targets[[:space:]]*$/ { in_block=1; next }
    /^```[[:space:]]*$/ && in_block { exit }
    in_block { print }
  ')"
  export VIEW_TARGETS_JSON
}

# For each item slug in VIEW_TARGETS_JSON, decide if its display row above the
# JSON block is `[x]`. The row carries a hidden `<!-- slug:<slug> -->` marker
# rendered by views-comment.sh — so we can match by slug regardless of the
# display title text.
# Populates the associative array VIEW_TICKS (slug -> "true"|"false").
parse_view_ticks() {
  local body="$1"
  declare -gA VIEW_TICKS=()
  parse_view_targets "$body"
  [ -n "$VIEW_TARGETS_JSON" ] || return 0
  local slugs
  slugs="$(printf '%s' "$VIEW_TARGETS_JSON" | jq -r '.items[].slug')" || return 1
  while IFS= read -r slug; do
    [ -n "$slug" ] && [ "$slug" != "null" ] || continue
    local escaped_slug
    escaped_slug="$(printf '%s' "$slug" | sed 's/[.[\*^${}\\|+?()]/\\&/g')"
    if printf '%s' "$body" | grep -qE "^\s*[-*][[:space:]]+\[[xX]\][[:space:]].*<!-- slug:${escaped_slug} -->"; then
      VIEW_TICKS[$slug]="true"
    else
      VIEW_TICKS[$slug]="false"
    fi
  done <<< "$slugs"
}

# Detects whether `- [x] **Start creating the HTML pages**` is ticked.
parse_views_start() {
  local body="$1"
  if printf '%s' "$body" | grep -qiE '^\s*[-*][[:space:]]+\[[xX]\][[:space:]]+\*\*Start creating the HTML pages\*\*'; then
    VIEWS_START=true
  else
    VIEWS_START=false
  fi
  export VIEWS_START
}
