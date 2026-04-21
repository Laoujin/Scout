#!/usr/bin/env bash
# Commit + push whatever Scout wrote into atlas-checkout/_research/.
# Atlas is a Jekyll site; GitHub Pages rebuilds the index from frontmatter on push.

set -euo pipefail

ATLAS_DIR="atlas-checkout"
TOPIC="${TOPIC:-research}"
SLUG="${SLUG:-unknown}"
DATE="${DATE:-$(date +%F)}"

if [ ! -d "$ATLAS_DIR/.git" ]; then
  echo "Error: $ATLAS_DIR does not exist or is not a git checkout." >&2
  exit 1
fi

cd "$ATLAS_DIR"
git add .

if git diff --cached --quiet; then
  echo "publish.sh: nothing to commit (Scout may have failed to write an artifact)." >&2
  exit 2
fi

# Commit as the triggering GitHub user. Workflow sets GIT_{AUTHOR,COMMITTER}_{NAME,EMAIL}
# from ${{ github.actor }} / ${{ github.actor_id }}. Fall back to Scout if run outside CI.
git -c user.name="${GIT_AUTHOR_NAME:-Scout}" \
    -c user.email="${GIT_AUTHOR_EMAIL:-scout@users.noreply.github.com}" \
  commit -m "research: ${DATE} ${SLUG}" -m "Topic: ${TOPIC}"

git push origin master

# Derive the Pages URL from ATLAS_REPO (git@github.com-atlas:<owner>/<repo>.git).
atlas_slug="${ATLAS_REPO#*:}"; atlas_slug="${atlas_slug%.git}"
owner="${atlas_slug%%/*}"; repo="${atlas_slug##*/}"
ATLAS_URL="https://${owner,,}.github.io/${repo}/research/${DATE}-${SLUG}/"
echo "Published: ${ATLAS_URL}"

# If this run came from an issue, comment the artifact link and close it.
if [ -n "${ISSUE_NUMBER:-}" ] && [ -n "${GH_TOKEN:-}" ] && [ -n "${GH_REPO:-}" ]; then
  gh issue comment "$ISSUE_NUMBER" --repo "$GH_REPO" \
    --body "Published: ${ATLAS_URL}"
  gh issue close "$ISSUE_NUMBER" --repo "$GH_REPO" --reason completed
fi
