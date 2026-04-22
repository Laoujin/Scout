#!/usr/bin/env bash
# Validates a citations.jsonl ledger against Scout's schema.
# Fails with a descriptive error on the first violation.
# Usage: validate_ledger.sh <ledger_path> [<artifact_path>]
#   If artifact_path is given, also checks every [[n]] in the artifact resolves.

set -euo pipefail

LEDGER="${1:?ledger path required}"
ARTIFACT="${2:-}"

if [ ! -f "$LEDGER" ]; then
  echo "validate_ledger: file not found: $LEDGER" >&2
  exit 1
fi

LINE_NUM=0
declare -A SEEN_URLS
while IFS= read -r LINE || [ -n "$LINE" ]; do
  LINE_NUM=$((LINE_NUM + 1))
  [ -z "$LINE" ] && continue

  if ! echo "$LINE" | jq empty 2>/dev/null; then
    echo "validate_ledger: line $LINE_NUM is not valid JSON" >&2
    exit 1
  fi

  URL=$(echo "$LINE" | jq -r '.url // empty')
  CLAIM=$(echo "$LINE" | jq -r '.claim // empty')
  SOURCE_TYPE=$(echo "$LINE" | jq -r '.source_type // empty')

  if [ -z "$URL" ]; then
    echo "validate_ledger: line $LINE_NUM has empty url" >&2
    exit 1
  fi

  if [ -z "$CLAIM" ]; then
    echo "validate_ledger: line $LINE_NUM has empty claim" >&2
    exit 1
  fi

  if [ -z "$SOURCE_TYPE" ]; then
    echo "validate_ledger: line $LINE_NUM missing source_type" >&2
    exit 1
  fi

  case "$SOURCE_TYPE" in
    official|peer-reviewed|vendor-blog|forum|news|wiki) ;;
    *)
      echo "validate_ledger: line $LINE_NUM has unknown source_type: $SOURCE_TYPE" >&2
      exit 1
      ;;
  esac

  if [ -n "${SEEN_URLS[$URL]:-}" ]; then
    echo "validate_ledger: duplicate url at line $LINE_NUM: $URL (first seen at line ${SEEN_URLS[$URL]})" >&2
    exit 1
  fi
  SEEN_URLS[$URL]=$LINE_NUM
done < "$LEDGER"

if [ -n "$ARTIFACT" ] && [ -f "$ARTIFACT" ]; then
  MAX_N=$(jq -s 'map(.n) | max' "$LEDGER")
  UNRESOLVED=$(grep -oE '\[\[[0-9]+\]\]' "$ARTIFACT" | tr -d '[]' | sort -nu | awk -v max="$MAX_N" '$1 > max {print}')
  if [ -n "$UNRESOLVED" ]; then
    echo "validate_ledger: artifact references [[n]] markers beyond ledger size ($MAX_N):" >&2
    echo "$UNRESOLVED" >&2
    exit 1
  fi
fi

echo "validate_ledger: OK ($LINE_NUM entries)"
