#!/usr/bin/env bash
# Verifies failure placeholders written by run-decompose.sh have the required
# frontmatter keys: status: failed, failure_reason, attempted_at, depth, layout: research.

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
PASS=0; FAIL=0
declare -a FAIL_MSGS
pass() { PASS=$((PASS + 1)); echo "  PASS: $1"; }
fail() { FAIL_MSGS+=("$1"); FAIL=$((FAIL + 1)); echo "  FAIL: $1"; }

TMP=$(mktemp -d)
mkdir -p "$TMP/scout/scripts" "$TMP/atlas-checkout"
cp "$REPO_ROOT/scripts/lib-issue-parse.sh" "$TMP/scout/scripts/"
cp "$REPO_ROOT/scripts/run-decompose.sh"   "$TMP/scout/scripts/"

# Stub run.sh that always fails.
cat > "$TMP/scout/scripts/run.sh" <<'STUB'
#!/usr/bin/env bash
exit 1
STUB
chmod +x "$TMP/scout/scripts/run.sh"

env PARENT_DIR="$TMP/atlas-checkout/p" \
    PARENT_TOPIC="t" PARENT_FORMAT=md DATE=2026-04-26 \
    SUB_TOPICS_TSV=$'A|standard||true' \
    SCOUT_DIR="$TMP/scout" \
    SCOUT_SKIP_SYNTHESIS=1 \
    bash "$TMP/scout/scripts/run-decompose.sh" >/dev/null 2>&1

f="$TMP/atlas-checkout/p/a/index.md"
[ -f "$f" ] && pass "placeholder file exists" || fail "no placeholder at $f"
grep -q '^layout: research' "$f"  && pass "layout: research"  || fail "missing layout: research"
grep -q '^status: failed'   "$f"  && pass "status: failed"    || fail "missing status: failed"
grep -q '^failure_reason: ' "$f"  && pass "failure_reason set" || fail "missing failure_reason"
grep -q '^attempted_at: '   "$f"  && pass "attempted_at set"  || fail "missing attempted_at"
grep -q '^depth: standard'  "$f"  && pass "depth recorded"    || fail "missing depth"

echo
echo "Passed: $PASS, Failed: $FAIL"
[ $FAIL -eq 0 ]
