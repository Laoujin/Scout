#!/usr/bin/env bash
# Clone/fetch Atlas, regenerate its index, commit, push.
# Expects ATLAS_REPO (SSH URL) and a working tree at atlas-checkout/.
# Called by run.sh after Scout writes the artifact into atlas-checkout/research/<slug>/.

set -euo pipefail

ATLAS_REPO="${ATLAS_REPO:-git@github.com:Laoujin/atlas.git}"
ATLAS_DIR="atlas-checkout"
TOPIC="${TOPIC:-research}"
SLUG="${SLUG:-unknown}"
DATE="${DATE:-$(date +%F)}"

if [ ! -d "$ATLAS_DIR/.git" ]; then
  echo "Error: $ATLAS_DIR does not exist or is not a git checkout. run.sh must clone before calling publish.sh." >&2
  exit 1
fi

cd "$ATLAS_DIR"

node ../scripts/build_index.js "$(pwd)"

git add .

if git diff --cached --quiet; then
  echo "publish.sh: nothing to commit (Scout may have failed to write an artifact)." >&2
  exit 2
fi

git -c user.name="Scout" -c user.email="scout@users.noreply.github.com" \
  commit -m "research: ${DATE} ${SLUG}" -m "Topic: ${TOPIC}"

git push origin master
echo "Published: https://laoujin.github.io/atlas/research/${DATE}-${SLUG}/"
