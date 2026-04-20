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

# Collision guard against the Jekyll collection file (md or html)
FINAL_SLUG="$SLUG"
n=2
while ls "$ATLAS_DIR/_research/${DATE}-${FINAL_SLUG}".{md,html} 2>/dev/null | grep -q .; do
  FINAL_SLUG="${SLUG}-${n}"
  n=$((n+1))
done

PROMPT="$(cat <<EOF
TOPIC: ${TOPIC}
DEPTH: ${DEPTH}
FORMAT: ${FORMAT}
DATE: ${DATE}
SLUG: ${FINAL_SLUG}
ATLAS_DIR: ${ATLAS_DIR}

Use the Scout skill. Perform the research and write the artifact to ATLAS_DIR/_research/DATE-SLUG.md (for format=md) or ATLAS_DIR/_research/DATE-SLUG.html (for format=html). For format=auto pick the one that fits the topic. Follow the skill's procedure. When done, print the final path.
EOF
)"

SKILL_CONTENT="$(cat "$SCOUT_DIR/skills/scout/SKILL.md")"

claude --dangerously-skip-permissions \
       --print \
       --append-system-prompt "$SKILL_CONTENT" \
       "$PROMPT"

TOPIC="$TOPIC" SLUG="$FINAL_SLUG" DATE="$DATE" ATLAS_REPO="$ATLAS_REPO" \
  bash "$SCOUT_DIR/scripts/publish.sh"
