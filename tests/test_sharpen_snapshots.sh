#!/usr/bin/env bash
# Snapshot tests for skills/scout/sharpen.md.
#
# Three modes:
#   SCOUT_SKIP_CLAUDE=1 ... bash tests/test_sharpen_snapshots.sh
#       Exits 0 without invoking claude. CI-safe escape hatch.
#
#   UPDATE_SNAPSHOTS=1 ... bash tests/test_sharpen_snapshots.sh
#       Re-captures fixtures by invoking sharpen.sh on each fixture .txt
#       and writing the output to the corresponding .expected.md.
#       Use after intentional prompt changes; manually review the diff in git.
#
#   bash tests/test_sharpen_snapshots.sh    (default)
#       Validates the captured *.expected.md files STRUCTURALLY — does NOT
#       invoke claude. Asserts shape invariants of the snapshots:
#         - both files non-empty, LF line endings
#         - narrow: no fenced blocks, no bullet lines
#         - wide: paragraph + scout-subtopics fenced block + 2-8 sub-topic
#           lines matching the canonical regex, all depths in
#           {recon, survey, expedition}, every line carries a [ ] checkbox.
#       This catches real prompt regressions without false-failing on
#       Claude's normal output drift.

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
FIXTURES="$REPO_ROOT/tests/fixtures/sharpen"
PASS=0; FAIL=0
declare -a FAIL_MSGS
pass() { PASS=$((PASS + 1)); echo "  PASS: $1"; }
fail() { FAIL_MSGS+=("$1"); FAIL=$((FAIL + 1)); echo "  FAIL: $1"; }

if [ "${SCOUT_SKIP_CLAUDE:-}" = "1" ]; then
  echo "SCOUT_SKIP_CLAUDE=1 — skipping snapshot tests."
  exit 0
fi

echo "Testing sharpen_snapshots.sh..."

# --- Update mode: re-capture snapshots from live claude invocations ---
if [ "${UPDATE_SNAPSHOTS:-}" = "1" ]; then
  for fix in "$FIXTURES"/*.txt; do
    base="$(basename "$fix" .txt)"
    expected="$FIXTURES/$base.expected.md"
    topic="$(cat "$fix")"
    actual="$(RAW_TOPIC="$topic" DEPTH=deep FORMAT=auto \
              bash "$REPO_ROOT/scripts/sharpen.sh")"
    printf '%s\n' "$actual" > "$expected"
    pass "$base (captured)"
  done
  echo
  echo "Results: $PASS passed, $FAIL failed"
  exit 0
fi

# --- Default mode: structural validation of captured snapshots ---

NARROW="$FIXTURES/narrow_topic.expected.md"
WIDE="$FIXTURES/wide_topic.expected.md"

# Both files must exist and be non-empty.
[ -s "$NARROW" ] && pass "narrow snapshot exists and non-empty" \
                 || fail "narrow snapshot missing or empty: $NARROW"
[ -s "$WIDE" ]   && pass "wide snapshot exists and non-empty" \
                 || fail "wide snapshot missing or empty: $WIDE"

# Both must be LF-only (no CR).
if [ -s "$NARROW" ]; then
  grep -q $'\r' "$NARROW" && fail "narrow has CRLF line endings" \
                          || pass "narrow uses LF line endings"
fi
if [ -s "$WIDE" ]; then
  grep -q $'\r' "$WIDE" && fail "wide has CRLF line endings" \
                        || pass "wide uses LF line endings"
fi

# --- Narrow: no fenced blocks, no bullet lines (single paragraph only) ---
if [ -s "$NARROW" ]; then
  fences=$(grep -c '^```' "$NARROW" || true)
  bullets=$(grep -cE '^[-*] ' "$NARROW" || true)
  [ "$fences" -eq 0 ] && pass "narrow: no fenced blocks" \
                      || fail "narrow: $fences fenced-block line(s) found, expected 0"
  [ "$bullets" -eq 0 ] && pass "narrow: no bullet lines" \
                       || fail "narrow: $bullets bullet line(s) found, expected 0"
fi

# --- Wide: paragraph + scout-subtopics block + 2-8 canonical sub-topic lines ---
if [ -s "$WIDE" ]; then
  open=$(grep -c '^```scout-subtopics' "$WIDE" || true)
  total_fences=$(grep -c '^```' "$WIDE" || true)
  [ "$open" -eq 1 ] && pass "wide: exactly one scout-subtopics opener" \
                    || fail "wide: $open scout-subtopics opener(s), expected 1"
  [ "$total_fences" -eq 2 ] && pass "wide: exactly two total fences (open + close)" \
                            || fail "wide: $total_fences total fence(s), expected 2"

  canonical=$(grep -cE '^- \[ \] \([a-z]+\) \*\*.+\*\* — .+$' "$WIDE" || true)
  if [ "$canonical" -ge 2 ] && [ "$canonical" -le 8 ]; then
    pass "wide: $canonical sub-topic line(s) matching canonical regex (2-8)"
  else
    fail "wide: $canonical sub-topic line(s) matching canonical, expected 2-8"
  fi

  bare=$(grep -cE '^- \([a-z]+\) \*\*.+\*\* — .+$' "$WIDE" || true)
  [ "$bare" -eq 0 ] && pass "wide: every sub-topic carries a [ ] checkbox" \
                    || fail "wide: $bare sub-topic line(s) missing checkbox prefix"

  # Every (depth) token must be in {recon, survey, expedition}.
  bad_depths=$(grep -oE '^- \[ \] \(([a-z]+)\)' "$WIDE" | sed -E 's/.*\((.*)\)/\1/' | grep -vE '^(recon|survey|expedition)$' | wc -l | tr -d ' ')
  [ "$bad_depths" -eq 0 ] && pass "wide: all (depth) tokens in {recon, survey, expedition}" \
                          || fail "wide: $bad_depths sub-topic(s) with unrecognized depth token"
fi

echo
echo "Results: $PASS passed, $FAIL failed"
if [ $FAIL -gt 0 ]; then
  printf '  %s\n' "${FAIL_MSGS[@]}"
  exit 1
fi
