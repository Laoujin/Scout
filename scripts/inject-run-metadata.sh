#!/usr/bin/env bash
# Deterministically stamp model / duration_sec / cost_usd (+ issue on the parent)
# into a /scout expedition's frontmatter — agent-independent, mirroring
# inject_cover.sh. Idempotent: inserts a field only when absent, never overwrites.
# Child duration comes from manifest.json (end-start); parent duration is the
# manifest wall-clock (max end - min start), or the DURATION env for single-pass.
#
# Usage: MODEL="Opus 4.8" [COST=sub] [ISSUE=42] [DURATION=<sec>] \
#          inject-run-metadata.sh <research-dir>
set -euo pipefail
DIR="${1:?usage: inject-run-metadata.sh <research-dir>}"
MODEL="${MODEL:?MODEL is required (friendly label, e.g. \"Opus 4.8\")}"
COST="${COST:-sub}"
ISSUE="${ISSUE:-}"
DURATION="${DURATION:-}"
command -v jq >/dev/null 2>&1 || { echo "inject-run-metadata: jq required" >&2; exit 1; }

# Insert "key: value" before the closing frontmatter delimiter, iff key is absent
# from the frontmatter block. No-op when already present. Mirrors backfill-metadata.sh.
_stamp() {
  local file="$1" key="$2" value="$3" end tmp
  [ -f "$file" ] || return 0
  if awk -v k="$key" '
        /^---$/ { if (++n==2) exit }
        n==1 && $0 ~ "^"k":" { found=1; exit }
        END { exit !found }' "$file"; then
    return 0   # already present
  fi
  end=$(awk '/^---$/{n++; if(n==2){print NR; exit}}' "$file")
  [ -n "$end" ] || return 0
  tmp="$(mktemp)"
  awk -v end="$end" -v line="$key: $value" 'NR==end{print line} {print}' "$file" > "$tmp"
  mv "$tmp" "$file"
}

_artifact() {
  local d="$1"
  [ -f "$d/index.md" ]   && { printf '%s' "$d/index.md";   return; }
  [ -f "$d/index.html" ] && { printf '%s' "$d/index.html"; return; }
  return 0
}

MANIFEST="$DIR/manifest.json"

# --- Parent ---
P="$(_artifact "$DIR")"
if [ -n "$P" ]; then
  _stamp "$P" model "\"$MODEL\""
  _stamp "$P" cost_usd "\"$COST\""
  if [ -n "$ISSUE" ]; then
    _stamp "$P" issue "$ISSUE"
  fi
  if [ -f "$MANIFEST" ]; then
    wall="$(jq -r '([.[].end]|max) - ([.[].start]|min)' "$MANIFEST" 2>/dev/null || true)"
    if [ -n "$wall" ] && [ "$wall" != "null" ]; then
      _stamp "$P" duration_sec "$wall"
    fi
  elif [ -n "$DURATION" ]; then
    _stamp "$P" duration_sec "$DURATION"
  fi
fi

# --- Children (manifest order; model/cost/duration each) ---
if [ -f "$MANIFEST" ]; then
  while IFS=$'\t' read -r slug dur; do
    [ -n "$slug" ] || continue
    C="$(_artifact "$DIR/$slug")"
    [ -n "$C" ] || continue
    _stamp "$C" model "\"$MODEL\""
    _stamp "$C" cost_usd "\"$COST\""
    _stamp "$C" duration_sec "$dur"
  done < <(jq -r '.[] | "\(.slug)\t\(.end - .start)"' "$MANIFEST")
fi
