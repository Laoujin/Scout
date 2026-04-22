#!/usr/bin/env bash
# Entrypoint for a research run. Called by the GH Actions workflow.
# Required env: TOPIC, DEPTH, FORMAT. Optional: ATLAS_REPO, RAW_TOPIC, ISSUE_NUMBER.

set -euo pipefail

: "${TOPIC:?TOPIC is required}"
: "${DEPTH:=standard}"
: "${FORMAT:=auto}"

# Normalize display aliases (from workflow_dispatch or direct calls) to internal codes.
case "$DEPTH" in
  recon)      DEPTH=ceo ;;
  survey)     DEPTH=standard ;;
  expedition) DEPTH=deep ;;
esac
RAW_TOPIC="${RAW_TOPIC:-$TOPIC}"
ATLAS_REPO="${ATLAS_REPO:-git@github.com:Laoujin/atlas.git}"

SCOUT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
cd "$SCOUT_DIR"

# Capture stderr for post-mortem. The ERR trap tails this file into an issue
# comment on hard failure so the user sees why the run died without opening
# workflow logs.
RUN_LOG="$(mktemp -t scout-run.XXXXXX.log)"
exec 2> >(tee -a "$RUN_LOG" >&2)

# Non-blocking failures (cost injection, etc.) append a line here. publish.sh
# reads it: if non-empty, post a soft-fail comment and keep the issue open.
SOFT_FAIL_LOG="$(mktemp -t scout-softfail.XXXXXX.log)"
export SOFT_FAIL_LOG

# On any unhandled error, try to surface the failure on the triggering issue
# before exiting. `|| true` on gh so a broken token doesn't loop the trap.
on_error() {
  local code=$?
  local cmd="${BASH_COMMAND:-unknown}"
  if [ -n "${ISSUE_NUMBER:-}" ] && [ -n "${GH_TOKEN:-}" ] && [ -n "${GH_REPO:-}" ]; then
    local tail_log
    tail_log="$(tail -n 30 "$RUN_LOG" 2>/dev/null | sed 's/`/\\`/g')"
    gh issue comment "$ISSUE_NUMBER" --repo "$GH_REPO" --body "$(printf 'Scout run failed (exit %s) at: `%s`\n\n<details><summary>Last 30 lines of stderr</summary>\n\n```\n%s\n```\n</details>' "$code" "$cmd" "$tail_log")" || true
  fi
  exit "$code"
}
trap on_error ERR

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

RESULT_JSON="$RESEARCH_DIR/.scout-result.json"
claude --dangerously-skip-permissions \
       --print \
       --output-format json \
       --append-system-prompt "$SKILL_CONTENT" \
       "$PROMPT" > "$RESULT_JSON"

# Echo the human-readable result to stdout so workflow logs keep the shape
# they had before --output-format json was added.
jq -r .result "$RESULT_JSON"

# Ledger validation (standard and deep only — ceo may not produce a ledger).
LEDGER="$RESEARCH_DIR/citations.jsonl"
ARTIFACT=""
for CAND in "$RESEARCH_DIR/index.md" "$RESEARCH_DIR/index.html"; do
  [ -f "$CAND" ] && ARTIFACT="$CAND" && break
done
if [ -f "$LEDGER" ]; then
  bash "$SCOUT_DIR/scripts/validate_ledger.sh" "$LEDGER" "$ARTIFACT"
elif [ "$DEPTH" != "ceo" ]; then
  echo "run.sh: expected citations.jsonl for depth=$DEPTH but none found" >&2
  exit 1
fi

# Inject cost/duration into the artifact frontmatter. Any failure here is
# non-blocking: log to SOFT_FAIL_LOG so publish.sh surfaces it without losing
# the research.
inject_claude_cost() {
  [ -n "$ARTIFACT" ] || { echo "no artifact file found" >&2; return 1; }
  local cost_raw dur_ms cost_2dp dur_sec
  cost_raw=$(jq -r '.total_cost_usd // empty' "$RESULT_JSON") || return 1
  dur_ms=$(jq -r '.duration_ms // empty' "$RESULT_JSON") || return 1
  [ -n "$cost_raw" ] && [ "$cost_raw" != "null" ] || { echo "total_cost_usd missing from result JSON" >&2; return 1; }
  [ -n "$dur_ms" ] && [ "$dur_ms" != "null" ] || { echo "duration_ms missing from result JSON" >&2; return 1; }
  cost_2dp=$(printf '%.2f' "$cost_raw") || return 1
  dur_sec=$(awk -v ms="$dur_ms" 'BEGIN{printf "%d", (ms/1000)+0.5}') || return 1
  bash "$SCOUT_DIR/scripts/inject_cost.sh" "$ARTIFACT" "$cost_2dp" "$dur_sec"
}
if ! inject_claude_cost 2>>"$SOFT_FAIL_LOG"; then
  echo "cost injection failed — see $SOFT_FAIL_LOG" | tee -a "$SOFT_FAIL_LOG" >&2
fi

rm -f "$RESULT_JSON"

TOPIC="$TOPIC" SLUG="$FINAL_SLUG" DATE="$DATE" ATLAS_REPO="$ATLAS_REPO" \
  ISSUE_NUMBER="${ISSUE_NUMBER:-}" \
  bash "$SCOUT_DIR/scripts/publish.sh"
