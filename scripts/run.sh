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

# Structured failure reason, written synchronously the moment a failure is
# known. The decompose parent reads this file instead of scraping the child's
# stderr tail (which races the async `tee` above and was the source of the
# uninformative "child run.sh exit 1" annotations). Path is finalised once
# RESEARCH_DIR is known; the trap guards on it being set.
SCOUT_ERROR_FILE=""

# Turn a Claude result JSON's error fields into one human-readable line.
scout_classify_error() {
  local subtype="$1" stop="$2" apierr="$3" msg="$4"
  if printf '%s %s %s %s' "$subtype" "$stop" "$apierr" "$msg" \
       | grep -qiE 'usage limit|rate.?limit|quota|overloaded|429|529|too many requests'; then
    echo "Claude hit a usage/rate limit — likely ran out of tokens${apierr:+ (api status $apierr)}. Re-run once the limit resets."
  elif [ "$subtype" = "error_max_turns" ]; then
    echo "Claude reached the max-turns limit before finishing${msg:+: $msg}"
  elif [ -n "$msg" ]; then
    echo "Claude returned an error${subtype:+ (subtype=$subtype)}: $msg"
  else
    echo "Claude returned an error${subtype:+ (subtype=$subtype)}${apierr:+ [api=$apierr]}"
  fi
}

# On any unhandled error, try to surface the failure on the triggering issue
# before exiting. `|| true` on gh so a broken token doesn't loop the trap.
on_error() {
  local code=$?
  local cmd="${BASH_COMMAND:-unknown}"
  local reason
  if [ -n "$SCOUT_ERROR_FILE" ] && [ -s "$SCOUT_ERROR_FILE" ]; then
    reason="$(cat "$SCOUT_ERROR_FILE")"
  else
    # Persist the live stderr tail so the decompose parent has a real reason
    # even though the `tee` above may not have flushed to RUN_LOG yet.
    reason="$(tail -n 5 "$RUN_LOG" 2>/dev/null | grep -v '^[[:space:]]*$' | tail -n 3 | tr '\n' ' ')"
    reason="exit $code at \`$cmd\`${reason:+ — $reason}"
    [ -n "$SCOUT_ERROR_FILE" ] && printf '%s\n' "$reason" > "$SCOUT_ERROR_FILE" 2>/dev/null || true
  fi
  # Decompose children must not comment on the parent issue — the parent
  # orchestrator writes a placeholder index.md and surfaces failure via the
  # final summary comment (reading .scout-error for the reason).
  if [ "${SCOUT_DECOMPOSE_CHILD:-0}" = "1" ]; then
    exit "$code"
  fi
  if [ -n "${ISSUE_NUMBER:-}" ] && [ -n "${GH_TOKEN:-}" ] && [ -n "${GH_REPO:-}" ]; then
    local tail_log
    tail_log="$(tail -n 30 "$RUN_LOG" 2>/dev/null | sed 's/`/\\`/g')"
    gh issue comment "$ISSUE_NUMBER" --repo "$GH_REPO" --body "$(printf 'Scout run failed: %s\n\n<details><summary>Last 30 lines of stderr</summary>\n\n```\n%s\n```\n</details>' "$reason" "$tail_log")" || true
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

# Two modes:
#  - Standalone: clone Atlas, derive a unique slug, write to atlas-checkout.
#  - Decompose-child: parent (run-decompose.sh) has already cloned Atlas and
#    pre-chosen RESEARCH_DIR inside the parent expedition tree. Children must
#    not re-clone (would wipe siblings) or relocate to a top-level folder.
if [ -n "${RESEARCH_DIR:-}" ]; then
  FINAL_SLUG="$SLUG"
else
  ATLAS_DIR="$SCOUT_DIR/atlas-checkout"
  rm -rf "$ATLAS_DIR"
  git clone --filter=blob:none --depth=1 "$ATLAS_REPO" "$ATLAS_DIR"

  FINAL_SLUG="$SLUG"
  n=2
  while [ -d "$ATLAS_DIR/research/${DATE}-${FINAL_SLUG}" ]; do
    FINAL_SLUG="${SLUG}-${n}"
    n=$((n+1))
  done

  RESEARCH_DIR="$ATLAS_DIR/research/${DATE}-${FINAL_SLUG}"
fi
mkdir -p "$RESEARCH_DIR"
SCOUT_ERROR_FILE="$RESEARCH_DIR/.scout-error"
rm -f "$SCOUT_ERROR_FILE"

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

ARTIFACT=""
for CAND in "$RESEARCH_DIR/index.md" "$RESEARCH_DIR/index.html"; do
  [ -f "$CAND" ] && ARTIFACT="$CAND" && break
done

# Claude reports a failed run via is_error:true while the CLI still exits 0.
# Detect it here, record a clear reason synchronously, and decide salvage vs
# hard-fail. Without this run.sh would publish an empty/partial page and the
# decompose parent would only ever see a generic "exit 1".
if [ "$(jq -r '.is_error // false' "$RESULT_JSON" 2>/dev/null || echo false)" = "true" ]; then
  err_subtype="$(jq -r '.subtype // ""'         "$RESULT_JSON" 2>/dev/null || true)"
  err_stop="$(jq    -r '.stop_reason // ""'     "$RESULT_JSON" 2>/dev/null || true)"
  err_api="$(jq     -r '.api_error_status // ""' "$RESULT_JSON" 2>/dev/null || true)"
  err_msg="$(jq     -r '.result // ""'          "$RESULT_JSON" 2>/dev/null | tr '\n' ' ' | cut -c1-300 || true)"
  REASON="$(scout_classify_error "$err_subtype" "$err_stop" "$err_api" "$err_msg")"
  printf '%s\n' "$REASON" > "$SCOUT_ERROR_FILE"
  echo "scout: $REASON" >&2

  if [ "${SCOUT_DECOMPOSE_CHILD:-0}" = "1" ]; then
    # The parent inspects rc + .scout-error: it salvages a real artifact as
    # error_with_content, or writes a failed placeholder with this reason.
    exit 3
  fi
  if [ -z "$ARTIFACT" ]; then
    # Single-pass with nothing to keep — fail hard with the clear reason.
    if [ -n "${ISSUE_NUMBER:-}" ] && [ -n "${GH_TOKEN:-}" ] && [ -n "${GH_REPO:-}" ]; then
      gh issue comment "$ISSUE_NUMBER" --repo "$GH_REPO" --body "Scout run failed: $REASON" || true
    fi
    exit 3
  fi
  # Single-pass with a partial artifact — publish it but flag the degradation.
  echo "$REASON" >> "$SOFT_FAIL_LOG"
fi

# Ledger validation (standard and deep only — ceo may not produce a ledger).
LEDGER="$RESEARCH_DIR/citations.jsonl"
if [ -f "$LEDGER" ]; then
  bash "$SCOUT_DIR/scripts/validate_ledger.sh" "$LEDGER" "$ARTIFACT"
elif [ "$DEPTH" != "ceo" ]; then
  echo "run.sh: warning: citations.jsonl not found for depth=$DEPTH (non-blocking)" >&2
fi

# Frontmatter YAML validation — catch broken quoting before publish.
if [ -n "$ARTIFACT" ]; then
  bash "$SCOUT_DIR/scripts/validate_frontmatter.sh" "$ARTIFACT"
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

# Keep .scout-result.json — it ships with the published research.

# --- Title-based slug rename -------------------------------------------------
# After the artifact is written, derive a cleaner slug from the frontmatter
# title instead of the raw TOPIC. Decompose children skip this — the parent
# orchestrator tracks them by their original slug.
if [ "${SCOUT_DECOMPOSE_CHILD:-0}" != "1" ] && [ -n "$ARTIFACT" ]; then
  FM_TITLE="$(awk '/^---[[:space:]]*$/{n++; next} n==1 && /^title:/{sub(/^title:[[:space:]]*/,""); print; exit}' "$ARTIFACT")"
  if [ -n "$FM_TITLE" ]; then
    TITLE_SLUG="$(slugify "$FM_TITLE")"
    if [ -n "$TITLE_SLUG" ] && [ "$TITLE_SLUG" != "$FINAL_SLUG" ]; then
      RESEARCH_PARENT="$(dirname "$RESEARCH_DIR")"
      NEW_DIR="$RESEARCH_PARENT/${DATE}-${TITLE_SLUG}"
      if [ -d "$NEW_DIR" ]; then
        n=2
        while [ -d "$RESEARCH_PARENT/${DATE}-${TITLE_SLUG}-${n}" ]; do
          n=$((n+1))
        done
        TITLE_SLUG="${TITLE_SLUG}-${n}"
        NEW_DIR="$RESEARCH_PARENT/${DATE}-${TITLE_SLUG}"
      fi
      mv "$RESEARCH_DIR" "$NEW_DIR"
      RESEARCH_DIR="$NEW_DIR"
      FINAL_SLUG="$TITLE_SLUG"
      echo "Renamed research dir to: ${DATE}-${FINAL_SLUG}" >&2
    fi
  fi
fi

# View-candidacy judgement — writes RESEARCH_DIR/.view-candidacy.json (post-rename).
if [ "${SCOUT_DECOMPOSE_CHILD:-0}" != "1" ]; then
  RESEARCH_DIR="$RESEARCH_DIR" SCOUT_DIR="$SCOUT_DIR" \
    bash "$SCOUT_DIR/scripts/view-candidacy.sh" \
    || echo "run.sh: view-candidacy.sh failed (non-blocking)" >> "$SOFT_FAIL_LOG"
fi

# Decompose children defer publishing to the parent orchestrator so the entire
# expedition lands as one commit / one Atlas card.
if [ "${SCOUT_NO_PUBLISH:-0}" = "1" ]; then
  exit 0
fi

# Add to an existing Atlas series if the sharpen step suggested one and the
# user left it ticked. Fail-soft: never blocks publishing.
if [ -n "${SERIES_SLUG:-}" ] && [ -n "${ATLAS_DIR:-}" ]; then
  SOFT_FAIL_LOG="$SOFT_FAIL_LOG" \
    bash "$SCOUT_DIR/scripts/add-to-series.sh" \
      "$ATLAS_DIR/_data/series.yml" \
      "${DATE}-${FINAL_SLUG}" \
      "$SERIES_SLUG" "${SERIES_GROUP:-}" \
    || echo "run.sh: add-to-series.sh failed (non-blocking)" >> "$SOFT_FAIL_LOG"
fi

TOPIC="$TOPIC" SLUG="$FINAL_SLUG" DATE="$DATE" ATLAS_REPO="$ATLAS_REPO" \
  ISSUE_NUMBER="${ISSUE_NUMBER:-}" RESEARCH_DIR="$RESEARCH_DIR" \
  bash "$SCOUT_DIR/scripts/publish.sh"
