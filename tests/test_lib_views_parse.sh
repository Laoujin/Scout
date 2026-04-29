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

# I1 regression: regex-special chars in slug must not produce false wildcard matches
BODY_DOTS=$'<!-- scout-view-targets-start -->\n```scout-view-targets\n{"items":[{"slug":"node.js-tools","path":"foo","view_name":null,"title_suffix":null,"vibe_hint":null,"row":"leaf"}]}\n```\n<!-- scout-view-targets-end -->\n- [x] something else <!-- slug:nodeXjs-tools -->\n'
parse_view_ticks "$BODY_DOTS"
# Slug is in the JSON so it resolves to "false", not a match against the wildcard tick nodeXjs-tools
assert_eq "I1: dot-slug not matched against wildcard" "false" "${VIEW_TICKS[node.js-tools]:-}"

# I2 regression: malformed JSON causes parse_view_ticks to return non-zero
BODY_BAD=$'<!-- scout-view-targets-start -->\n```scout-view-targets\n{"items":[malformed]}\n```\n<!-- scout-view-targets-end -->\n'
if parse_view_ticks "$BODY_BAD" 2>/dev/null; then
  fail "I2: malformed JSON: parse_view_ticks should return non-zero"
else
  pass "I2: malformed JSON: parse_view_ticks returns non-zero"
fi

# I3 regression: leading whitespace and asterisk-bullet variants tolerated
BODY_WS=$'<!-- scout-view-targets-start -->\n```scout-view-targets\n{"items":[{"slug":"foo","path":"x","view_name":null,"title_suffix":null,"vibe_hint":null,"row":"leaf"}]}\n```\n<!-- scout-view-targets-end -->\n  - [x] foo <!-- slug:foo -->\n   * [x] **Start creating the HTML pages**\n'
parse_view_ticks "$BODY_WS"
assert_eq "I3: leading whitespace: tick recognized" "true" "${VIEW_TICKS[foo]:-}"
parse_views_start "$BODY_WS"
assert_eq "I3: leading whitespace + asterisk bullet: start recognized" "true" "$VIEWS_START"

echo
echo "Results: $PASS pass, $FAIL fail"
if [ "$FAIL" -gt 0 ]; then
  printf '  - %s\n' "${FAIL_MSGS[@]}"
  exit 1
fi
