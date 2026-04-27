#!/usr/bin/env bash
# Commit + push whatever Scout wrote into atlas-checkout/_research/.
# Atlas is a Jekyll site; GitHub Pages rebuilds the index from frontmatter on push.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=scripts/lib-publish.sh
source "$SCRIPT_DIR/lib-publish.sh"

ATLAS_DIR="atlas-checkout"
TOPIC="${TOPIC:-research}"
SLUG="${SLUG:-unknown}"
DATE="${DATE:-$(date +%F)}"

if [ ! -d "$ATLAS_DIR/.git" ]; then
  echo "Error: $ATLAS_DIR does not exist or is not a git checkout." >&2
  exit 1
fi

cd "$ATLAS_DIR"

COMMIT_MSG="$(printf 'research: %s %s\n\nTopic: %s' "$DATE" "$SLUG" "$TOPIC")"
BRANCH="scout/${DATE}-${SLUG}"

rc=0; publish_path "$COMMIT_MSG" "." "$BRANCH" || rc=$?
case "$rc" in
  0) ;;
  2) echo "publish.sh: nothing to commit (Scout may have failed to write an artifact)." >&2; exit 2 ;;
  *) exit 1 ;;
esac

# Derive the Pages URL from ATLAS_REPO (git@github.com-atlas:<owner>/<repo>.git).
atlas_slug="${ATLAS_REPO#*:}"; atlas_slug="${atlas_slug%.git}"
owner="${atlas_slug%%/*}"; repo="${atlas_slug##*/}"
ATLAS_URL="https://${owner,,}.github.io/${repo}/research/${DATE}-${SLUG}/"
echo "Published: ${ATLAS_URL}"

# Decompose runs leave failed-child placeholders inside the parent expedition
# folder. Surface them via SOFT_FAIL_LOG so the comment block below keeps the
# issue open and lists which sub-topics failed.
if [ -n "${SOFT_FAIL_LOG:-}" ] && [ -n "${RESEARCH_DIR:-}" ] && [ -d "$RESEARCH_DIR" ]; then
  while IFS= read -r child_index; do
    child_dir="$(dirname "$child_index")"
    [ "$child_dir" = "$RESEARCH_DIR" ] && continue
    if grep -q '^status: failed' "$child_index"; then
      reason="$(awk -F': ' '/^failure_reason:/ { sub(/^failure_reason:[[:space:]]*/, ""); print; exit }' "$child_index")"
      cslug="$(basename "$child_dir")"
      echo "- \`$cslug\`: $reason" >> "$SOFT_FAIL_LOG"
    fi
  done < <(find "$RESEARCH_DIR" -mindepth 2 -maxdepth 2 \( -name 'index.md' -o -name 'index.html' \))
fi

# If this run came from an issue, comment the artifact link. Close the issue
# only when no soft failures were recorded — otherwise leave it open with a
# second comment so the user can decide how to handle the partial success.
if [ -n "${ISSUE_NUMBER:-}" ] && [ -n "${GH_TOKEN:-}" ] && [ -n "${GH_REPO:-}" ]; then
  gh issue comment "$ISSUE_NUMBER" --repo "$GH_REPO" \
    --body "Published: ${ATLAS_URL}"
  if [ -n "${SOFT_FAIL_LOG:-}" ] && [ -s "$SOFT_FAIL_LOG" ]; then
    gh issue comment "$ISSUE_NUMBER" --repo "$GH_REPO" --body "$(printf 'Published, but some non-blocking steps failed. Review and close manually.\n\n```\n%s\n```' "$(cat "$SOFT_FAIL_LOG")")"
  else
    gh issue close "$ISSUE_NUMBER" --repo "$GH_REPO" --reason completed \
      || echo "publish.sh: gh issue close failed (non-fatal); continuing." >&2
  fi
fi
