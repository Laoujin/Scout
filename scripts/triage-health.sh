#!/usr/bin/env bash
# Regenerate Atlas's _data/health.json (the data behind the /health page + homepage
# pill) from a fresh Atlas clone, and push it to main. Run daily by the triage workflow.
# scan.py makes zero model calls — a cheap, deterministic, network-free local audit.
set -euo pipefail

SCOUT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
source "$SCOUT_DIR/scripts/lib-publish.sh"   # commit_with_identity
: "${ATLAS_REPO:?set ATLAS_REPO (SSH alias, e.g. git@github.com-atlas:owner/Atlas.git)}"

WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT

git clone --depth=1 "$ATLAS_REPO" "$WORK/atlas" >/dev/null 2>&1 || {
  echo "triage-health: failed to clone Atlas from $ATLAS_REPO" >&2; exit 1; }

mkdir -p "$WORK/atlas/_data"
python3 "$SCOUT_DIR/skills/scout-triage/scan.py" --health "$WORK/atlas/research" \
  > "$WORK/atlas/_data/health.json"

cd "$WORK/atlas"
git add _data/health.json
if git diff --cached --quiet; then
  echo "triage-health: health.json unchanged — nothing to push"
  exit 0
fi

commit_with_identity "health: $(date -u +%F) triage snapshot"
# A concurrent push (e.g. a research run) is rare in this short job; rebase + retry once.
git push origin main 2>/dev/null \
  || { git fetch -q origin main && git rebase -q origin/main && git push origin main; }

echo "triage-health: pushed health.json — $(python3 -c "import json;print(json.load(open('_data/health.json'))['counts'])")"
