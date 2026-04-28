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

# Push helpers — used to commit+push each successful child immediately so a
# mid-expedition crash doesn't lose the work of children that already finished.
# Sourced defensively (matches slug.sh pattern): tests that stub SCOUT_DIR
# without copying lib-publish.sh fall back to a no-op _publish_child.
if [ -f "$SCOUT_DIR/scripts/lib-publish.sh" ]; then
  # shellcheck source=scripts/lib-publish.sh
  source "$SCOUT_DIR/scripts/lib-publish.sh"
fi

PARENT_BASE="$(basename "$PARENT_DIR")"
PARENT_SLUG="${PARENT_BASE#"$DATE"-}"
PARENT_BRANCH="scout/${DATE}-${PARENT_SLUG}"

# Push a single child's folder to Atlas main. No-op if publish_path isn't
# available (test environments) or atlas-checkout isn't a git repo (standalone
# decompose runs without a real Atlas). Per-child push failure is non-fatal:
# the parent's final publish.sh sweep will retry with everything still on disk.
_publish_child() {
  local child_dir="$1" cslug="$2"
  declare -F publish_path >/dev/null || return 0
  local atlas_root rel_path rc=0
  atlas_root="$(cd "$child_dir" 2>/dev/null && git rev-parse --show-toplevel 2>/dev/null)" || return 0
  [ -n "$atlas_root" ] || return 0
  rel_path="${child_dir#"$atlas_root"/}"
  (
    cd "$atlas_root"
    publish_path "research: ${DATE} ${PARENT_SLUG}/${cslug}" "$rel_path" "$PARENT_BRANCH"
  ) || rc=$?
  if [ "$rc" -ne 0 ] && [ "$rc" -ne 2 ]; then
    echo "[run-decompose] per-child push failed for $cslug (rc=$rc); deferring to final publish" >&2
  fi
  return 0
}
_simple_slug() {
  printf '%s' "$1" | tr '[:upper:]' '[:lower:]' \
    | sed -e 's/[^a-z0-9]/-/g' -e 's/--*/-/g' -e 's/^-//' -e 's/-$//'
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

# Idempotent frontmatter setter: replaces <key> if present, inserts before
# closing `---` otherwise. Operates on the YAML frontmatter only.
_set_field() {
  local file="$1" key="$2" value="$3"
  local end
  end=$(awk '/^---$/{n++; if(n==2){print NR; exit}}' "$file") || return 1
  [ -n "$end" ] || return 1
  if awk -v k="$key" -v end="$end" 'NR<end && $0 ~ "^"k":" {f=1} END{exit !f}' "$file"; then
    awk -v k="$key" -v v="$value" -v end="$end" '
      NR < end && $0 ~ "^"k":" { printf "%s: %s\n", k, v; next }
      { print }
    ' "$file" > "$file.tmp" && mv "$file.tmp" "$file"
  else
    awk -v k="$key" -v v="$value" -v end="$end" '
      NR == end { printf "%s: %s\n", k, v }
      { print }
    ' "$file" > "$file.tmp" && mv "$file.tmp" "$file"
  fi
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

# Returns the path to the child's real artifact (index.html or non-placeholder
# index.md). Prefers index.html when index.md is a failure placeholder.
_child_artifact() {
  local dir="$1"
  local md="$dir/index.md" html="$dir/index.html"
  if [ -f "$md" ] && [ "$(_frontmatter_field "$md" status)" != "failed" ]; then
    echo "$md"; return 0
  fi
  if [ -f "$html" ]; then
    echo "$html"; return 0
  fi
  [ -f "$md" ] && echo "$md" && return 0
  return 1
}

# Returns 0 if the child directory contains a real (non-placeholder) artifact.
_has_real_artifact() {
  local dir="$1"
  [ -f "$dir/index.html" ] && return 0
  [ -f "$dir/index.md" ] && \
    [ "$(_frontmatter_field "$dir/index.md" status)" != "failed" ] && return 0
  return 1
}

# Annotate an existing artifact with a validation/runtime error.
# Adds a validation_error field to YAML frontmatter so the website can show a
# warning indicator while still serving the content.
_annotate_error() {
  local dir="$1" error="$2"
  local file
  file="$(_child_artifact "$dir")" || return 1
  error="$(printf '%s' "$error" | sed 's/"/\\"/g')"
  _set_field "$file" "validation_error" "\"$error\""
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
      child_err_file="$(mktemp)"
      set +e
      env TOPIC="$ctitle" RAW_TOPIC="$ctitle" DEPTH="$cdepth" \
          FORMAT="$PARENT_FORMAT_INTERNAL" RESEARCH_DIR="$child_dir" \
          ATLAS_REPO="${ATLAS_REPO:-}" \
          SCOUT_NO_PUBLISH=1 SCOUT_DECOMPOSE_CHILD=1 \
          ${RUN_LOG:+RUN_LOG="$RUN_LOG"} \
          timeout "${remaining}s" bash "$SCOUT_DIR/scripts/run.sh" 2>"$child_err_file"
      rc=$?
      set -e
      # Replay captured stderr so it's visible in workflow logs.
      [ -s "$child_err_file" ] && cat "$child_err_file" >&2
      # Extract last meaningful error lines for failure annotations.
      child_err_msg=""
      if [ "$rc" -ne 0 ] && [ -s "$child_err_file" ]; then
        child_err_msg="$(grep -v '^[[:space:]]*$' "$child_err_file" | tail -3 | tr '\n' '; ')"
        child_err_msg="${child_err_msg%%; }"
      fi
      rm -f "$child_err_file"

      if [ "$rc" -eq 0 ] && _child_is_success "$child_dir"; then
        child_status="success"
        _publish_child "$child_dir" "$cslug"
      elif _has_real_artifact "$child_dir"; then
        # Content exists but run.sh failed (validation, timeout, etc.).
        # Annotate the artifact with the error so the user sees a warning
        # but can still view the research.
        _annotate_error "$child_dir" "${child_err_msg:-run.sh exit $rc}"
        child_status="error_with_content"
        _publish_child "$child_dir" "$cslug"
      elif [ "$rc" -eq 124 ]; then
        _write_placeholder "$child_dir" "$cdepth" "hard timeout"
        child_status="failed_hard_timeout"
      else
        _write_placeholder "$child_dir" "$cdepth" "${child_err_msg:-child run.sh exit $rc}"
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
  val_error=""
  if _child_is_success "$child_dir"; then
    status="success"
    SUCCESS_COUNT=$((SUCCESS_COUNT + 1))
    src="$(_child_artifact "$child_dir")" || src="$child_dir/index.md"
    summary="$(_frontmatter_field "$src" summary)"
    [ -z "$summary" ] && summary="$(_frontmatter_field "$src" title)"
    citations="$(_frontmatter_field "$src" citations)"
    reading="$(_frontmatter_field "$src" reading_time_min)"
    val_error="$(_frontmatter_field "$src" validation_error)"
    if [ -n "$val_error" ]; then
      status="error_with_content"
    fi
    # Fallback: count ledger lines for citations if not in frontmatter.
    if [ -z "$citations" ] || [ "$citations" = "0" ]; then
      [ -f "$child_dir/citations.jsonl" ] && citations=$(grep -c '.' "$child_dir/citations.jsonl" || true)
    fi
    [ -z "$citations" ] && citations=0
    [ -z "$reading" ] && reading=0
  elif [ -f "$child_dir/index.md" ]; then
    summary="$(_frontmatter_field "$child_dir/index.md" failure_reason)"
  fi
  [ "$first" -eq 1 ] && first=0 || CHILDREN_JSON+=","
  local_json=$(printf '\n  {"slug":"%s","title":"%s","depth":"%s","status":"%s","summary":"%s","citations":%s,"reading_time_min":%s' \
    "$cslug" \
    "$(printf '%s' "$ctitle" | sed 's/"/\\"/g')" \
    "$cdepth" "$status" \
    "$(printf '%s' "$summary" | sed 's/"/\\"/g')" \
    "$citations" "$reading")
  if [ -n "$val_error" ]; then
    local_json+=$(printf ',"validation_error":"%s"' "$(printf '%s' "$val_error" | sed 's/"/\\"/g')")
  fi
  local_json+="}"
  CHILDREN_JSON+="$local_json"
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

# --- Aggregate metrics: parent synthesis + sum of successful children ---

# Extract a numeric field from a flat JSON file (jq if available, else grep+sed).
_json_num() {
  local file="$1" field="$2"
  if command -v jq >/dev/null 2>&1; then
    jq -r ".$field // 0" "$file" 2>/dev/null || echo 0
  else
    local val
    val=$(grep -o "\"$field\"[[:space:]]*:[[:space:]]*[0-9.]*" "$file" 2>/dev/null \
          | sed 's/.*:[[:space:]]*//' | head -1)
    echo "${val:-0}"
  fi
}

SYNTH_COST=0
SYNTH_DUR=0
if [ -f "$PARENT_DIR/.synthesis-result.json" ]; then
  SYNTH_COST=$(_json_num "$PARENT_DIR/.synthesis-result.json" total_cost_usd)
  SYNTH_DUR_MS=$(_json_num "$PARENT_DIR/.synthesis-result.json" duration_ms)
  SYNTH_DUR=$(( SYNTH_DUR_MS / 1000 ))
fi
# Keep .synthesis-result.json — it ships with the published research.

TOT_COST="$SYNTH_COST"
TOT_DUR="$SYNTH_DUR"
TOT_CITES=0
TOT_READING=0
for entry in "${CHILDREN[@]}"; do
  [ -n "$entry" ] || continue
  IFS='|' read -r ctitle cdepth crationale cchecked <<< "$entry"
  cslug="$(_slugify_or_simple "$ctitle")"
  child_dir="$PARENT_DIR/$cslug"
  _child_is_success "$child_dir" || continue
  c_idx="$(_child_artifact "$child_dir")" || continue
  c_cost="$(_frontmatter_field "$c_idx" cost_usd)"
  c_dur="$(_frontmatter_field "$c_idx" duration_sec)"
  c_cite="$(_frontmatter_field "$c_idx" citations)"
  c_read="$(_frontmatter_field "$c_idx" reading_time_min)"
  # Fallback: count ledger lines for citations if not in frontmatter.
  if [ -z "$c_cite" ] || [ "$c_cite" = "0" ]; then
    [ -f "$child_dir/citations.jsonl" ] && c_cite=$(grep -c '.' "$child_dir/citations.jsonl" || true)
  fi
  TOT_COST=$(awk -v a="$TOT_COST" -v b="${c_cost:-0}" 'BEGIN{print a+b}')
  TOT_DUR=$(( TOT_DUR + ${c_dur:-0} ))
  TOT_CITES=$(( TOT_CITES + ${c_cite:-0} ))
  TOT_READING=$(( TOT_READING + ${c_read:-0} ))
done
TOT_COST_2DP=$(awk -v c="$TOT_COST" 'BEGIN{printf "%.2f", c}')

PARENT_FILE=""
[ -f "$PARENT_DIR/index.md"   ] && PARENT_FILE="$PARENT_DIR/index.md"
[ -z "$PARENT_FILE" ] && [ -f "$PARENT_DIR/index.html" ] && PARENT_FILE="$PARENT_DIR/index.html"
if [ -n "$PARENT_FILE" ]; then
  _set_field "$PARENT_FILE" cost_usd         "$TOT_COST_2DP"
  _set_field "$PARENT_FILE" duration_sec     "$TOT_DUR"
  _set_field "$PARENT_FILE" citations        "$TOT_CITES"
  _set_field "$PARENT_FILE" reading_time_min "$TOT_READING"
fi

# --- Title-based slug rename for parent expedition ---------------------------
# Derive a cleaner slug from the synthesis frontmatter title instead of the raw
# topic. Children were already pushed under the old path; the final publish
# stages the rename so the end state on main uses the new slug.
if [ -n "$PARENT_FILE" ]; then
  FM_TITLE="$(_frontmatter_field "$PARENT_FILE" title)"
  if [ -n "$FM_TITLE" ]; then
    TITLE_SLUG="$(_slugify_or_simple "$FM_TITLE")"
    if [ -n "$TITLE_SLUG" ] && [ "$TITLE_SLUG" != "$PARENT_SLUG" ]; then
      RESEARCH_PARENT="$(dirname "$PARENT_DIR")"
      NEW_DIR="$RESEARCH_PARENT/${DATE}-${TITLE_SLUG}"
      if [ -d "$NEW_DIR" ]; then
        n=2
        while [ -d "$RESEARCH_PARENT/${DATE}-${TITLE_SLUG}-${n}" ]; do
          n=$((n+1))
        done
        TITLE_SLUG="${TITLE_SLUG}-${n}"
        NEW_DIR="$RESEARCH_PARENT/${DATE}-${TITLE_SLUG}"
      fi
      mv "$PARENT_DIR" "$NEW_DIR"
      PARENT_DIR="$NEW_DIR"
      PARENT_SLUG="$TITLE_SLUG"
      echo "[run-decompose] renamed parent dir to: ${DATE}-${PARENT_SLUG}" >&2
    fi
  fi
fi

# --- Publish: parent synthesis + manifest + any failure placeholders. ---
# Children that succeeded were already pushed individually inside the loop; this
# final publish picks up whatever's left (synthesis index.md, manifest.json,
# placeholders for failed/skipped children).
SOFT_LOG="$(mktemp -t scout-decompose-softfail.XXXXXX.log)"

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
