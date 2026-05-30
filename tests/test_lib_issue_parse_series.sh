#!/usr/bin/env bash
# Tests for parse_series() in lib-issue-parse.sh.

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
source "$REPO_ROOT/scripts/lib-issue-parse.sh"

PASS=0; FAIL=0
declare -a FAIL_MSGS
pass() { PASS=$((PASS + 1)); echo "  PASS: $1"; }
fail() { FAIL_MSGS+=("$1"); FAIL=$((FAIL + 1)); echo "  FAIL: $1"; }
assert_eq() {
  local label="$1" expected="$2" actual="$3"
  if [ "$expected" = "$actual" ]; then pass "$label"
  else fail "$label: expected [$expected], got [$actual]"; fi
}

echo "Testing parse_series()..."

# --- ticked, with group ---
COMMENT=$'### Series\n- [x] **michelin-weekends** \xe2\x80\xba Germany \xe2\x80\x94 Munich weekend.\n\n### Go\n- [ ] **Start research**\n'
parse_series "$COMMENT"
assert_eq "grouped: slug"  "michelin-weekends" "$SERIES_SLUG"
assert_eq "grouped: group" "Germany"           "$SERIES_GROUP"

# --- ticked, flat (no group) ---
COMMENT=$'### Series\n- [x] **sessions-and-workshops** \xe2\x80\x94 talk prep.\n'
parse_series "$COMMENT"
assert_eq "flat: slug"  "sessions-and-workshops" "$SERIES_SLUG"
assert_eq "flat: group" ""                        "$SERIES_GROUP"

# --- unticked -> nothing ---
COMMENT=$'### Series\n- [ ] **michelin-weekends** \xe2\x80\xba Germany \xe2\x80\x94 Munich.\n'
parse_series "$COMMENT"
assert_eq "unticked: slug"  "" "$SERIES_SLUG"
assert_eq "unticked: group" "" "$SERIES_GROUP"

# --- absent section -> nothing ---
COMMENT=$'### Go\n- [ ] **Start research**\n'
parse_series "$COMMENT"
assert_eq "absent: slug"  "" "$SERIES_SLUG"
assert_eq "absent: group" "" "$SERIES_GROUP"

# --- lenient: ascii separators, asterisk bullet, leading ws, slash group ---
COMMENT=$'### Series\n  * [X] **michelin-weekends** / Germany - Munich.\n'
parse_series "$COMMENT"
assert_eq "lenient: slug"  "michelin-weekends" "$SERIES_SLUG"
assert_eq "lenient: group" "Germany"           "$SERIES_GROUP"

# --- hyphenated group label with space-hyphen rationale separator (fix #1) ---
COMMENT=$'### Series\n- [x] **michelin-weekends** \xe2\x80\xba Bosnia-Herzegovina - some rationale.\n'
parse_series "$COMMENT"
assert_eq "hyphenated-group: slug"  "michelin-weekends"  "$SERIES_SLUG"
assert_eq "hyphenated-group: group" "Bosnia-Herzegovina" "$SERIES_GROUP"

echo
echo "Results: $PASS passed, $FAIL failed"
if [ $FAIL -gt 0 ]; then
  printf '  %s\n' "${FAIL_MSGS[@]}"
  exit 1
fi
