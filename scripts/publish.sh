#!/usr/bin/env bash
# Commit + push whatever Scout wrote into the publish target.
# Atlas is a Jekyll site; GitHub Pages rebuilds the index from frontmatter on push.
#
# Dual-mode:
#   worktree mode (WORKTREE set) — per-run worktree from local-setup.sh; cleans up after.
#   legacy mode   (WORKTREE unset) — CI's atlas-checkout; unchanged pre-Task-4 behavior.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=scripts/lib-publish.sh
source "$SCRIPT_DIR/lib-publish.sh"

if [ -n "${WORKTREE:-}" ]; then
  BRANCH="${BRANCH:?BRANCH is required in worktree mode}"
  ATLAS_DIR="${ATLAS_DIR:?ATLAS_DIR is required in worktree mode}"
  [ -e "$WORKTREE/.git" ] || { echo "Error: $WORKTREE is not a git worktree." >&2; exit 1; }
  cd "$WORKTREE"
  PUBLISH_MODE=worktree
else
  ATLAS_DIR="atlas-checkout"
  [ -d "$ATLAS_DIR/.git" ] || { echo "Error: $ATLAS_DIR does not exist or is not a git checkout." >&2; exit 1; }
  cd "$ATLAS_DIR"
  PUBLISH_MODE=legacy
fi
TOPIC="${TOPIC:-research}"
SLUG="${SLUG:-unknown}"
DATE="${DATE:-$(date +%F)}"

COMMIT_MSG="$(printf 'research: %s %s\n\nTopic: %s' "$DATE" "$SLUG" "$TOPIC")"
[ "$PUBLISH_MODE" = legacy ] && BRANCH="scout/${DATE}-${SLUG}"

rc=0; publish_path "$COMMIT_MSG" "." "$BRANCH" || rc=$?
case "$rc" in
  0) ;;
  2) echo "publish.sh: nothing to commit (Scout may have failed to write an artifact)." >&2; exit 2 ;;
  *) exit 1 ;;
esac

if [ "$PUBLISH_MODE" = worktree ]; then
  # Derive the Pages URL from the worktree's origin remote (the publish target).
  # Handles SSH (git@host:owner/repo.git), host-alias SSH, and HTTPS URLs.
  origin_url="$(git -C "$WORKTREE" remote get-url origin)"
  u="${origin_url%.git}"
  if [[ "$u" == http*://* ]]; then path="${u#*://}"; path="${path#*/}"; else path="${u##*:}"; fi
  owner="${path%%/*}"; repo="${path##*/}"
  ATLAS_URL="https://${owner,,}.github.io/${repo}/research/${DATE}-${SLUG}/"
else
  # Derive the Pages URL from ATLAS_REPO (git@github.com-atlas:<owner>/<repo>.git).
  atlas_slug="${ATLAS_REPO#*:}"; atlas_slug="${atlas_slug%.git}"
  owner="${atlas_slug%%/*}"; repo="${atlas_slug##*/}"
  ATLAS_URL="https://${owner,,}.github.io/${repo}/research/${DATE}-${SLUG}/"
fi
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

# If this run came from an issue, comment the artifact link. The issue stays
# open after publish; it auto-closes after the views job finishes (Task 8),
# or the user closes it manually if they don't want views.
if [ -n "${ISSUE_NUMBER:-}" ] && [ -n "${GH_TOKEN:-}" ] && [ -n "${GH_REPO:-}" ]; then
  gh issue comment "$ISSUE_NUMBER" --repo "$GH_REPO" \
    --body "Published: ${ATLAS_URL}"
  if [ -n "${SOFT_FAIL_LOG:-}" ] && [ -s "$SOFT_FAIL_LOG" ]; then
    gh issue comment "$ISSUE_NUMBER" --repo "$GH_REPO" --body "$(printf 'Published, but some non-blocking steps failed. Review and close manually.\n\n```\n%s\n```' "$(cat "$SOFT_FAIL_LOG")")"
  fi
  # Post the candidacy comment if a candidacy file was produced. The issue
  # stays open after publish; it auto-closes after the views job finishes
  # (or the user closes it manually if they don't want views).
  if [ -n "${RESEARCH_DIR:-}" ] && [ -f "${RESEARCH_DIR}/.view-candidacy.json" ]; then
    SCOUT_DIR_RESOLVED="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
    ISSUE_NUMBER="$ISSUE_NUMBER" GH_TOKEN="$GH_TOKEN" GH_REPO="$GH_REPO" \
      RESEARCH_DIR="$RESEARCH_DIR" \
      bash "$SCOUT_DIR_RESOLVED/scripts/views-comment.sh" \
      || echo "publish.sh: views-comment.sh failed (non-fatal)" >&2
  fi
fi

# Success: retire this run's worktree + branch (non-fatal — publish already done).
# Runs LAST so the SOFT_FAIL/issue blocks above can still read RESEARCH_DIR (which
# lives inside the worktree) before the worktree is deleted. Worktree mode only.
if [ "${PUBLISH_MODE:-}" = worktree ]; then
  git -C "$ATLAS_DIR" worktree remove "$WORKTREE" 2>/dev/null \
    || echo "publish.sh: could not remove worktree $WORKTREE (remove it manually)" >&2
  git -C "$ATLAS_DIR" branch -D "$BRANCH" >/dev/null 2>&1 || true
fi
