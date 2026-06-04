#!/usr/bin/env bash
# Backfill missing model / duration_sec / cost_usd into legacy research
# frontmatter, reading truthful values from each node's .scout-result.json.
# Only fields the triage scanner flags as MISSING_* are injected, so the
# scanner's exemptions (tiny/failed bodies, sub-runs, parent cost) are honoured
# and nothing is fabricated — a node with no result JSON is left flagged.
# Idempotent. Usage: backfill-metadata.sh <research-root>

set -euo pipefail

ROOT="${1:?usage: backfill-metadata.sh <research-root>}"
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
       | map(select(. == "MISSING_MODEL" or . == "MISSING_DURATION" or . == "MISSING_COST"))}
  | select(.cats | length > 0)
  | "\(.p)\t\(.cats | join(","))"' <<<"$health")

backfilled=0; lost=0
for row in "${rows[@]}"; do
  rel="${row%%$'\t'*}"; cats=",${row#*$'\t'},"
  node="$ROOT/$rel"
  art=""
  for ext in md html; do [ -f "$node/index.$ext" ] && { art="$node/index.$ext"; break; }; done
  [ -n "$art" ] || continue

  res="$node/.scout-result.json"
  if [ ! -f "$res" ]; then
    echo "  lost: $rel (no .scout-result.json)"; lost=$((lost + 1)); continue
  fi

  inject=()
  if [[ "$cats" == *",MISSING_MODEL,"* ]]; then
    m="$(scout_model_label_from_result "$res")"
    [ -n "$m" ] && inject+=("model: \"$m\"")
  fi
  if [[ "$cats" == *",MISSING_DURATION,"* ]]; then
    d="$(jq -r '.duration_ms // empty' "$res")"
    [ -n "$d" ] && inject+=("duration_sec: $(( (d + 500) / 1000 ))")
  fi
  if [[ "$cats" == *",MISSING_COST,"* ]]; then
    c="$(jq -r '.total_cost_usd // empty' "$res")"
    [ -n "$c" ] && inject+=("cost_usd: $c")
  fi

  if [ "${#inject[@]}" -eq 0 ]; then
    echo "  lost: $rel (result lacks usable fields)"; lost=$((lost + 1)); continue
  fi

  # Insert the new fields just before the closing frontmatter delimiter.
  end_line=$(awk '/^---$/{n++; if(n==2){print NR; exit}}' "$art")
  block="$(printf '%s\n' "${inject[@]}")"
  tmp=$(mktemp)
  awk -v end="$end_line" -v block="$block" 'NR==end{printf "%s\n", block} {print}' "$art" > "$tmp"
  mv "$tmp" "$art"
  echo "  fixed: $rel  [${inject[*]}]"
  backfilled=$((backfilled + 1))
done

echo "backfill: $backfilled node(s) updated, $lost lost (no/empty result)"
