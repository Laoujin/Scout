#!/usr/bin/env bash
REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
PASS=0; FAIL=0; declare -a FAIL_MSGS
pass() { PASS=$((PASS + 1)); echo "  PASS: $1"; }
fail() { FAIL_MSGS+=("$1"); FAIL=$((FAIL + 1)); echo "  FAIL: $1"; }
MD="$REPO_ROOT/.claude/commands/scout.md"

grep -q 'atlas-checkout' "$MD" && fail "still references atlas-checkout" || pass "no atlas-checkout refs"
grep -q 'atlas-config.sh' "$MD" && pass "references atlas-config.sh" || fail "missing atlas-config.sh"
grep -q 'WORKTREE' "$MD" && pass "threads WORKTREE" || fail "missing WORKTREE"
grep -q '~/.scout/atlas' "$MD" && pass "documents ~/.scout/atlas pointer" || fail "missing ~/.scout/atlas"

echo; echo "Results: $PASS passed, $FAIL failed"
[ $FAIL -gt 0 ] && { printf '  %s\n' "${FAIL_MSGS[@]}"; exit 1; } || exit 0
