#!/usr/bin/env bash
# Per-run setup for the interactive (subscription) Scout flow. Given a registered
# Atlas checkout (ATLAS_DIR) and a worktree home (WT_HOME), fetch origin/main and
# add an isolated git worktree on a fresh scout/<date>-<slug> branch. No clone, no
# rm -rf: parallel runs get independent worktrees and never clobber each other.
set -euo pipefail

TITLE="${1:?usage: local-setup.sh <title>}"
ATLAS_DIR="${ATLAS_DIR:?ATLAS_DIR is required (registered Atlas checkout; see atlas-config.sh)}"
WT_HOME="${WT_HOME:?WT_HOME is required (worktree home dir; see atlas-config.sh)}"
DATE="${DATE:-$(date +%F)}"

# Resolve SCOUT_DIR for slug.sh: explicit pointer, else walk up to the playbook.
if [ -f "$HOME/.scout/dir" ]; then
  SCOUT_DIR="$(cat "$HOME/.scout/dir")"
else
  d="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
  while [ "$d" != "/" ] && [ ! -f "$d/skills/scout-research/SKILL.md" ]; do d="$(dirname "$d")"; done
  [ -f "$d/skills/scout-research/SKILL.md" ] || { echo "Error: cannot locate SCOUT_DIR" >&2; exit 1; }
  SCOUT_DIR="$d"
fi
# shellcheck source=scripts/slug.sh
source "$SCOUT_DIR/scripts/slug.sh"

git -C "$ATLAS_DIR" worktree prune >/dev/null 2>&1 || true
err="$(git -C "$ATLAS_DIR" fetch origin main 2>&1)" || {
  echo "Error: failed to fetch origin/main in $ATLAS_DIR: $err" >&2; exit 1; }

# Unique slug vs what's published (origin/main), live branches, and live worktrees.
BASE_SLUG="$(slugify "$TITLE")"
SLUG="$BASE_SLUG"; n=2
while git -C "$ATLAS_DIR" cat-file -e "origin/main:research/${DATE}-${SLUG}" 2>/dev/null \
   || git -C "$ATLAS_DIR" show-ref --verify --quiet "refs/heads/scout/${DATE}-${SLUG}" \
   || [ -e "$WT_HOME/${DATE}-${SLUG}" ]; do
  SLUG="${BASE_SLUG}-${n}"; n=$((n + 1))
done

BRANCH="scout/${DATE}-${SLUG}"
WORKTREE="$WT_HOME/${DATE}-${SLUG}"
mkdir -p "$WT_HOME"
# worktree add is the atomic backstop for the slug race: if a concurrent run
# grabbed the same branch between the uniqueness check and here, this fails loudly.
err="$(git -C "$ATLAS_DIR" worktree add -b "$BRANCH" "$WORKTREE" origin/main 2>&1)" || {
  echo "Error: git worktree add failed for $WORKTREE: $err" >&2; exit 1; }

PARENT_DIR="$WORKTREE/research/${DATE}-${SLUG}"
mkdir -p "$PARENT_DIR"

printf 'ATLAS_DIR=%s\n' "$ATLAS_DIR"
printf 'WORKTREE=%s\n' "$WORKTREE"
printf 'BRANCH=%s\n' "$BRANCH"
printf 'DATE=%s\n' "$DATE"
printf 'SLUG=%s\n' "$SLUG"
printf 'PARENT_DIR=%s\n' "$PARENT_DIR"
printf 'START_TS=%s\n' "$(date +%s)"

if [ -n "${SUB_TOPICS_TSV:-}" ]; then
  while IFS=$'\t' read -r ctitle _; do
    [ -n "$ctitle" ] || continue
    cslug="$(slugify "$ctitle")"
    mkdir -p "$PARENT_DIR/$cslug"
    printf 'CHILD=%s\t%s\n' "$cslug" "$PARENT_DIR/$cslug"
  done <<< "$SUB_TOPICS_TSV"
fi
