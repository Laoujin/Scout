#!/usr/bin/env bash
# Install the Scout slash commands on this machine (typically your laptop).
#   /scout       — interactive research on your subscription; symlinked to this
#                  checkout so it self-locates and auto-updates on `git pull`.
#   /scout-async — opens a GitHub Issue for the runner; copied with your repo
#                  slug + Atlas URL baked in.
#
# Use this on the machine where you run Claude Code. install.sh already prompts
# for the same install on the host where it runs.
#
# Usage:
#   bash commands/install-scout-command.sh <owner>/<scout-repo> <atlas-url>
# Example:
#   bash commands/install-scout-command.sh alice/Scout https://alice.github.io/Atlas/

set -euo pipefail

if [[ $# -ne 2 ]]; then
  echo "Usage: $0 <owner>/<scout-repo> <atlas-url>" >&2
  echo "Example: $0 alice/Scout https://alice.github.io/Atlas/" >&2
  exit 2
fi

SCOUT_REPO="$1"
ATLAS_URL="$2"

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SCOUT_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
CMDDIR="$HOME/.claude/commands"
mkdir -p "$CMDDIR"

# /scout-async — copy + substitute (needs the repo slug, can't be a symlink).
ASYNC_SRC="$SCOUT_DIR/.claude/commands/scout-async.md"
[[ -f "$ASYNC_SRC" ]] || { echo "Error: $ASYNC_SRC not found" >&2; exit 1; }
sed -e "s|{{SCOUT_REPO}}|$SCOUT_REPO|g" \
    -e "s|{{ATLAS_URL}}|$ATLAS_URL|g" \
    "$ASYNC_SRC" > "$CMDDIR/scout-async.md"
echo "installed: $CMDDIR/scout-async.md → $SCOUT_REPO"

# /scout — symlink (self-locating); record the checkout path for ~/.scout/dir.
mkdir -p "$HOME/.scout"
printf '%s\n' "$SCOUT_DIR" > "$HOME/.scout/dir"
INTER_SRC="$SCOUT_DIR/.claude/commands/scout.md"
[[ -f "$INTER_SRC" ]] || { echo "Error: $INTER_SRC not found" >&2; exit 1; }
if ln -sf "$INTER_SRC" "$CMDDIR/scout.md" 2>/dev/null; then
  echo "linked:    $CMDDIR/scout.md → $INTER_SRC"
else
  cp "$INTER_SRC" "$CMDDIR/scout.md"   # filesystems without symlinks
  echo "copied:    $CMDDIR/scout.md (symlink unavailable; re-run after updates)"
fi
