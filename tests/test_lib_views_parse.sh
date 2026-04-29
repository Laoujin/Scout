#!/usr/bin/env bash
# Tests for parse_view_targets(), parse_view_ticks(), parse_views_start() in lib-views-parse.sh.

set -u

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
source "$REPO_ROOT/scripts/lib-views-parse.sh"

PASS=0; FAIL=0
declare -a FAIL_MSGS
pass() { PASS=$((PASS + 1)); echo "  PASS: $1"; }
fail() { FAIL_MSGS+=("$1"); FAIL=$((FAIL + 1)); echo "  FAIL: $1"; }
assert_eq() {
  local label="$1" expected="$2" actual="$3"
  if [ "$expected" = "$actual" ]; then pass "$label"
  else fail "$label: expected [$expected], got [$actual]"; fi
}

echo "Testing lib-views-parse.sh..."

BODY="$(cat "$REPO_ROOT/tests/fixtures/comments/dispatch-input-decompose.md")"

# parse_view_targets — extracts the JSON block, sets VIEW_TARGETS_JSON
parse_view_targets "$BODY"
[ -n "${VIEW_TARGETS_JSON:-}" ] && pass "VIEW_TARGETS_JSON populated" || fail "VIEW_TARGETS_JSON empty"
# JSON has 5 items
COUNT=$(printf '%s' "$VIEW_TARGETS_JSON" | jq '.items | length')
assert_eq "items count" "5" "$COUNT"

# parse_view_ticks — sets VIEW_TICKS associative array (slug → checked)
parse_view_ticks "$BODY"
assert_eq "tick high-signal-ai"        "true"  "${VIEW_TICKS[high-signal-ai]:-}"
assert_eq "tick long-form-bloggers"    "true"  "${VIEW_TICKS[long-form-bloggers]:-}"
assert_eq "tick youtube-channels"      "false" "${VIEW_TICKS[youtube-channels]:-}"
assert_eq "tick x-twitter-accounts"    "true"  "${VIEW_TICKS[x-twitter-accounts]:-}"
assert_eq "tick podcasts"              "false" "${VIEW_TICKS[podcasts]:-}"

# parse_views_start — sets VIEWS_START to true/false
parse_views_start "$BODY"
assert_eq "start ticked: true" "true" "$VIEWS_START"

# Negative case — start unticked
# sed used here because bash ${var/pat} treats [x] as a glob character class
BODY_UNTICKED="$(printf '%s' "$BODY" | sed 's/\- \[x\] \*\*Start creating the HTML pages\*\*/- [ ] **Start creating the HTML pages**/')"
parse_views_start "$BODY_UNTICKED"
assert_eq "start unticked: false" "false" "$VIEWS_START"

# Edge case — comment without scout-view-targets block
parse_view_targets "no block here"
assert_eq "no block: empty" "" "${VIEW_TARGETS_JSON:-}"

echo
echo "Results: $PASS pass, $FAIL fail"
if [ "$FAIL" -gt 0 ]; then
  printf '  - %s\n' "${FAIL_MSGS[@]}"
  exit 1
fi
