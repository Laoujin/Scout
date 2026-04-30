#!/usr/bin/env bash
# Dispatch script for the views workflow job. Triggered when a user flips the
# "Start creating the HTML pages" checkbox on a candidacy comment.
#
# Required env: GH_TOKEN, GH_REPO, ISSUE_NUMBER, BOT_COMMENT_BODY, BOT_COMMENT_ID
# Optional env: ATLAS_REPO (defaults to git@github.com:Laoujin/atlas.git)
#               GIT_AUTHOR_{NAME,EMAIL}, GIT_COMMITTER_{NAME,EMAIL}
#               SCOUT_TEST_KEEP_ATLAS=1  skip rm+clone (test fixture hook)
#
# Flow:
#   1. Parse comment, build dispatch set (ticked items minus existing views).
#   2. Reset the Start checkbox + append a "✓ dispatch fired at <ts>" line.
#   3. Reopen the issue if closed.
#   4. Clone Atlas. Fan out claude invocations in shell parallel.
#   5. Commit + push (lib-publish.sh's publish_path).
#   6. Post the results comment.
#   7. Close the issue if at least one new view shipped.

set -euo pipefail

: "${GH_TOKEN:?GH_TOKEN is required}"
: "${GH_REPO:?GH_REPO is required}"
: "${ISSUE_NUMBER:?ISSUE_NUMBER is required}"
: "${BOT_COMMENT_BODY:?BOT_COMMENT_BODY is required}"
: "${BOT_COMMENT_ID:?BOT_COMMENT_ID is required}"

SCOUT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
ATLAS_REPO="${ATLAS_REPO:-git@github.com:Laoujin/atlas.git}"

# shellcheck source=scripts/lib-views-parse.sh
source "$SCOUT_DIR/scripts/lib-views-parse.sh"
# shellcheck source=scripts/lib-publish.sh
source "$SCOUT_DIR/scripts/lib-publish.sh"

# Step 1: parse the bot comment.
parse_view_targets "$BOT_COMMENT_BODY"
parse_view_ticks "$BOT_COMMENT_BODY"
parse_views_start "$BOT_COMMENT_BODY"

if [ "$VIEWS_START" != "true" ]; then
  echo "[views-dispatch] Start checkbox not ticked; nothing to do" >&2
  exit 0
fi
if [ -z "$VIEW_TARGETS_JSON" ]; then
  echo "[views-dispatch] no scout-view-targets block found; aborting" >&2
  exit 1
fi

# Step 2: edit the comment — reset Start, append dispatch-fired line.
TS="$(date -u +%FT%TZ)"
NEW_BODY="$(printf '%s' "$BOT_COMMENT_BODY" \
  | sed -E 's/- \[[xX]\] \*\*Start creating the HTML pages\*\*/- [ ] **Start creating the HTML pages**/')"
NEW_BODY+=$'\n\n> ✓ dispatch fired at '"$TS"
gh api -X PATCH "/repos/${GH_REPO}/issues/comments/${BOT_COMMENT_ID}" -f body="$NEW_BODY" >/dev/null \
  || echo "[views-dispatch] failed to PATCH comment $BOT_COMMENT_ID (continuing)" >&2

# Step 3: reopen issue if closed.
ISSUE_STATE="$(gh issue view "$ISSUE_NUMBER" --repo "$GH_REPO" --json state --jq .state || echo OPEN)"
if [ "$ISSUE_STATE" = "CLOSED" ]; then
  gh issue reopen "$ISSUE_NUMBER" --repo "$GH_REPO" \
    || echo "[views-dispatch] failed to reopen issue (continuing)" >&2
fi

# Step 4a: clone Atlas.
# SCOUT_TEST_KEEP_ATLAS=1 skips wipe+clone so test fixtures survive.
ATLAS_DIR="$SCOUT_DIR/atlas-checkout"
if [ "${SCOUT_TEST_KEEP_ATLAS:-0}" != "1" ]; then
  rm -rf "$ATLAS_DIR"
  git clone --filter=blob:none --depth=1 "$ATLAS_REPO" "$ATLAS_DIR"
fi

# Step 4b: build dispatch set.
declare -a DISPATCH_ITEMS=()  # entries: "slug|path|view_name|title_suffix|vibe_hint|title"
declare -a SKIPPED_ITEMS=()   # entries: "slug|reason"
declare -a UNTICKED_ITEMS=()  # entries: "slug" (informational, not posted)

ITEMS_COUNT=$(printf '%s' "$VIEW_TARGETS_JSON" | jq '.items | length')
for i in $(seq 0 $((ITEMS_COUNT - 1))); do
  slug=$(printf '%s' "$VIEW_TARGETS_JSON" | jq -r ".items[$i].slug")
  path=$(printf '%s' "$VIEW_TARGETS_JSON" | jq -r ".items[$i].path")
  view_name=$(printf '%s' "$VIEW_TARGETS_JSON" | jq -r ".items[$i].view_name // empty")
  title_suffix=$(printf '%s' "$VIEW_TARGETS_JSON" | jq -r ".items[$i].title_suffix // empty")
  vibe_hint=$(printf '%s' "$VIEW_TARGETS_JSON" | jq -r ".items[$i].vibe_hint // empty")

  if [ "${VIEW_TICKS[$slug]:-false}" != "true" ]; then
    UNTICKED_ITEMS+=("$slug")
    continue
  fi

  # Default view_name if missing (manual tick on un-judged row).
  if [ -z "$view_name" ] || [ "$view_name" = "null" ]; then
    view_name="custom"
    title_suffix="Custom"
    vibe_hint=""
  fi

  view_file="$ATLAS_DIR/$path/views/${view_name}.html"
  if [ -f "$view_file" ]; then
    SKIPPED_ITEMS+=("$slug|view already exists")
    continue
  fi

  # Title approximated from index.{md,html} frontmatter; fall back to slug.
  title="$slug"
  for ext in md html; do
    if [ -f "$ATLAS_DIR/$path/index.$ext" ]; then
      t="$(awk '/^---[[:space:]]*$/{n++; next} n==1 && /^title:/{sub(/^title:[[:space:]]*/,""); print; exit}' "$ATLAS_DIR/$path/index.$ext")"
      [ -n "$t" ] && title="$t"
      break
    fi
  done

  vibe_hint="${vibe_hint//|/}"
  title="${title//|/}"
  DISPATCH_ITEMS+=("$slug|$path|$view_name|$title_suffix|$vibe_hint|$title")
done

if [ "${#DISPATCH_ITEMS[@]}" -eq 0 ] && [ "${#SKIPPED_ITEMS[@]}" -eq 0 ]; then
  gh issue comment "$ISSUE_NUMBER" --repo "$GH_REPO" --body \
    "Dispatch fired but no rows ticked. Tick at least one row before flipping the Start checkbox."
  exit 0
fi

# Step 4c: fan out in shell parallel.
SKILL_CONTENT="$(cat "$SCOUT_DIR/skills/scout-view-author/SKILL.md")"
LOG_DIR="$(mktemp -d)"
declare -a PIDS=()
declare -a PID_SLUGS=()

for entry in "${DISPATCH_ITEMS[@]}"; do
  IFS='|' read -r slug path view_name title_suffix vibe_hint title <<< "$entry"
  RESEARCH_DIR_ABS="$ATLAS_DIR/$path"
  CANONICAL=""
  for ext in md html; do
    [ -f "$RESEARCH_DIR_ABS/index.$ext" ] && CANONICAL="$RESEARCH_DIR_ABS/index.$ext" && break
  done
  if [ -z "$CANONICAL" ]; then
    SKIPPED_ITEMS+=("$slug|canonical missing")
    continue
  fi
  mkdir -p "$RESEARCH_DIR_ABS/views"

  PROMPT="$(cat <<EOF
CANONICAL_PATH:  ${CANONICAL}
RESEARCH_DIR:    ${RESEARCH_DIR_ABS}
VIEW_NAME:       ${view_name}
TITLE_SUFFIX:    ${title_suffix}
VIBE_HINT:       ${vibe_hint}

Use the scout-view-author skill. Author the view at RESEARCH_DIR/views/VIEW_NAME.html.
EOF
)"

  (
    claude --dangerously-skip-permissions \
           --print \
           --output-format json \
           --append-system-prompt "$SKILL_CONTENT" \
           "$PROMPT" > "$LOG_DIR/${slug}.result.json" 2> "$LOG_DIR/${slug}.stderr.log"
  ) &
  PIDS+=("$!")
  PID_SLUGS+=("$slug")
done

# Wait, collecting per-slug exit codes.
declare -a SUCCESS_ITEMS=()  # entries: "slug|view_name|title_suffix|title"
declare -a FAILED_ITEMS=()   # entries: "slug|tail-of-stderr"
for j in "${!PIDS[@]}"; do
  pid="${PIDS[$j]}"
  slug="${PID_SLUGS[$j]}"
  rc=0; wait "$pid" || rc=$?
  # Find the dispatch entry to recover view_name, title_suffix, title.
  for entry in "${DISPATCH_ITEMS[@]}"; do
    IFS='|' read -r s path_e vn ts_e _ tt <<< "$entry"
    if [ "$s" = "$slug" ]; then
      view_file="$ATLAS_DIR/${path_e}/views/${vn}.html"
      if [ "$rc" -eq 0 ] && [ -f "$view_file" ]; then
        SUCCESS_ITEMS+=("$slug|$vn|$ts_e|$tt")
      else
        tail_msg="$(tail -3 "$LOG_DIR/${slug}.stderr.log" 2>/dev/null | tr '\n' '; ' | sed 's/; $//')"
        [ -z "$tail_msg" ] && tail_msg="claude exit $rc"
        FAILED_ITEMS+=("$slug|$tail_msg")
      fi
      break
    fi
  done
done

# Step 5: commit + push if any successes.
SHIPPED=0
if [ "${#SUCCESS_ITEMS[@]}" -gt 0 ]; then
  cd "$ATLAS_DIR"
  DATE_TAG="$(date +%F)"
  SLUG_LIST="$(printf '%s\n' "${SUCCESS_ITEMS[@]}" | cut -d'|' -f1 | tr '\n' ',' | sed 's/,$//')"
  rc=0; publish_path "views: ${DATE_TAG} ${SLUG_LIST}" "." "scout-views/${DATE_TAG}-${ISSUE_NUMBER}" || rc=$?
  if [ "$rc" -eq 0 ]; then
    SHIPPED=1
  else
    local_reason="atlas push failed"
    [ "$rc" -eq 2 ] && local_reason="nothing staged"
    for entry in "${SUCCESS_ITEMS[@]}"; do
      IFS='|' read -r slug _ _ _ <<< "$entry"
      FAILED_ITEMS+=("$slug|$local_reason")
    done
    SUCCESS_ITEMS=()
  fi
fi

# Step 6: post results comment.
ATLAS_BASE_URL=""
case "$ATLAS_REPO" in
  git@*:*)
    atlas_slug="${ATLAS_REPO#*:}"; atlas_slug="${atlas_slug%.git}"
    owner="${atlas_slug%%/*}"; repo="${atlas_slug##*/}"
    ATLAS_BASE_URL="https://${owner,,}.github.io/${repo}" ;;
  https://github.com/*)
    atlas_slug="${ATLAS_REPO#https://github.com/}"; atlas_slug="${atlas_slug%.git}"
    owner="${atlas_slug%%/*}"; repo="${atlas_slug##*/}"
    ATLAS_BASE_URL="https://${owner,,}.github.io/${repo}" ;;
esac

LINES=()
for entry in "${SUCCESS_ITEMS[@]}"; do
  IFS='|' read -r slug vn ts_e tt <<< "$entry"
  path=$(printf '%s' "$VIEW_TARGETS_JSON" | jq -r ".items[] | select(.slug==\"$slug\") | .path")
  url_path="${path#research/}"
  LINES+=("- ✓ [${tt} — ${ts_e}](${ATLAS_BASE_URL}/research/${url_path}/views/${vn}.html)")
done
for entry in "${FAILED_ITEMS[@]}"; do
  IFS='|' read -r slug reason <<< "$entry"
  LINES+=("- ⚠ ${slug} — failed: ${reason}")
done
for entry in "${SKIPPED_ITEMS[@]}"; do
  IFS='|' read -r slug reason <<< "$entry"
  LINES+=("- ⏭ ${slug} — skipped (${reason})")
done

if [ "${#LINES[@]}" -gt 0 ]; then
  RESULT_BODY="HTML views processed:"$'\n\n'"$(printf '%s\n' "${LINES[@]}")"
  gh issue comment "$ISSUE_NUMBER" --repo "$GH_REPO" --body "$RESULT_BODY"
fi

# Step 7: close issue if at least one view shipped.
if [ "$SHIPPED" -eq 1 ] && [ "${#SUCCESS_ITEMS[@]}" -gt 0 ]; then
  gh issue close "$ISSUE_NUMBER" --repo "$GH_REPO" --reason completed \
    || echo "[views-dispatch] gh issue close failed (non-fatal)" >&2
fi

rm -rf "$LOG_DIR"
