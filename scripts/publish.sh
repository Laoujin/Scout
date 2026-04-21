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
echo "Published: https://laoujin.github.io/Atlas/research/${DATE}-${SLUG}/"
