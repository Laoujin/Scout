#!/usr/bin/env bash
# Asserts the two Scout slash commands exist with the right shape.
REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
PASS=0; FAIL=0; declare -a FAIL_MSGS
pass() { PASS=$((PASS + 1)); echo "  PASS: $1"; }
fail() { FAIL_MSGS+=("$1"); FAIL=$((FAIL + 1)); echo "  FAIL: $1"; }

ASYNC="$REPO_ROOT/.claude/commands/scout-async.md"
INTER="$REPO_ROOT/.claude/commands/scout.md"

# --- async ---
[ -f "$ASYNC" ] && pass "async command exists" || fail "missing $ASYNC"
[ -f "$REPO_ROOT/commands/scout.md" ] && fail "old commands/scout.md should be gone" || pass "old commands/scout.md removed"
if [ -f "$ASYNC" ]; then
  grep -qiE '\bformat\b' "$ASYNC" && fail "async must not mention format" || pass "async has no format"
  grep -q 'gh issue create' "$ASYNC" && pass "async creates an issue" || fail "async missing gh issue create"
fi

# --- interactive (filled in a later task) ---
[ -f "$INTER" ] && pass "interactive command exists" || fail "missing $INTER"
if [ -f "$INTER" ]; then
  grep -q 'allowed-tools:.*Agent' "$INTER" && pass "interactive allows Agent" || fail "interactive missing Agent tool"
  grep -q 'local-setup.sh' "$INTER" && pass "interactive calls local-setup.sh" || fail "interactive missing local-setup.sh"
fi

echo; echo "Results: $PASS passed, $FAIL failed"
if [ $FAIL -gt 0 ]; then printf '  %s\n' "${FAIL_MSGS[@]}"; exit 1; fi
