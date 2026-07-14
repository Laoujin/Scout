#!/usr/bin/env bash
# Guards /scout's two-gate Steps 2 and 5.5, and the markdown output contracts the issue
# path parses.
set -u
REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SKILL="$REPO_ROOT/skills/scout/SKILL.md"
SHARPEN="$REPO_ROOT/skills/scout-research/sharpen.md"
CANDIDACY="$REPO_ROOT/skills/scout-research/view-candidacy.md"

PASS=0; FAIL=0; declare -a FAIL_MSGS
pass() { PASS=$((PASS + 1)); echo "  PASS: $1"; }
fail() { FAIL_MSGS+=("$1"); FAIL=$((FAIL + 1)); echo "  FAIL: $1"; }
assert_grep() {  # line-anchored: ### headings and fenced-block contracts, which never wrap
  local label="$1" pattern="$2" file="$3"
  if grep -qF -- "$pattern" "$file"; then pass "$label"
  else fail "$label: [$pattern] not found in $(basename "$file")"; fi
}
assert_flat() {  # SKILL.md is free-wrapped prose; matching per-line would pin its line breaks
  local label="$1" pattern="$2" text="$3"
  if grep -qF -- "$pattern" <<< "$text"; then pass "$label"
  else fail "$label: [$pattern] not found"; fi
}

SKILL_FLAT=$(tr '\n' ' ' < "$SKILL" | tr -s ' ')
# Both steps word their gates alike, so a whole-file grep for a Gate rule is satisfied by the
# other step's copy — deleting one step's rules would still pass. Slice each gate out and
# assert inside it; only phrases with no twin may be matched against $SKILL_FLAT.
STEP2_G2=$(sed -n '/^### Gate 2 — select the angles/,/^## Step 3/p' "$SKILL" \
  | tr '\n' ' ' | tr -s ' ')
VIEWS_G1=$(sed -n '/^### Gate 1 — candidacy table/,/^### Gate 2 — select the views/p' "$SKILL" \
  | tr '\n' ' ' | tr -s ' ')
VIEWS_G2=$(sed -n '/^### Gate 2 — select the views/,/^### Author/p' "$SKILL" \
  | tr '\n' ' ' | tr -s ' ')

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
assert_flat "single-option fallback documented" "single-select Yes/No" "$STEP2_G2"

assert_flat "Gate 2 is a single AskUserQuestion call" 'call `AskUserQuestion` **once**' "$STEP2_G2"
assert_flat "no pre-ticking documented" "**Nothing is pre-ticked**" "$STEP2_G2"
assert_flat "Other answer routes back to Gate 1" \
  "re-sharpen feedback — go back to Gate 1" "$STEP2_G2"
assert_flat "no-question case falls through to single-pass" \
  "skip Gate 2 entirely and continue as single-pass" "$SKILL_FLAT"
assert_flat "Gate 2 selection drives Step 3" "ticked in Step 2's Gate 2" "$SKILL_FLAT"
assert_flat "Series No means no filing" 'answered `Yes` to Step 2' "$SKILL_FLAT"

assert_grep "Step 5.5 keeps a prose gate" "### Gate 1 — candidacy table" "$SKILL"
assert_grep "Step 5.5 has a checkbox gate" "### Gate 2 — select the views" "$SKILL"
assert_grep "Step 5.5 authors after the gates" "### Author (parallel sub-agents)" "$SKILL"

assert_flat "Gate 1 lists the candidacy columns" \
  'Columns: Page | Offer? | Register (`view_name`) | Vibe (`vibe_hint`).' "$VIEWS_G1"
assert_flat "Gate 1 is the only place a register changes" \
  "This is the only place a register can change" "$VIEWS_G1"
assert_flat "Gate 1 stops for approval" "**Stop until they approve.**" "$VIEWS_G1"
# view-candidacy.md nulls the register of a rejected row and takes no feedback input, so a
# promotion has to mint one — a re-judge would just re-reject the row.
assert_flat "Gate 1 promotion is an override, not a re-judge" \
  "A promotion is a user **override**, not a re-judge" "$VIEWS_G1"
assert_flat "Gate 1 mints the register of a promoted row" \
  'mint them yourself from `view-candidacy.md`'"'"'s register vocabulary' "$VIEWS_G1"
assert_flat "Gate 1 refuses to promote an html canonical" \
  'A page whose canonical is already `format: html` is **not** promotable' "$VIEWS_G1"

assert_flat "Step 5.5 Gate 2 is a single AskUserQuestion call" \
  'call `AskUserQuestion` **once**' "$VIEWS_G2"
assert_flat "Step 5.5 Gate 2 offers only the approved ✓ rows" \
  'over only the rows approved as `✓` at Gate 1' "$VIEWS_G2"
assert_flat "Step 5.5 Gate 2 pre-ticks nothing" "**Nothing is pre-ticked**" "$VIEWS_G2"
assert_flat "Step 5.5 Gate 2 binds description to the judge's fields" \
  'Option `label` is the page title; `description` is `<view_name> — <vibe_hint>`.' "$VIEWS_G2"
assert_flat "Step 5.5 one-candidate case asks Yes/No" \
  "Exactly one surviving row is asked as a **single-select Yes/No**" "$VIEWS_G2"
assert_flat "Step 5.5 zero-candidate case falls through to Step 6" \
  "skip Gate 2 entirely and go straight to Step 6" "$VIEWS_G2"
assert_flat "Step 5.5 Other answer routes back to Gate 1" \
  "An **Other** answer is re-judge feedback — go back to Gate 1." "$VIEWS_G2"

# Step 5.5 names its headers in prose, not in a `| … | multiSelect |` row, so the table-based
# check above can't see them. Match the header tokens themselves — a sentence-shaped match
# would stop at the first period and miss a header named after it.
mapfile -t VIEW_HEADERS < <(grep -oE '`HTML views[^`]*`' <<< "$VIEWS_G2" | tr -d '`')
if [ "${#VIEW_HEADERS[@]}" -eq 3 ]; then pass "found 3 Step 5.5 view headers in SKILL.md"
else fail "expected 3 Step 5.5 view headers in SKILL.md, found ${#VIEW_HEADERS[@]}"; fi
for h in "${VIEW_HEADERS[@]}"; do
  if [ "${#h}" -le 12 ]; then pass "view header fits AskUserQuestion's 12-char limit: $h"
  else fail "view header too long for AskUserQuestion: $h (${#h} chars)"; fi
done

# CI contract: the issue path parses these, so they must not move.
assert_grep "sharpen.md still emits scout-subtopics" '```scout-subtopics' "$SHARPEN"
assert_grep "sharpen.md still emits scout-series" '```scout-series' "$SHARPEN"
assert_grep "sharpen.md keeps the tick format" '- [x] (depth) **Title**' "$SHARPEN"
assert_grep "view-candidacy.md still emits JSON" '"should_offer_view"' "$CANDIDACY"

echo; echo "Results: $PASS passed, $FAIL failed"
if [ $FAIL -gt 0 ]; then printf '  %s\n' "${FAIL_MSGS[@]}"; exit 1; fi
