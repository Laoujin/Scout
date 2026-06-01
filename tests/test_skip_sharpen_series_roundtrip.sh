#!/usr/bin/env bash
# End-to-end of the skip-sharpen path with a series block embedded directly in
# the issue body's ### Topic section (how the _michelin-batch templates carry
# series intent — the sharpener never runs to emit one). Proves the block
# survives: parse_issue_body -> SHARPENED_TOPIC=RAW_TOPIC -> issue-comment.sh
# render -> parse_series, yielding the right slug + group.

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
PASS=0; FAIL=0
declare -a FAIL_MSGS
pass() { PASS=$((PASS + 1)); echo "  PASS: $1"; }
fail() { FAIL_MSGS+=("$1"); FAIL=$((FAIL + 1)); echo "  FAIL: $1"; }

echo "Testing skip_sharpen_series_roundtrip.sh..."

source "$REPO_ROOT/scripts/lib-issue-parse.sh"

# Stub `gh`: capture issue-comment.sh's --body instead of posting.
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

# Issue body shaped like the batch templates: Topic paragraph + scout-subtopics
# + scout-series, expedition depth, skip-sharpen ticked. (UTF-8 › U+203A and
# — U+2014 match the sharpen.md series-block format.)
ISSUE_BODY=$'### Topic\n\nPlan a weekend in Munich, Germany.\n\n```scout-subtopics\n- [x] (survey) **Things to do** \xe2\x80\x94 rationale.\n```\n```scout-series\n- [x] **michelin-weekends** \xe2\x80\xba Germany \xe2\x80\x94 Munich anchor.\n```\n\n### Depth\n\nexpedition\n\n### Options\n\n- [x] Skip sharpening (use my topic verbatim)\n'

# 1) Parse the issue body.
parse_issue_body "$ISSUE_BODY"
[ "$SKIP_SHARPEN" = "true" ] && pass "skip-sharpen detected" || fail "SKIP_SHARPEN=$SKIP_SHARPEN (expected true)"
printf '%s' "$RAW_TOPIC" | grep -q 'scout-series' && pass "RAW_TOPIC retains scout-series block" || fail "RAW_TOPIC lost the scout-series block"

# 2) Skip-sharpen branch: the workflow passes the topic through verbatim.
SHARPENED_TOPIC="$RAW_TOPIC"

# 3) Render the proposal comment.
export CAPTURE_FILE="$STUB/comment.txt"
ISSUE_NUMBER=1 GH_TOKEN=x GH_REPO=o/r DEPTH="$DEPTH" \
  SHARPENED_TOPIC="$SHARPENED_TOPIC" bash "$REPO_ROOT/scripts/issue-comment.sh"
grep -q '### Series' "$CAPTURE_FILE" && pass "comment renders ### Series section" || fail "no ### Series section in comment"

# 4) Parse the series back out of the bot comment (what research-from-issue does).
parse_series "$(cat "$CAPTURE_FILE")"
[ "$SERIES_SLUG" = "michelin-weekends" ] && pass "parsed SERIES_SLUG=michelin-weekends" || fail "SERIES_SLUG='$SERIES_SLUG'"
[ "$SERIES_GROUP" = "Germany" ] && pass "parsed SERIES_GROUP=Germany" || fail "SERIES_GROUP='$SERIES_GROUP'"

echo
echo "Results: $PASS passed, $FAIL failed"
if [ $FAIL -gt 0 ]; then
  printf '  %s\n' "${FAIL_MSGS[@]}"
  exit 1
fi
