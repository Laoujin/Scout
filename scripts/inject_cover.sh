#!/usr/bin/env bash
# Wire `cover: cover.svg` into an artifact's YAML frontmatter when a cover.svg
# sits beside it. Deterministic counterpart to the LLM "add cover: if the
# illustrator wrote one" step, so local /scout runs reliably wire child covers
# instead of leaving cover.svg orphaned (triage MISSING_COVER).
# Idempotent; a no-op (exit 0) when there's no cover.svg or cover: is already set.
# Usage: inject_cover.sh <artifact-path>

set -euo pipefail

if [ "$#" -ne 1 ]; then
  echo "inject_cover.sh: usage: inject_cover.sh <artifact>" >&2
  exit 1
fi

ARTIFACT="$1"
if [ ! -f "$ARTIFACT" ]; then
  echo "inject_cover.sh: artifact not found: $ARTIFACT" >&2
  exit 1
fi

# Frontmatter must open on line 1 and have a closing delimiter.
if [ "$(head -n 1 "$ARTIFACT")" != "---" ]; then
  echo "inject_cover.sh: no opening frontmatter delimiter in $ARTIFACT" >&2
  exit 1
fi
end_line=$(awk '/^---$/{n++; if(n==2){print NR; exit}}' "$ARTIFACT")
if [ -z "$end_line" ]; then
  echo "inject_cover.sh: no closing frontmatter delimiter in $ARTIFACT" >&2
  exit 1
fi

# Nothing to wire if there's no cover beside the artifact.
if [ ! -f "$(dirname "$ARTIFACT")/cover.svg" ]; then
  exit 0
fi

# Already wired — leave it (idempotent).
if awk -v end="$end_line" 'NR<end && /^cover:[[:space:]]/{found=1} END{exit !found}' "$ARTIFACT"; then
  exit 0
fi

tmp=$(mktemp)
awk -v end="$end_line" 'NR == end { print "cover: cover.svg" } { print }' "$ARTIFACT" > "$tmp"
mv "$tmp" "$ARTIFACT"
