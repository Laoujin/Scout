#!/usr/bin/env bash
# Validate that an artifact's YAML frontmatter parses cleanly.
# Usage: validate_frontmatter.sh <artifact-file>
# Exits 0 on valid YAML, 1 on parse error or missing frontmatter.
#
# Two layers:
#   1. Bash heuristic (always runs): catches the most common Jekyll-breaking
#      patterns — freeform fields (title, summary, topic, topic_raw) whose
#      values contain unquoted colons or unbalanced quotes.
#   2. Python yaml.safe_load (when available): full YAML parse. Skipped
#      gracefully when Python isn't installed.

set -euo pipefail

ARTIFACT="${1:?Usage: validate_frontmatter.sh <file>}"

if [ ! -f "$ARTIFACT" ]; then
  echo "validate_frontmatter.sh: file not found: $ARTIFACT" >&2
  exit 1
fi

# Extract the frontmatter block (between the first pair of --- lines).
FM="$(awk '
  /^---[[:space:]]*$/ { n++; if (n==2) exit; next }
  n==1 { print }
' "$ARTIFACT")"

if [ -z "$FM" ]; then
  echo "validate_frontmatter.sh: no YAML frontmatter found in $ARTIFACT" >&2
  exit 1
fi

# --- Layer 1: bash heuristic for freeform fields ---
# Freeform scalar fields that MUST be quoted to avoid YAML parse issues.
FREEFORM_FIELDS="title|summary|topic|topic_raw"
ERRORS=0

while IFS= read -r line; do
  # Match lines like `title: value` (top-level, no leading spaces for parent fields,
  # or 4-space indent for children array entries).
  if printf '%s' "$line" | grep -qE "^[[:space:]]*(${FREEFORM_FIELDS}):[[:space:]]"; then
    # Extract the value part after `field: `.
    value="$(printf '%s' "$line" | sed -E "s/^[[:space:]]*(${FREEFORM_FIELDS}):[[:space:]]*//")"
    [ -z "$value" ] && continue

    # Value is properly quoted if it starts+ends with matching quotes.
    if printf '%s' "$value" | grep -qE '^".*"$'; then continue; fi
    if printf '%s' "$value" | grep -qE "^'.*'$"; then continue; fi

    # Unquoted value — check for YAML-breaking characters.
    if printf '%s' "$value" | grep -qF ':'; then
      field="$(printf '%s' "$line" | sed -E 's/^[[:space:]]*([a-z_]+):.*/\1/')"
      echo "validate_frontmatter.sh: $ARTIFACT: field '$field' contains unquoted colon — wrap in double quotes" >&2
      ERRORS=$((ERRORS + 1))
    fi
    if printf '%s' "$value" | grep -qF '"'; then
      field="$(printf '%s' "$line" | sed -E 's/^[[:space:]]*([a-z_]+):.*/\1/')"
      echo "validate_frontmatter.sh: $ARTIFACT: field '$field' contains unquoted double quote — wrap value in single quotes or escape" >&2
      ERRORS=$((ERRORS + 1))
    fi
  fi
done <<< "$FM"

[ "$ERRORS" -gt 0 ] && exit 1

# --- Layer 2: full YAML parse (when Python is available) ---
if command -v python3 >/dev/null 2>&1; then
  PY=python3
elif command -v python >/dev/null 2>&1; then
  PY=python
else
  exit 0
fi

# Verify it's real Python, not a Windows Store stub.
"$PY" -c "import sys" 2>/dev/null || exit 0

ERR="$(printf '%s' "$FM" | "$PY" -c "
import sys, yaml
try:
    data = yaml.safe_load(sys.stdin.read())
    if not isinstance(data, dict):
        print('frontmatter parsed but is not a mapping', file=sys.stderr)
        sys.exit(1)
except yaml.YAMLError as e:
    print(f'YAML parse error: {e}', file=sys.stderr)
    sys.exit(1)
" 2>&1)" || {
  echo "validate_frontmatter.sh: $ARTIFACT has invalid YAML frontmatter:" >&2
  echo "$ERR" >&2
  exit 1
}
