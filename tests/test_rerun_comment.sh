#!/usr/bin/env bash
# Tests for scripts/rerun-comment.sh — posts a "re-run failed sub-topics"
# checkbox comment when an expedition has failed children, and stays silent
# otherwise.

set -u
REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
PASS=0; FAIL=0
declare -a FAIL_MSGS
pass() { PASS=$((PASS + 1)); echo "  PASS: $1"; }
fail() { FAIL_MSGS+=("$1"); FAIL=$((FAIL + 1)); echo "  FAIL: $1"; }

echo "Testing rerun-comment.sh..."

TMP="$(mktemp -d)"; trap 'rm -rf "$TMP"' EXIT
mkdir -p "$TMP/bin"
cat > "$TMP/bin/gh" <<'EOF'
#!/usr/bin/env bash
echo "called" >> "$CALL_LOG"
while [ $# -gt 0 ]; do
  case "$1" in
    --body) shift; printf '%s' "$1" > "$CAPTURE_FILE"; shift ;;
    *) shift ;;
  esac
done
EOF
chmod +x "$TMP/bin/gh"
export PATH="$TMP/bin:$PATH"

# --- Case 1: expedition with failed children → comment posted ---
EXP="$TMP/atlas/research/2026-05-25-a-heist-weekend"
mkdir -p "$EXP/lodging" "$EXP/activities" "$EXP/conferences"
cat > "$EXP/manifest.json" <<'JSON'
[
  {"slug":"lodging","title":"Walking-distance lodging","depth":"standard","status":"success","start":1,"end":2},
  {"slug":"activities","title":"Day-trips and activities","depth":"deep","status":"failed","start":1,"end":2},
  {"slug":"conferences","title":"IT conferences nearby","depth":"standard","status":"failed_hard_timeout","start":1,"end":2}
]
JSON
cat > "$EXP/activities/index.md" <<'MD'
---
layout: research
status: failed
failure_reason: "Claude hit a usage/rate limit — likely ran out of tokens."
---
Research failed.
MD

export CALL_LOG="$TMP/calls.log"; : > "$CALL_LOG"
export CAPTURE_FILE="$TMP/body1.md"
ISSUE_NUMBER=61 GH_TOKEN=x GH_REPO=o/r PARENT_DIR="$EXP" \
  bash "$REPO_ROOT/scripts/rerun-comment.sh"

if [ -s "$CAPTURE_FILE" ]; then
  body="$(cat "$CAPTURE_FILE")"
  grep -q '<!-- scout-rerun: 2026-05-25-a-heist-weekend -->' "$CAPTURE_FILE" \
    && pass "embeds the expedition marker" || fail "missing scout-rerun marker"
  grep -qiE '^\s*-\s+\[ \]\s+\*\*Re-run failed sub-topics\*\*' "$CAPTURE_FILE" \
    && pass "renders the rerun checkbox" || fail "missing rerun checkbox"
  grep -q 'activities' "$CAPTURE_FILE" && grep -q 'conferences' "$CAPTURE_FILE" \
    && pass "lists both failed sub-topics" || fail "failed sub-topics not listed"
  grep -q 'usage/rate limit' "$CAPTURE_FILE" \
    && pass "shows the failure reason" || fail "failure reason not shown"
  ! grep -q 'lodging' "$CAPTURE_FILE" \
    && pass "omits the successful sub-topic" || fail "should not list the successful child"
else
  fail "no comment body captured for failed expedition"
fi

# --- Case 2: all children succeeded → no comment ---
EXP2="$TMP/atlas/research/2026-05-28-all-good"
mkdir -p "$EXP2"
cat > "$EXP2/manifest.json" <<'JSON'
[
  {"slug":"a","title":"A","depth":"standard","status":"success","start":1,"end":2},
  {"slug":"b","title":"B","depth":"standard","status":"skipped_success","start":1,"end":2}
]
JSON
: > "$CALL_LOG"
ISSUE_NUMBER=62 GH_TOKEN=x GH_REPO=o/r PARENT_DIR="$EXP2" \
  bash "$REPO_ROOT/scripts/rerun-comment.sh"
[ ! -s "$CALL_LOG" ] && pass "no comment when nothing failed" || fail "should not post when all succeeded"

echo ""
echo "Results: $PASS passed, $FAIL failed"
if [ "$FAIL" -gt 0 ]; then
  printf '  %s\n' "${FAIL_MSGS[@]}"
  exit 1
fi
