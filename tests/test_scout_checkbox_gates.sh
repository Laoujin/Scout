#!/usr/bin/env bash
# Guards /scout's two-gate Step 2 and the markdown output contracts the issue path parses.
set -u
REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SKILL="$REPO_ROOT/skills/scout/SKILL.md"
SHARPEN="$REPO_ROOT/skills/scout-research/sharpen.md"
CANDIDACY="$REPO_ROOT/skills/scout-research/view-candidacy.md"

PASS=0; FAIL=0; declare -a FAIL_MSGS
pass() { PASS=$((PASS + 1)); echo "  PASS: $1"; }
fail() { FAIL_MSGS+=("$1"); FAIL=$((FAIL + 1)); echo "  FAIL: $1"; }
assert_grep() {
  local label="$1" pattern="$2" file="$3"
  if grep -qF -- "$pattern" "$file"; then pass "$label"
  else fail "$label: [$pattern] not found in $(basename "$file")"; fi
}
assert_grep_flat() {  # SKILL.md is free-wrapped prose; matching per-line would pin its line breaks
  local label="$1" pattern="$2" file="$3"
  if tr '\n' ' ' < "$file" | tr -s ' ' | grep -qF -- "$pattern"; then pass "$label"
  else fail "$label: [$pattern] not found in $(basename "$file")"; fi
}

echo "Testing /scout checkbox gates..."

grep -qE 'allowed-tools:.*AskUserQuestion' "$SKILL" \
  && pass "allowed-tools has AskUserQuestion" || fail "scout skill missing AskUserQuestion tool"

assert_grep "Step 2 keeps a prose gate" "Gate 1 — approve the brief" "$SKILL"
assert_grep "Step 2 has a checkbox gate" "Gate 2 — select the angles" "$SKILL"

# sharpen matches at most one series, and AskUserQuestion rejects a 1-option multiSelect.
grep -qE '`Series` *\| *single-select' "$SKILL" \
  && pass "Series stays single-select" || fail "Series must stay single-select"

# Every header SKILL.md asks AskUserQuestion to use must fit its 12-char limit. Read them
# out of the Gate-2 table rather than a hardcoded list, so a new over-long header is caught.
mapfile -t HEADERS < <(grep -E '^\|.*\| *(multiSelect|single-select) *\|' "$SKILL" \
  | awk -F'|' '{ h=$3; gsub(/^[` ]+|[` ]+$/, "", h); print h }')
if [ "${#HEADERS[@]}" -eq 4 ]; then pass "found 4 AskUserQuestion headers in SKILL.md"
else fail "expected 4 AskUserQuestion headers in SKILL.md, found ${#HEADERS[@]}"; fi
for h in "${HEADERS[@]}"; do
  if [ "${#h}" -le 12 ]; then pass "header fits AskUserQuestion's 12-char limit: $h"
  else fail "header too long for AskUserQuestion: $h (${#h} chars)"; fi
done

# AskUserQuestion needs >= 2 options, so a one-entry list can't be a checkbox list.
assert_grep_flat "single-option fallback documented" "single-select Yes/No" "$SKILL"

assert_grep_flat "Gate 2 is a single AskUserQuestion call" 'call `AskUserQuestion` **once**' "$SKILL"
assert_grep_flat "no pre-ticking documented" "**Nothing is pre-ticked**" "$SKILL"
assert_grep_flat "Other answer routes back to Gate 1" "go back to Gate 1" "$SKILL"
assert_grep_flat "no-question case falls through to single-pass" \
  "skip Gate 2 entirely and continue as single-pass" "$SKILL"
assert_grep_flat "Gate 2 selection drives Step 3" "ticked in Step 2's Gate 2" "$SKILL"
assert_grep_flat "Series No means no filing" 'answered `Yes` to Step 2' "$SKILL"

# CI contract: the issue path parses these, so they must not move.
assert_grep "sharpen.md still emits scout-subtopics" '```scout-subtopics' "$SHARPEN"
assert_grep "sharpen.md still emits scout-series" '```scout-series' "$SHARPEN"
assert_grep "sharpen.md keeps the tick format" '- [x] (depth) **Title**' "$SHARPEN"
assert_grep "view-candidacy.md still emits JSON" '"should_offer_view"' "$CANDIDACY"

echo; echo "Results: $PASS passed, $FAIL failed"
if [ $FAIL -gt 0 ]; then printf '  %s\n' "${FAIL_MSGS[@]}"; exit 1; fi
