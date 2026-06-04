#!/usr/bin/env bash
# Backfill missing model / duration_sec / cost_usd (and issue) into legacy
# research frontmatter, reading truthful values from each node's
# .scout-result.json (issue is GitHub-only, so it is sentinel-only).
# Only fields the triage scanner flags as MISSING_* are injected, so the
# scanner's exemptions (tiny/failed bodies, sub-runs, parent cost) are honoured.
# A field that can't be recovered (no/empty result JSON) is left flagged — UNLESS
# BACKFILL_SENTINEL is set, in which case the unrecoverable field is stamped with
# that sentinel string (e.g. "n/a") so it clears the health backlog without
# faking a number. Real values are always preferred over the sentinel.
# Idempotent. Usage: [BACKFILL_SENTINEL=n/a] backfill-metadata.sh <research-root>

set -euo pipefail

ROOT="${1:?usage: backfill-metadata.sh <research-root>}"
SENTINEL="${BACKFILL_SENTINEL:-}"
DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SCAN="$DIR/../skills/scout-triage/scan.py"
# shellcheck source=lib-models.sh
. "$DIR/lib-models.sh"

[ -d "$ROOT" ] || { echo "backfill: not a directory: $ROOT" >&2; exit 1; }
command -v jq >/dev/null 2>&1 || { echo "backfill: jq required" >&2; exit 1; }

health="$(python3 "$SCAN" --health "$ROOT")"

# "relpath<TAB>CAT,CAT" for every node with a backfillable MISSING_* finding.
mapfile -t rows < <(jq -r '
  .hygiene[].items[]
  | {p: .path, cats: [.findings[].category]
       | map(select(. == "MISSING_MODEL" or . == "MISSING_DURATION"
                    or . == "MISSING_COST" or . == "MISSING_ISSUE"))}
  | select(.cats | length > 0)
  | "\(.p)\t\(.cats | join(","))"' <<<"$health")

backfilled=0; lost=0; marked=0
for row in "${rows[@]}"; do
  rel="${row%%$'\t'*}"; cats=",${row#*$'\t'},"
  node="$ROOT/$rel"
  art=""
  for ext in md html; do [ -f "$node/index.$ext" ] && { art="$node/index.$ext"; break; }; done
  [ -n "$art" ] || continue

  res="$node/.scout-result.json"
  have_res=0; [ -f "$res" ] && have_res=1

  inject=(); sentineled=0
  if [[ "$cats" == *",MISSING_MODEL,"* ]]; then
    m=""; [ "$have_res" = 1 ] && m="$(scout_model_label_from_result "$res")"
    if [ -n "$m" ]; then inject+=("model: \"$m\"")
    elif [ -n "$SENTINEL" ]; then inject+=("model: \"$SENTINEL\""); sentineled=1; fi
  fi
  if [[ "$cats" == *",MISSING_DURATION,"* ]]; then
    d=""; [ "$have_res" = 1 ] && d="$(jq -r '.duration_ms // empty' "$res")"
    if [ -n "$d" ]; then inject+=("duration_sec: $(( (d + 500) / 1000 ))")
    elif [ -n "$SENTINEL" ]; then inject+=("duration_sec: \"$SENTINEL\""); sentineled=1; fi
  fi
  if [[ "$cats" == *",MISSING_COST,"* ]]; then
    c=""; [ "$have_res" = 1 ] && c="$(jq -r '.total_cost_usd // empty' "$res")"
    if [ -n "$c" ]; then inject+=("cost_usd: $c")
    elif [ -n "$SENTINEL" ]; then inject+=("cost_usd: \"$SENTINEL\""); sentineled=1; fi
  fi
  # issue is a GitHub artifact, never in the result JSON — sentinel-only.
  if [[ "$cats" == *",MISSING_ISSUE,"* ]] && [ -n "$SENTINEL" ]; then
    inject+=("issue: \"$SENTINEL\""); sentineled=1
  fi

  if [ "${#inject[@]}" -eq 0 ]; then
    echo "  lost: $rel (no recoverable data; set BACKFILL_SENTINEL to mark unrecorded)"
    lost=$((lost + 1)); continue
  fi

  # Insert the new fields just before the closing frontmatter delimiter.
  end_line=$(awk '/^---$/{n++; if(n==2){print NR; exit}}' "$art")
  block="$(printf '%s\n' "${inject[@]}")"
  tmp=$(mktemp)
  awk -v end="$end_line" -v block="$block" 'NR==end{printf "%s\n", block} {print}' "$art" > "$tmp"
  mv "$tmp" "$art"
  if [ "$sentineled" = 1 ]; then
    echo "  marked: $rel  [${inject[*]}]"; marked=$((marked + 1))
  else
    echo "  fixed: $rel  [${inject[*]}]"
  fi
  backfilled=$((backfilled + 1))
done

echo "backfill: $backfilled node(s) updated ($marked with sentinel '$SENTINEL'), $lost lost"
