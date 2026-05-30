#!/usr/bin/env bash
# Tests that issue-comment.sh renders a ### Series section from a scout-series
# block, and strips that block from the scout-topic fenced block.

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
PASS=0; FAIL=0
declare -a FAIL_MSGS
pass() { PASS=$((PASS + 1)); echo "  PASS: $1"; }
fail() { FAIL_MSGS+=("$1"); FAIL=$((FAIL + 1)); echo "  FAIL: $1"; }

# Stub `gh`: capture the --body arg into $CAP instead of posting.
STUB="$(mktemp -d)"; trap 'rm -rf "$STUB"' EXIT
CAP="$STUB/body.txt"
cat > "$STUB/gh" <<EOF
#!/usr/bin/env bash
while [ \$# -gt 0 ]; do
  if [ "\$1" = "--body" ]; then shift; printf '%s' "\$1" > "$CAP"; fi
  shift
done
EOF
chmod +x "$STUB/gh"

run_comment() {
  PATH="$STUB:$PATH" ISSUE_NUMBER=1 GH_TOKEN=x GH_REPO=o/r DEPTH=standard \
    SHARPENED_TOPIC="$1" bash "$REPO_ROOT/scripts/issue-comment.sh"
}

# --- with scout-series block ---
TOPIC=$'A Munich weekend planned around a Michelin anchor.\n```scout-series\n- [x] **michelin-weekends** \xe2\x80\xba Germany \xe2\x80\x94 Munich anchor.\n```'
run_comment "$TOPIC"
grep -q '### Series' "$CAP" && pass "series section rendered" || fail "no ### Series section"
grep -qF -- '- [x] **michelin-weekends**' "$CAP" && pass "checkbox rendered ticked" || fail "checkbox missing"
awk '/```scout-topic/{f=1;next} /```/{f=0} f' "$CAP" | grep -q 'scout-series' \
  && fail "scout-series leaked into scout-topic block" \
  || pass "scout-series stripped from scout-topic block"

# --- without scout-series block: no Series section ---
run_comment "A plain topic with no series."
grep -q '### Series' "$CAP" && fail "unexpected ### Series section" || pass "no series section when absent"
grep -qF '**Start research**' "$CAP" && pass "Start research checkbox still present" || fail "Start research missing"

echo
echo "Results: $PASS passed, $FAIL failed"
if [ $FAIL -gt 0 ]; then
  printf '  %s\n' "${FAIL_MSGS[@]}"
  exit 1
fi
