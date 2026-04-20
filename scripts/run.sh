#!/usr/bin/env bash
# Entrypoint for a research run. Called by the GH Actions workflow.
# Required env: TOPIC, DEPTH, FORMAT. Optional: ATLAS_REPO.

set -euo pipefail

: "${TOPIC:?TOPIC is required}"
: "${DEPTH:=standard}"
: "${FORMAT:=auto}"
ATLAS_REPO="${ATLAS_REPO:-git@github.com:Laoujin/atlas.git}"

SCOUT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
cd "$SCOUT_DIR"

source "$SCOUT_DIR/scripts/slug.sh"
DATE="$(date +%F)"
SLUG="$(slugify "$TOPIC")"
if [ -z "$SLUG" ]; then
  echo "Error: topic produced empty slug." >&2
  exit 1
fi

ATLAS_DIR="$SCOUT_DIR/atlas-checkout"
rm -rf "$ATLAS_DIR"
git clone --depth=1 "$ATLAS_REPO" "$ATLAS_DIR"

# Collision guard against the Jekyll collection file (md or html) or its asset folder
FINAL_SLUG="$SLUG"
n=2
while ls "$ATLAS_DIR/_research/${DATE}-${FINAL_SLUG}".{md,html} 2>/dev/null | grep -q . \
   || [ -d "$ATLAS_DIR/assets/research/${DATE}-${FINAL_SLUG}" ]; do
  FINAL_SLUG="${SLUG}-${n}"
  n=$((n+1))
done

# Pre-create the per-research assets directory so Claude can drop images/data files in.
ASSETS_DIR="$ATLAS_DIR/assets/research/${DATE}-${FINAL_SLUG}"
mkdir -p "$ASSETS_DIR"

PROMPT="$(cat <<EOF
TOPIC: ${TOPIC}
DEPTH: ${DEPTH}
FORMAT: ${FORMAT}
DATE: ${DATE}
SLUG: ${FINAL_SLUG}
ATLAS_DIR: ${ATLAS_DIR}
ASSETS_DIR: ${ASSETS_DIR}

Use the Scout skill. Write the research artifact to ATLAS_DIR/_research/DATE-SLUG.md (for format=md) or ATLAS_DIR/_research/DATE-SLUG.html (for format=html); for format=auto pick the one that fits the topic. Save any supporting images or data files into ASSETS_DIR and reference them from the research body. Follow the skill's procedure. When done, print the final path.
EOF
)"

SKILL_CONTENT="$(cat "$SCOUT_DIR/skills/scout/SKILL.md")"

claude --dangerously-skip-permissions \
       --print \
       --append-system-prompt "$SKILL_CONTENT" \
       "$PROMPT"

TOPIC="$TOPIC" SLUG="$FINAL_SLUG" DATE="$DATE" ATLAS_REPO="$ATLAS_REPO" \
  bash "$SCOUT_DIR/scripts/publish.sh"
