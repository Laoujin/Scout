#!/usr/bin/env bash
# Merge per-agent citation ledgers into a single citations.jsonl.
# Dedupe by URL, renumber n starting at 1, preserve first-seen order.
# Usage: merge_ledgers.sh <research_dir>

set -euo pipefail

RESEARCH_DIR="${1:?research_dir required}"
cd "$RESEARCH_DIR"

shopt -s nullglob
AGENT_LEDGERS=(citations.a*.jsonl)

if [ ${#AGENT_LEDGERS[@]} -eq 0 ]; then
  echo "merge_ledgers: no per-agent ledgers found in $RESEARCH_DIR" >&2
  exit 1
fi

# Concatenate, dedupe by url (first occurrence wins), renumber.
# jq: slurp all lines, tag with original index so first-seen wins per URL,
# group by url, take min-index of each group, sort by that index, renumber n.
jq -s -c '
  to_entries
  | group_by(.value.url)
  | map(min_by(.key))
  | sort_by(.key)
  | to_entries
  | map(.value.value + {n: (.key + 1)})
  | .[]
' "${AGENT_LEDGERS[@]}" > citations.jsonl

# Also write the set of URLs for EXCLUDE_URLS use by remediation researchers
jq -r '.url' citations.jsonl > citations.urls.txt

echo "merge_ledgers: wrote $(wc -l < citations.jsonl) entries to citations.jsonl"
