#!/usr/bin/env bash
# Parse the body of a Scout research-request Issue (rendered from the Issue Form
# at .github/ISSUE_TEMPLATE/research.yml) and export RAW_TOPIC, DEPTH,
# SKIP_SHARPEN. FORMAT is not parsed from the body; it is hardcoded to `auto`
# and exported for downstream-script compatibility.
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

# Extract the sharpened topic from a bot comment body. Prefers the HTML-marker
# region (current format); falls back to a bare ```scout-topic fence for
# pre-marker comments. Unwraps an old ```scout-topic fence found *inside* the
# markers so already-sharpened issues keep working.
# COMPAT: the fence-unwrap branch + bare-fence fallback can be removed once all
# pre-2026-06 sharpened issues are closed.
extract_topic() {
  local body="$1" region
  region="$(printf '%s' "$body" | awk '
    /<!-- scout-topic-start -->/ { in_m=1; next }
    /<!-- scout-topic-end -->/   { in_m=0; exit }
    in_m { print }
  ')"
  if [ -z "$region" ]; then
    region="$(printf '%s' "$body" | awk '
      /^```scout-topic[[:space:]]*$/ { in_b=1; next }
      /^```[[:space:]]*$/ && in_b { exit }
      in_b { print }
    ')"
  fi
  case "$region" in
    '```scout-topic'*)
      region="$(printf '%s' "$region" | awk '
        /^```scout-topic/ { f=1; next }
        /^```/            { f=0 }
        f')" ;;
  esac
  printf '%s' "$region" | _trim_blanks
}

# First non-empty line of a (possibly structured) topic, stripped of bold
# markers and a leading bullet — used as the slug/title source.
topic_title() {
  printf '%s\n' "$1" | sed -n '/[^[:space:]]/{s/^[[:space:]]*//;s/\*\*//g;s/^[-*][[:space:]]*//;s/[[:space:]]*$//;p;q}'
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
  local options_block
  options_block="$(_extract_section "$body" Options)"
  if printf '%s' "$options_block" | grep -qiE '^\- \[[xX]\] Skip sharpening'; then
    SKIP_SHARPEN=true
  else
    SKIP_SHARPEN=false
  fi
  [ -n "$DEPTH" ] || DEPTH=survey
  FORMAT=auto
  DEPTH_LABEL="$DEPTH"
  DEPTH="$(_normalize_depth "$DEPTH")"
  export RAW_TOPIC DEPTH DEPTH_LABEL FORMAT SKIP_SHARPEN
}

# --- Sub-topic parsing ----------------------------------------------------
#
# parse_sub_topics extracts the Sub-topics list from a bot comment body and
# populates the global SUB_TOPICS array. Each entry has the shape:
#   "<title>|<depth>|<rationale>|<checked>"
# where <depth> is the internal code (ceo/standard/deep) and <checked> is
# the literal string "true" or "false".
#
# Lenience rules (mirrors hand-edited markdown):
#  - either `-` or `*` bullets, leading whitespace tolerated
#  - depth tokens accept display names (recon/survey/expedition), internal
#    codes (ceo/standard/deep), case-insensitive
#  - unknown tokens within edit-distance ≤ 2 of any accepted token snap
#    to that token; otherwise default to `standard`
#  - missing `(depth)` prefix → defaults to `standard`
#  - missing `— rationale` accepted (rationale=empty)

# Levenshtein distance between two strings; pure bash; O(len1*len2). Fine
# for our 6-element token table and short inputs.
_lev() {
  local s="$1" t="$2"
  local m=${#s} n=${#t} i j cost
  if [ "$m" -eq 0 ]; then echo "$n"; return; fi
  if [ "$n" -eq 0 ]; then echo "$m"; return; fi
  declare -A d
  for ((i=0; i<=m; i++)); do d[$i,0]=$i; done
  for ((j=0; j<=n; j++)); do d[0,$j]=$j; done
  for ((i=1; i<=m; i++)); do
    for ((j=1; j<=n; j++)); do
      [ "${s:i-1:1}" = "${t:j-1:1}" ] && cost=0 || cost=1
      local del=$(( d[$((i-1)),$j] + 1 ))
      local ins=$(( d[$i,$((j-1))] + 1 ))
      local sub=$(( d[$((i-1)),$((j-1))] + cost ))
      local min=$del
      [ "$ins" -lt "$min" ] && min=$ins
      [ "$sub" -lt "$min" ] && min=$sub
      d[$i,$j]=$min
    done
  done
  echo "${d[$m,$n]}"
}

# Snap a depth token to the nearest known internal code, or "standard" if
# nothing is within edit-distance 2.
_snap_depth() {
  local input="$1"
  local lower
  lower="$(printf '%s' "$input" | tr '[:upper:]' '[:lower:]')"
  case "$lower" in
    ceo|standard|deep) echo "$lower"; return ;;
    recon)             echo "ceo";      return ;;
    survey)            echo "standard"; return ;;
    expedition)        echo "deep";     return ;;
  esac
  local best="standard" best_d=99
  local cand cand_internal d
  for cand in recon ceo survey standard expedition deep; do
    d="$(_lev "$lower" "$cand")"
    if [ "$d" -le 2 ] && [ "$d" -lt "$best_d" ]; then
      best_d=$d
      case "$cand" in
        recon) cand_internal=ceo ;;
        survey) cand_internal=standard ;;
        expedition) cand_internal=deep ;;
        *) cand_internal=$cand ;;
      esac
      best="$cand_internal"
    fi
  done
  echo "$best"
}

# Populate SUB_TOPICS array from the comment body. Empty array if no
# `### Sub-topics` section is present.
parse_sub_topics() {
  local body="$1"
  SUB_TOPICS=()
  local section
  section="$(_extract_section "$body" 'Sub-topics')"
  [ -n "$section" ] || return 0
  while IFS= read -r line; do
    # strip leading whitespace
    line="${line#"${line%%[![:space:]]*}"}"
    # match: bullet [ ]/[x] (optional (depth)) **title** (optional — rationale)
    # Title uses .+ (not [^*]+) because titles may contain literal * (e.g. *.domain)
    # Em-dash/hyphen separator uses alternation because [—-] is an invalid range.
    if [[ "$line" =~ ^[-*][[:space:]]+\[([\ xX])\][[:space:]]*(\(([a-zA-Z]+)\)[[:space:]]*)?\*\*(.+)\*\*([[:space:]]*(—|-)[[:space:]]*(.*))?$ ]]; then
      local checked_raw="${BASH_REMATCH[1]}"
      local depth_raw="${BASH_REMATCH[3]}"
      local title="${BASH_REMATCH[4]}"
      local rationale="${BASH_REMATCH[7]:-}"
      local checked="false"
      [[ "$checked_raw" =~ [xX] ]] && checked="true"
      local depth_internal
      if [ -n "$depth_raw" ]; then
        depth_internal="$(_snap_depth "$depth_raw")"
      else
        depth_internal="standard"
      fi
      # Pipe characters would corrupt the |-delimited array entry shape.
      title="${title//|/}"
      rationale="${rationale//|/}"
      SUB_TOPICS+=("${title}|${depth_internal}|${rationale}|${checked}")
    fi
  done <<< "$section"
}

# Determine which Start checkbox the user ticked.
#   "decompose"  — only `Start research` ticked
#   "as_one"     — `Research as one expedition instead` ticked (wins ties)
#   "none"       — neither
parse_start_choice() {
  local body="$1"
  local start_ticked=false as_one_ticked=false
  if printf '%s' "$body" | grep -qiE '^\s*[-*][[:space:]]+\[[xX]\][[:space:]]+\*\*Start research\*\*'; then
    start_ticked=true
  fi
  if printf '%s' "$body" | grep -qiE '^\s*[-*][[:space:]]+\[[xX]\][[:space:]]+\*\*Research as one expedition instead\*\*'; then
    as_one_ticked=true
  fi
  if $as_one_ticked; then
    START_CHOICE="as_one"
  elif $start_ticked; then
    START_CHOICE="decompose"
  else
    START_CHOICE="none"
  fi
  export START_CHOICE
}

# --- Series parsing -------------------------------------------------------
#
# parse_series reads the `### Series` section of a bot comment and exports:
#   SERIES_SLUG  — series slug if a ticked line is present, else ""
#   SERIES_GROUP — group label if present on that line, else ""
# Only a ticked ([x]/[X]) line counts. Line shape (lenient):
#   - [x] **<slug>** [(› | /) <group>] [(— | -) <rationale>]
parse_series() {
  local body="$1"
  SERIES_SLUG=""; SERIES_GROUP=""
  local section line
  section="$(_extract_section "$body" 'Series')"
  [ -n "$section" ] || { export SERIES_SLUG SERIES_GROUP; return 0; }
  while IFS= read -r line; do
    line="${line#"${line%%[![:space:]]*}"}"   # strip leading whitespace
    # The series checkbox is ALWAYS the FIRST task-list bullet in the section.
    # In narrow mode the section is unbounded (no trailing `### `), so a later
    # `- [x] **Start research**` bullet would be over-read. Stop at the first
    # task-list bullet and only honor it if ticked.
    [[ "$line" =~ ^[-*][[:space:]]+\[[\ xX]\] ]] || continue
    # Match bullet + ticked checkbox + **slug** — use greedy [^*]+ which is fine
    # since slugs contain no asterisks.
    if [[ "$line" =~ ^[-*][[:space:]]+\[[xX]\][[:space:]]*\*\*([^*]+)\*\*(.*)$ ]]; then
      SERIES_SLUG="${BASH_REMATCH[1]}"
      SERIES_SLUG="${SERIES_SLUG%"${SERIES_SLUG##*[![:space:]]}"}"
      local remainder="${BASH_REMATCH[2]}"
      # Strip leading whitespace from remainder
      remainder="${remainder#"${remainder%%[![:space:]]*}"}"
      # If remainder starts with › (U+203A, UTF-8: e2 80 ba) or /, a group follows
      local group_sep=$'\xe2\x80\xba'
      if [[ "$remainder" == "${group_sep}"* ]] || [[ "$remainder" == "/"* ]]; then
        # Remove the leading separator character
        if [[ "$remainder" == "${group_sep}"* ]]; then
          remainder="${remainder#"$group_sep"}"
        else
          remainder="${remainder#/}"
        fi
        # Strip leading whitespace
        remainder="${remainder#"${remainder%%[![:space:]]*}"}"
        # Split on the first em-dash (—, U+2014, UTF-8: e2 80 94) or hyphen
        local em_dash=$'\xe2\x80\x94'
        if [[ "$remainder" == *"${em_dash}"* ]]; then
          SERIES_GROUP="${remainder%%"${em_dash}"*}"
        elif [[ "$remainder" == *" -"* ]]; then
          SERIES_GROUP="${remainder%% -*}"
        else
          SERIES_GROUP="$remainder"
        fi
        # Trim trailing whitespace from group
        SERIES_GROUP="${SERIES_GROUP%"${SERIES_GROUP##*[![:space:]]}"}"
      fi
    fi
    # Break after the FIRST task-list bullet regardless of ticked state, so a
    # later ticked bullet (e.g. Start research) is never reached.
    break
  done <<< "$section"
  export SERIES_SLUG SERIES_GROUP
}
