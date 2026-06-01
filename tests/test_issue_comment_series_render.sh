#!/usr/bin/env bash
# Tests that issue-comment.sh renders a ### Series section from a scout-series
# block, and strips that block from the scout-topic fenced block.

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
PASS=0; FAIL=0
declare -a FAIL_MSGS
pass() { PASS=$((PASS + 1)); echo "  PASS: $1"; }
fail() { FAIL_MSGS+=("$1"); FAIL=$((FAIL + 1)); echo "  FAIL: $1"; }

# Stub `gh`: capture the --body arg into $CAPTURE_FILE instead of posting.
STUB="$(mktemp -d)"; trap 'rm -rf "$STUB"' EXIT
cat > "$STUB/gh" <<'EOF'
#!/usr/bin/env bash
while [ $# -gt 0 ]; do
  case "$1" in
    --body) shift; printf '%s' "$1" > "$CAPTURE_FILE"; shift ;;
    *) shift ;;
  esac
done
EOF
chmod +x "$STUB/gh"
export PATH="$STUB:$PATH"

run_comment() {
  ISSUE_NUMBER=1 GH_TOKEN=x GH_REPO=o/r DEPTH=standard \
    SHARPENED_TOPIC="$1" bash "$REPO_ROOT/scripts/issue-comment.sh"
}

# --- narrow: with scout-series block only ---
export CAPTURE_FILE="$STUB/narrow-series.txt"
TOPIC=$'A Munich weekend planned around a Michelin anchor.\n```scout-series\n- [x] **michelin-weekends** \xe2\x80\xba Germany \xe2\x80\x94 Munich anchor.\n```'
run_comment "$TOPIC"
grep -q '### Series' "$CAPTURE_FILE" && pass "narrow: series section rendered" || fail "narrow: no ### Series section"
grep -qF -- '- [x] **michelin-weekends**' "$CAPTURE_FILE" && pass "narrow: checkbox rendered ticked" || fail "narrow: checkbox missing"
awk '/<!-- scout-topic-start -->/{f=1;next} /<!-- scout-topic-end -->/{f=0} f' "$CAPTURE_FILE" | grep -q 'scout-series' \
  && fail "narrow: scout-series leaked into topic block" \
  || pass "narrow: scout-series stripped from topic block"
grep -qE '^> ' "$CAPTURE_FILE" && fail "narrow: blockquote should be gone" || pass "narrow: no blockquote"
grep -qF '```scout-topic' "$CAPTURE_FILE" && fail "narrow: scout-topic fence should be gone" || pass "narrow: no scout-topic fence"
grep -qF '<!-- scout-topic-start -->' "$CAPTURE_FILE" && pass "narrow: marker present" || fail "narrow: marker missing"
# Fix 1: blank line before the action item
BODY="$(cat "$CAPTURE_FILE")"
PREV_LINE="$(printf '%s\n' "$BODY" | grep -n '^\- \[ \] \*\*Start research\*\*' | head -1 | cut -d: -f1)"
if [ -n "$PREV_LINE" ] && [ "$PREV_LINE" -gt 1 ]; then
  PRECEDING="$(printf '%s\n' "$BODY" | sed -n "$((PREV_LINE - 1))p")"
  [ -z "$PRECEDING" ] && pass "narrow: blank line before Start research" || fail "narrow: no blank line before Start research (got: '$PRECEDING')"
else
  fail "narrow: could not find Start research line"
fi

# --- narrow: without scout-series block ---
export CAPTURE_FILE="$STUB/narrow-plain.txt"
run_comment "A plain topic with no series."
grep -q '### Series' "$CAPTURE_FILE" && fail "narrow-plain: unexpected ### Series section" || pass "narrow-plain: no series section when absent"
grep -qF '**Start research**' "$CAPTURE_FILE" && pass "narrow-plain: Start research checkbox still present" || fail "narrow-plain: Start research missing"

# --- wide: with both scout-subtopics and scout-series blocks ---
export CAPTURE_FILE="$STUB/wide-both.txt"
WIDE_TOPIC=$'A wide topic.\n```scout-subtopics\n- [x] (survey) **Angle one** \xe2\x80\x94 rationale.\n```\n```scout-series\n- [x] **michelin-weekends** \xe2\x80\xba Germany \xe2\x80\x94 Munich anchor.\n```'
run_comment "$WIDE_TOPIC"
grep -q '### Sub-topics' "$CAPTURE_FILE" && pass "wide: Sub-topics section present" || fail "wide: no ### Sub-topics section"
grep -q '### Series' "$CAPTURE_FILE" && pass "wide: Series section present" || fail "wide: no ### Series section"
grep -q '### Go' "$CAPTURE_FILE" && pass "wide: ### Go header present" || fail "wide: no ### Go header"
grep -qF '**Start research**' "$CAPTURE_FILE" && pass "wide: Start research checkbox present" || fail "wide: Start research missing"
grep -qF '**Research as one expedition instead**' "$CAPTURE_FILE" && pass "wide: Research as one expedition present" || fail "wide: Research as one expedition missing"
awk '/<!-- scout-topic-start -->/{f=1;next} /<!-- scout-topic-end -->/{f=0} f' "$CAPTURE_FILE" | grep -q 'scout-subtopics' \
  && fail "wide: scout-subtopics leaked into topic block" \
  || pass "wide: scout-subtopics stripped from topic block"
awk '/<!-- scout-topic-start -->/{f=1;next} /<!-- scout-topic-end -->/{f=0} f' "$CAPTURE_FILE" | grep -q 'scout-series' \
  && fail "wide: scout-series leaked into topic block" \
  || pass "wide: scout-series stripped from topic block"
# Fix 1: blank line immediately before ### Go
BODY="$(cat "$CAPTURE_FILE")"
GO_LINE="$(printf '%s\n' "$BODY" | grep -n '^### Go$' | head -1 | cut -d: -f1)"
if [ -n "$GO_LINE" ] && [ "$GO_LINE" -gt 1 ]; then
  PRECEDING="$(printf '%s\n' "$BODY" | sed -n "$((GO_LINE - 1))p")"
  [ -z "$PRECEDING" ] && pass "wide: blank line before ### Go" || fail "wide: no blank line before ### Go (got: '$PRECEDING')"
else
  fail "wide: could not find ### Go line"
fi

echo
echo "Results: $PASS passed, $FAIL failed"
if [ $FAIL -gt 0 ]; then
  printf '  %s\n' "${FAIL_MSGS[@]}"
  exit 1
fi
