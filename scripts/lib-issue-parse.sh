#!/usr/bin/env bash
# Parse the body of a Scout research-request Issue (rendered from the Issue Form
# at .github/ISSUE_TEMPLATE/research.yml) and export RAW_TOPIC, DEPTH, FORMAT,
# SKIP_SHARPEN.
#
# Usage (source this file, then call parse_issue_body):
#   source scripts/lib-issue-parse.sh
#   parse_issue_body "$ISSUE_BODY"
#
# Issue Form bodies look like:
#   ### Topic
#
#   <topic, possibly multi-line>
#
#   ### Depth
#
#   standard
#
#   ### Format
#
#   auto
#
#   ### Options
#
#   - [X] Skip sharpening (use my topic verbatim)

# Extract the lines between `### <label>` and the next `### ` header.
_extract_section() {
  local body="$1" label="$2"
  printf '%s' "$body" | awk -v target="### $label" '
    $0 == target { in_block=1; next }
    /^### / && in_block { exit }
    in_block { print }
  '
}

# Strip leading + trailing blank lines, preserving internal blanks.
_trim_blanks() {
  awk '
    { lines[NR] = $0; if (NF) last = NR }
    !first && NF { first = NR }
    END { for (i = first; i <= last; i++) print lines[i] }
  '
}

# Map display-name aliases from the Issue Form back to internal codes used by
# downstream scripts (run.sh, sharpen.sh, skills, agents).
_normalize_depth() {
  case "$1" in
    recon)      echo ceo ;;
    survey)     echo standard ;;
    expedition) echo deep ;;
    *)          echo "$1" ;;
  esac
}

parse_issue_body() {
  local body="$1"
  RAW_TOPIC="$(_extract_section "$body" Topic | _trim_blanks)"
  DEPTH="$(_extract_section "$body" Depth | _trim_blanks | head -n 1)"
  FORMAT="$(_extract_section "$body" Format | _trim_blanks | head -n 1)"
  local options_block
  options_block="$(_extract_section "$body" Options)"
  if printf '%s' "$options_block" | grep -qiE '^\- \[[xX]\] Skip sharpening'; then
    SKIP_SHARPEN=true
  else
    SKIP_SHARPEN=false
  fi
  [ -n "$DEPTH" ]  || DEPTH=survey
  [ -n "$FORMAT" ] || FORMAT=auto
  DEPTH_LABEL="$DEPTH"
  DEPTH="$(_normalize_depth "$DEPTH")"
  export RAW_TOPIC DEPTH DEPTH_LABEL FORMAT SKIP_SHARPEN
}
