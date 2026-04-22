#!/usr/bin/env bash
# Entrypoint for a research run. Called by the GH Actions workflow.
# Required env: TOPIC, DEPTH, FORMAT. Optional: ATLAS_REPO, RAW_TOPIC, ISSUE_NUMBER.

set -euo pipefail

: "${TOPIC:?TOPIC is required}"
: "${DEPTH:=standard}"
: "${FORMAT:=auto}"
RAW_TOPIC="${RAW_TOPIC:-$TOPIC}"
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

# Collision guard against the per-research folder
FINAL_SLUG="$SLUG"
n=2
while [ -d "$ATLAS_DIR/research/${DATE}-${FINAL_SLUG}" ]; do
  FINAL_SLUG="${SLUG}-${n}"
  n=$((n+1))
done

# Pre-create the per-research folder so Claude can drop index.{md,html} + assets inside.
RESEARCH_DIR="$ATLAS_DIR/research/${DATE}-${FINAL_SLUG}"
mkdir -p "$RESEARCH_DIR"

PROMPT="$(cat <<EOF
TOPIC: ${TOPIC}
RAW_TOPIC: ${RAW_TOPIC}
DEPTH: ${DEPTH}
FORMAT: ${FORMAT}
DATE: ${DATE}
SLUG: ${FINAL_SLUG}
RESEARCH_DIR: ${RESEARCH_DIR}
ISSUE_NUMBER: ${ISSUE_NUMBER:-}

Use the Scout skill. Write the research artifact to RESEARCH_DIR/index.md (for format=md) or RESEARCH_DIR/index.html (for format=html); for format=auto pick the one that fits the topic. Save any supporting images or data files into RESEARCH_DIR and reference them with plain relative paths (e.g. chart.png). Follow the skill's procedure. When done, print the final path.
EOF
)"

SKILL_CONTENT="$(cat "$SCOUT_DIR/skills/scout/SKILL.md")"

claude --dangerously-skip-permissions \
       --print \
       --append-system-prompt "$SKILL_CONTENT" \
       "$PROMPT"

# Ledger validation (standard and deep only — ceo may not produce a ledger).
LEDGER="$RESEARCH_DIR/citations.jsonl"
if [ -f "$LEDGER" ]; then
  ARTIFACT=""
  for CAND in "$RESEARCH_DIR/index.md" "$RESEARCH_DIR/index.html"; do
    [ -f "$CAND" ] && ARTIFACT="$CAND" && break
  done
  bash "$SCOUT_DIR/scripts/validate_ledger.sh" "$LEDGER" "$ARTIFACT"
elif [ "$DEPTH" != "ceo" ]; then
  echo "run.sh: expected citations.jsonl for depth=$DEPTH but none found" >&2
  exit 1
fi

TOPIC="$TOPIC" SLUG="$FINAL_SLUG" DATE="$DATE" ATLAS_REPO="$ATLAS_REPO" \
  ISSUE_NUMBER="${ISSUE_NUMBER:-}" \
  bash "$SCOUT_DIR/scripts/publish.sh"
