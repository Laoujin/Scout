#!/usr/bin/env bash
# Insert cost_usd and duration_sec into the YAML frontmatter of a research
# artifact (index.md or index.html), immediately before the closing `---`.
# Usage: inject_cost.sh <artifact-path> <cost_usd> <duration_sec>

set -euo pipefail

if [ "$#" -ne 3 ]; then
  echo "inject_cost.sh: usage: inject_cost.sh <artifact> <cost_usd> <duration_sec>" >&2
  exit 1
fi

ARTIFACT="$1"
COST="$2"
DURATION="$3"

if [ ! -f "$ARTIFACT" ]; then
  echo "inject_cost.sh: artifact not found: $ARTIFACT" >&2
  exit 1
fi

# Frontmatter check: first line must be `---`, and there must be a second `---`.
first_line=$(head -n 1 "$ARTIFACT")
if [ "$first_line" != "---" ]; then
  echo "inject_cost.sh: no opening frontmatter delimiter in $ARTIFACT" >&2
  exit 1
fi

# Find the line number of the closing `---` (second occurrence of a line that is exactly `---`).
end_line=$(awk '/^---$/{n++; if(n==2){print NR; exit}}' "$ARTIFACT")
if [ -z "$end_line" ]; then
  echo "inject_cost.sh: no closing frontmatter delimiter in $ARTIFACT" >&2
  exit 1
fi

tmp=$(mktemp)
awk -v end="$end_line" -v cost="$COST" -v dur="$DURATION" '
  NR == end { printf "cost_usd: %s\nduration_sec: %s\n", cost, dur }
  { print }
' "$ARTIFACT" > "$tmp"
mv "$tmp" "$ARTIFACT"
