#!/usr/bin/env bash
# Parent orchestrator for decomposed expeditions. Iterates over user-ticked
# sub-topics, invoking scripts/run.sh per child. Writes parent index.md via
# a synthesis pass when ≥2 children succeed.
#
# Required env: PARENT_DIR, PARENT_TOPIC, DATE, SUB_TOPICS_TSV
# Optional env: PARENT_FORMAT (default auto), SCOUT_DIR (defaults to script's
#               parent), SCOUT_MAX_CHILDREN (default 8),
#               SCOUT_DECOMPOSE_SOFT_TIMEOUT (4h),
#               SCOUT_DECOMPOSE_HARD_TIMEOUT (4h20m),
#               SCOUT_DECOMPOSE_MIN_REMAINING (default 60s — minimum
#               per-child budget once a child starts; lower in tests),
#               SCOUT_SKIP_SYNTHESIS (test hook), RUN_LOG (test hook to
#               record invocations).
#
# SUB_TOPICS_TSV is a newline-separated list of `title|depth|rationale|checked`
# entries (the same shape parse_sub_topics writes to the SUB_TOPICS array).

set -euo pipefail

: "${PARENT_DIR:?PARENT_DIR is required}"
: "${PARENT_TOPIC:?PARENT_TOPIC is required}"
: "${PARENT_FORMAT:=auto}"
: "${DATE:?DATE is required}"
: "${SUB_TOPICS_TSV:?SUB_TOPICS_TSV is required}"
: "${SCOUT_MAX_CHILDREN:=8}"
: "${SCOUT_DECOMPOSE_SOFT_TIMEOUT:=14400}"   # seconds, 4h
: "${SCOUT_DECOMPOSE_HARD_TIMEOUT:=15600}"   # seconds, 4h20m

SCOUT_DIR="${SCOUT_DIR:-$(cd "$(dirname "$0")/.." && pwd)}"
mkdir -p "$PARENT_DIR"

# Slugify (uses existing scripts/slug.sh if available, else simple version).
if [ -f "$SCOUT_DIR/scripts/slug.sh" ]; then
  source "$SCOUT_DIR/scripts/slug.sh"
fi
_simple_slug() {
  printf '%s' "$1" | tr '[:upper:]' '[:lower:]' \
    | sed -e 's/[^a-z0-9]/-/g' -e 's/--*/-/g' -e 's/^-//' -e 's/-$//' \
    | cut -c1-60
}
_slugify_or_simple() {
  if declare -F slugify >/dev/null 2>&1; then slugify "$1"
  else _simple_slug "$1"
  fi
}

# Frontmatter helper: extracts a field's value from an index.md file.
_frontmatter_field() {
  local file="$1" field="$2"
  awk -v f="$field" '
    /^---[[:space:]]*$/ { in_fm = !in_fm; next }
    in_fm && $0 ~ "^"f":" { sub("^"f":[[:space:]]*", ""); print; exit }
  ' "$file"
}

# Returns 0 if child has a successful (non-placeholder) index.{md,html}.
# A child is considered successful if ANY of its index files lacks a
# `status: failed` frontmatter field — so a stray failure placeholder in
# index.md doesn't override a real artifact in index.html (or vice-versa).
_child_is_success() {
  local dir="$1" file any_found=0
  for file in "$dir/index.md" "$dir/index.html"; do
    [ -f "$file" ] || continue
    any_found=1
    local status
    status="$(_frontmatter_field "$file" status)"
    [ "$status" = "failed" ] || return 0
  done
  return 1
}

# Write a failure placeholder index.md for a child.
_write_placeholder() {
  local dir="$1" depth="$2" reason="$3"
  mkdir -p "$dir"
  cat > "$dir/index.md" <<MD
---
layout: research
title: $(basename "$dir")
status: failed
failure_reason: $reason
attempted_at: $(date -u +%FT%TZ)
depth: $depth
---

Research failed: $reason
MD
}

# --- Main loop ----------------------------------------------------------------

START_TS=$(date +%s)
PARENT_FORMAT_INTERNAL="$PARENT_FORMAT"

# Truncate at SCOUT_MAX_CHILDREN.
mapfile -t CHILDREN <<< "$(printf '%s\n' "$SUB_TOPICS_TSV" | grep '|true$' | head -n "$SCOUT_MAX_CHILDREN")"

manifest_path="$PARENT_DIR/manifest.json"
echo "[" > "$manifest_path.tmp"
manifest_first=1

for entry in "${CHILDREN[@]}"; do
  [ -n "$entry" ] || continue
  IFS='|' read -r ctitle cdepth crationale cchecked <<< "$entry"
  cslug="$(_slugify_or_simple "$ctitle")"
  child_dir="$PARENT_DIR/$cslug"
  child_status="unknown"
  child_start=$(date +%s)

  if _child_is_success "$child_dir"; then
    echo "[run-decompose] skip (already success): $cslug" >&2
    child_status="skipped_success"
  else
    elapsed=$(( $(date +%s) - START_TS ))
    if [ "$elapsed" -ge "$SCOUT_DECOMPOSE_SOFT_TIMEOUT" ]; then
      echo "[run-decompose] soft timeout reached, skipping: $cslug" >&2
      _write_placeholder "$child_dir" "$cdepth" "soft timeout reached before start"
      child_status="skipped_soft_timeout"
    else
      remaining=$(( SCOUT_DECOMPOSE_HARD_TIMEOUT - elapsed ))
      [ "$remaining" -lt "${SCOUT_DECOMPOSE_MIN_REMAINING:-60}" ] && \
        remaining="${SCOUT_DECOMPOSE_MIN_REMAINING:-60}"
      echo "[run-decompose] running child $cslug (depth=$cdepth, remaining=${remaining}s)" >&2
      rm -rf "$child_dir"
      mkdir -p "$child_dir"
      set +e
      env TOPIC="$ctitle" RAW_TOPIC="$ctitle" DEPTH="$cdepth" \
          FORMAT="$PARENT_FORMAT_INTERNAL" RESEARCH_DIR="$child_dir" \
          ATLAS_REPO="${ATLAS_REPO:-}" \
          SCOUT_NO_PUBLISH=1 SCOUT_DECOMPOSE_CHILD=1 \
          ${RUN_LOG:+RUN_LOG="$RUN_LOG"} \
          timeout "${remaining}s" bash "$SCOUT_DIR/scripts/run.sh"
      rc=$?
      set -e
      if [ "$rc" -eq 0 ] && _child_is_success "$child_dir"; then
        child_status="success"
      elif [ "$rc" -eq 124 ]; then
        _write_placeholder "$child_dir" "$cdepth" "hard timeout"
        child_status="failed_hard_timeout"
      else
        _write_placeholder "$child_dir" "$cdepth" "child run.sh exit $rc"
        child_status="failed"
      fi
    fi
  fi

  # Append to manifest.
  child_end=$(date +%s)
  if [ "$manifest_first" -eq 1 ]; then manifest_first=0; else echo "," >> "$manifest_path.tmp"; fi
  printf '  {"slug":"%s","title":"%s","depth":"%s","status":"%s","start":%d,"end":%d}' \
    "$cslug" "$(printf '%s' "$ctitle" | sed 's/"/\\"/g')" "$cdepth" \
    "$child_status" "$child_start" "$child_end" >> "$manifest_path.tmp"
done

echo >> "$manifest_path.tmp"
echo "]" >> "$manifest_path.tmp"
mv "$manifest_path.tmp" "$manifest_path"

# --- Synthesis pass -----------------------------------------------------------

if [ "${SCOUT_SKIP_SYNTHESIS:-0}" = "1" ]; then
  exit 0
fi

# Count successful (non-placeholder) children and build a CHILDREN JSON array.
SUCCESS_COUNT=0
CHILDREN_JSON='['
first=1
for entry in "${CHILDREN[@]}"; do
  [ -n "$entry" ] || continue
  IFS='|' read -r ctitle cdepth crationale cchecked <<< "$entry"
  cslug="$(_slugify_or_simple "$ctitle")"
  child_dir="$PARENT_DIR/$cslug"
  status="failed"
  summary=""
  citations=0
  reading=0
  if _child_is_success "$child_dir"; then
    status="success"
    SUCCESS_COUNT=$((SUCCESS_COUNT + 1))
    summary="$(_frontmatter_field "$child_dir/index.md" summary)"
    [ -z "$summary" ] && summary="$(_frontmatter_field "$child_dir/index.md" title)"
    citations="$(_frontmatter_field "$child_dir/index.md" citations)"
    reading="$(_frontmatter_field "$child_dir/index.md" reading_time_min)"
    [ -z "$citations" ] && citations=0
    [ -z "$reading" ] && reading=0
  elif [ -f "$child_dir/index.md" ]; then
    summary="$(_frontmatter_field "$child_dir/index.md" failure_reason)"
  fi
  [ "$first" -eq 1 ] && first=0 || CHILDREN_JSON+=","
  CHILDREN_JSON+=$(printf '\n  {"slug":"%s","title":"%s","depth":"%s","status":"%s","summary":"%s","citations":%s,"reading_time_min":%s}' \
    "$cslug" \
    "$(printf '%s' "$ctitle" | sed 's/"/\\"/g')" \
    "$cdepth" "$status" \
    "$(printf '%s' "$summary" | sed 's/"/\\"/g')" \
    "$citations" "$reading")
done
CHILDREN_JSON+=$'\n]'

if [ "$SUCCESS_COUNT" -lt 2 ]; then
  cat > "$PARENT_DIR/index.md" <<MD
---
layout: expedition
title: $(basename "$PARENT_DIR")
date: $DATE
topic: $PARENT_TOPIC
format: $PARENT_FORMAT
synthesis: false
children: $CHILDREN_JSON
---

Synthesis skipped — only $SUCCESS_COUNT sub-topic(s) produced output. See child page(s) below.
MD
else
  SKILL_CONTENT="$(cat "$SCOUT_DIR/skills/scout/synthesis.md")"
  PROMPT="$(cat <<EOF
PARENT_TOPIC: ${PARENT_TOPIC}
PARENT_DIR: ${PARENT_DIR}
DATE: ${DATE}
FORMAT: ${PARENT_FORMAT}
SUCCESS_COUNT: ${SUCCESS_COUNT}
CHILDREN: ${CHILDREN_JSON}

Use the synthesis skill. Write the parent index.md to PARENT_DIR/index.md.
EOF
)"

  claude --dangerously-skip-permissions \
         --print \
         --output-format json \
         --append-system-prompt "$SKILL_CONTENT" \
         "$PROMPT" > "$PARENT_DIR/.synthesis-result.json" || true

  rm -f "$PARENT_DIR/.synthesis-result.json"
fi

# Synthesis fallback: if claude didn't write index.{md,html}, emit a minimal
# placeholder so the Atlas expedition layout still renders the children grid.
if [ ! -f "$PARENT_DIR/index.md" ] && [ ! -f "$PARENT_DIR/index.html" ]; then
  cat > "$PARENT_DIR/index.md" <<MD
---
layout: expedition
title: $(basename "$PARENT_DIR")
date: $DATE
topic: $PARENT_TOPIC
format: $PARENT_FORMAT
synthesis: false
children: $CHILDREN_JSON
---

Synthesis pass produced no output during this run. See child page(s) below.
MD
fi

# --- Publish: one commit covers parent synthesis + every child subfolder. ---
SOFT_LOG="$(mktemp -t scout-decompose-softfail.XXXXXX.log)"
PARENT_BASE="$(basename "$PARENT_DIR")"
PARENT_SLUG="${PARENT_BASE#"$DATE"-}"

(
  cd "$SCOUT_DIR"
  env TOPIC="$PARENT_TOPIC" SLUG="$PARENT_SLUG" DATE="$DATE" \
      ATLAS_REPO="${ATLAS_REPO:-}" \
      ISSUE_NUMBER="${ISSUE_NUMBER:-}" \
      GH_TOKEN="${GH_TOKEN:-}" GH_REPO="${GH_REPO:-}" \
      RESEARCH_DIR="$PARENT_DIR" \
      SOFT_FAIL_LOG="$SOFT_LOG" \
      bash "$SCOUT_DIR/scripts/publish.sh"
)
rm -f "$SOFT_LOG"
