#!/usr/bin/env bash
# Install the /scout Claude Code slash command on this machine.
# Bakes your Scout repo + Atlas URL into ~/.claude/commands/scout.md.
#
# Use this on the machine where you run Claude Code (typically your laptop) —
# install.sh already prompts for the same install on the host where it runs.
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
SRC="$SCRIPT_DIR/scout.md"
DEST="$HOME/.claude/commands/scout.md"

[[ -f "$SRC" ]] || { echo "Error: template not found at $SRC" >&2; exit 1; }

if [[ -e "$DEST" ]]; then
  read -rp "$DEST exists. Overwrite? [y/N]: " _ow
  [[ "${_ow,,}" =~ ^(y|yes)$ ]] || { echo "skipped"; exit 0; }
fi

mkdir -p "$(dirname "$DEST")"
sed -e "s|{{SCOUT_REPO}}|$SCOUT_REPO|g" \
    -e "s|{{ATLAS_URL}}|$ATLAS_URL|g" \
    "$SRC" > "$DEST"

echo "installed: $DEST → $SCOUT_REPO"
