#!/usr/bin/env bash
# Tests for scripts/lib-rerun-parse.sh

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
source "$REPO_ROOT/scripts/lib-rerun-parse.sh"

PASS=0; FAIL=0
declare -a FAIL_MSGS
pass() { PASS=$((PASS + 1)); echo "  PASS: $1"; }
fail() { FAIL_MSGS+=("$1"); FAIL=$((FAIL + 1)); echo "  FAIL: $1"; }

echo "Testing lib-rerun-parse.sh..."

BODY="$(cat <<'EOF'
### Some sub-topics failed

2 of 3 sub-topics didn't complete.

- `topic-b` — Claude hit a usage/rate limit
- `topic-c` — hard timeout

- [x] **Re-run failed sub-topics**

<!-- scout-rerun: 2026-05-25-a-heist-weekend -->
EOF
)"

# --- parse_rerun_expedition ---
parse_rerun_expedition "$BODY"
[ "$RERUN_EXPEDITION" = "2026-05-25-a-heist-weekend" ] \
  && pass "parse_rerun_expedition extracts the folder name" \
  || fail "expected expedition slug, got '$RERUN_EXPEDITION'"

# --- parse_rerun_start: ticked ---
parse_rerun_start "$BODY"
[ "$RERUN_START" = "true" ] && pass "ticked checkbox detected" || fail "ticked checkbox not detected"

# --- parse_rerun_start: unticked ---
parse_rerun_start "${BODY/\[x\]/[ ]}"
[ "$RERUN_START" = "false" ] && pass "unticked checkbox detected" || fail "unticked should be false (got $RERUN_START)"

# --- manifest_to_subtopics ---
TMP="$(mktemp -d)"; trap 'rm -rf "$TMP"' EXIT
cat > "$TMP/manifest.json" <<'JSON'
[
  {"slug":"topic-a","title":"Topic A","depth":"standard","status":"success","start":1,"end":2},
  {"slug":"topic-b","title":"Topic B: nuance","depth":"deep","status":"failed","start":1,"end":2}
]
JSON
TSV="$(manifest_to_subtopics "$TMP/manifest.json")"
expected="$(printf 'Topic A|standard||true\nTopic B: nuance|deep||true')"
[ "$TSV" = "$expected" ] \
  && pass "manifest_to_subtopics rebuilds all children as checked" \
  || fail "TSV mismatch. got:
$TSV
want:
$expected"

echo ""
echo "Results: $PASS passed, $FAIL failed"
if [ "$FAIL" -gt 0 ]; then
  printf '  %s\n' "${FAIL_MSGS[@]}"
  exit 1
fi
