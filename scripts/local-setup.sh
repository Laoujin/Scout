#!/usr/bin/env bash
# Setup for an interactive (subscription) Scout run. Resolves SCOUT_DIR +
# ATLAS_REPO, clones Atlas fresh, computes a unique research dir, makes child
# dirs, and prints KEY=VALUE lines for the /scout command. No claude -p — the
# interactive session is the research agent.
set -euo pipefail

TITLE="${1:?usage: local-setup.sh <title>}"

# Resolve SCOUT_DIR: explicit pointer, else walk up to the playbook.
if [ -f "$HOME/.scout/dir" ]; then
  SCOUT_DIR="$(cat "$HOME/.scout/dir")"
else
  d="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
  while [ "$d" != "/" ] && [ ! -f "$d/skills/scout/SKILL.md" ]; do d="$(dirname "$d")"; done
  [ -f "$d/skills/scout/SKILL.md" ] || {
    echo "Error: cannot locate SCOUT_DIR (no skills/scout/SKILL.md above $(pwd) and no ~/.scout/dir)" >&2
    exit 1; }
  SCOUT_DIR="$d"
fi

# Resolve ATLAS_REPO: env override, else docker/.env, else error.
if [ -z "${ATLAS_REPO:-}" ] && [ -f "$SCOUT_DIR/docker/.env" ]; then
  ATLAS_REPO="$(grep -E '^ATLAS_REPO=' "$SCOUT_DIR/docker/.env" | head -1 | cut -d= -f2-)"
fi
[ -n "${ATLAS_REPO:-}" ] || {
  echo "Error: set ATLAS_REPO (env) or add it to \$SCOUT_DIR/docker/.env" >&2
  exit 1; }

DATE="${DATE:-$(date +%F)}"

cd "$SCOUT_DIR"
# shellcheck source=scripts/slug.sh
source "$SCOUT_DIR/scripts/slug.sh"

rm -rf atlas-checkout
git clone --depth=1 --filter=blob:none "$ATLAS_REPO" atlas-checkout >/dev/null 2>&1 || {
  echo "Error: failed to clone Atlas from $ATLAS_REPO (check SSH key / ~/.ssh/config alias / network)" >&2
  exit 1; }

# Unique slug against the freshly-cloned Atlas — it reflects what is actually
# published, so this catches collisions from other machines / async runs too.
BASE_SLUG="$(slugify "$TITLE")"
SLUG="$BASE_SLUG"; n=2
while [ -d "atlas-checkout/research/${DATE}-${SLUG}" ]; do
  SLUG="${BASE_SLUG}-${n}"; n=$((n + 1))
done
PARENT_DIR="$SCOUT_DIR/atlas-checkout/research/${DATE}-${SLUG}"
mkdir -p "$PARENT_DIR"

printf 'SCOUT_DIR=%s\n' "$SCOUT_DIR"
printf 'ATLAS_REPO=%s\n' "$ATLAS_REPO"
printf 'DATE=%s\n' "$DATE"
printf 'SLUG=%s\n' "$SLUG"
printf 'PARENT_DIR=%s\n' "$PARENT_DIR"
printf 'START_TS=%s\n' "$(date +%s)"

if [ -n "${SUB_TOPICS_TSV:-}" ]; then
  while IFS=$'\t' read -r ctitle cdepth; do
    [ -n "$ctitle" ] || continue
    cslug="$(slugify "$ctitle")"
    mkdir -p "$PARENT_DIR/$cslug"
    printf 'CHILD=%s\t%s\n' "$cslug" "$PARENT_DIR/$cslug"
  done <<< "$SUB_TOPICS_TSV"
fi
