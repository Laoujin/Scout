#!/usr/bin/env bash
# Resolve / validate / persist the local Atlas checkout and worktree-home paths
# for the interactive /scout flow. All persisted paths are absolute. The config
# dir is $SCOUT_CONFIG_DIR (default ~/.scout) so tests can redirect it.
set -uo pipefail
CFG_DIR="${SCOUT_CONFIG_DIR:-$HOME/.scout}"
ATLAS_PTR="$CFG_DIR/atlas"
WT_PTR="$CFG_DIR/worktrees-dir"

_abs() { ( cd "$1" 2>/dev/null && pwd ); }

# Valid = a git working tree that has an 'origin' remote (the publish target).
_valid_atlas() {
  local d="$1"
  [ -n "$d" ] || return 1
  git -C "$d" rev-parse --is-inside-work-tree >/dev/null 2>&1 || return 1
  git -C "$d" remote get-url origin >/dev/null 2>&1 || return 1
}

cmd_resolve_atlas() {
  [ -f "$ATLAS_PTR" ] || return 3
  local d; d="$(cat "$ATLAS_PTR" 2>/dev/null)"
  _valid_atlas "$d" || return 3
  printf '%s\n' "$d"
}

cmd_save_atlas() {
  local d; d="$(_abs "${1:-}")" || true
  [ -n "$d" ] || { echo "atlas-config: path not found: ${1:-}" >&2; return 2; }
  _valid_atlas "$d" || { echo "atlas-config: not a git checkout with an 'origin' remote: $d" >&2; return 2; }
  mkdir -p "$CFG_DIR"; printf '%s\n' "$d" > "$ATLAS_PTR"; printf '%s\n' "$d"
}

cmd_detect_sibling() {
  local s; s="$(_abs "${1:?usage: detect-sibling <scout-dir>}/../atlas")" || return 1
  _valid_atlas "$s" || return 1
  printf '%s\n' "$s"
}

cmd_resolve_worktrees() {
  [ -f "$WT_PTR" ] || return 3
  local d; d="$(cat "$WT_PTR" 2>/dev/null)"; [ -n "$d" ] || return 3
  printf '%s\n' "$d"
}

cmd_save_worktrees() {
  local p="${1:?usage: save-worktrees <path> [atlas-dir-if-inside]}" inside="${2:-}"
  mkdir -p "$p"; local d; d="$(_abs "$p")"
  mkdir -p "$CFG_DIR"; printf '%s\n' "$d" > "$WT_PTR"
  if [ -n "$inside" ]; then
    local ex="$inside/.git/info/exclude"
    mkdir -p "$inside/.git/info"
    grep -qxF 'worktrees/' "$ex" 2>/dev/null || printf 'worktrees/\n' >> "$ex"
  fi
  printf '%s\n' "$d"
}

case "${1:-}" in
  resolve-atlas)     shift; cmd_resolve_atlas "$@" ;;
  save-atlas)        shift; cmd_save_atlas "$@" ;;
  detect-sibling)    shift; cmd_detect_sibling "$@" ;;
  resolve-worktrees) shift; cmd_resolve_worktrees "$@" ;;
  save-worktrees)    shift; cmd_save_worktrees "$@" ;;
  *) echo "usage: atlas-config.sh {resolve-atlas | save-atlas <path> | detect-sibling <scout-dir> | resolve-worktrees | save-worktrees <path> [atlas-dir]}" >&2; exit 2 ;;
esac
