#!/usr/bin/env bash
# Asserts the two user-facing Scout entry points exist with the right shape.
# They are skills (commands are skills now): `name:` makes them invocable bare as
# /scout and /scout-async. (Whether each also sets `disable-model-invocation` to be
# manual-only is a per-skill design choice, not asserted here.)
REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
PASS=0; FAIL=0; declare -a FAIL_MSGS
pass() { PASS=$((PASS + 1)); echo "  PASS: $1"; }
fail() { FAIL_MSGS+=("$1"); FAIL=$((FAIL + 1)); echo "  FAIL: $1"; }

ASYNC="$REPO_ROOT/skills/scout-async/SKILL.md"
INTER="$REPO_ROOT/skills/scout/SKILL.md"

[ -f "$ASYNC" ] && pass "async skill exists" || fail "missing $ASYNC"
[ -f "$INTER" ] && pass "interactive skill exists" || fail "missing $INTER"
[ ! -e "$REPO_ROOT/.claude/commands" ] && pass "old .claude/commands removed" || fail ".claude/commands should be gone (commands are skills now)"

# name: → bare /scout and /scout-async invocation
grep -qx 'name: scout' "$INTER" && pass "interactive is name: scout (→ /scout)" || fail "scout skill missing 'name: scout'"
grep -qx 'name: scout-async' "$ASYNC" && pass "async is name: scout-async (→ /scout-async)" || fail "async missing 'name: scout-async'"

# both must be user-invocable (must NOT be hidden from the menu)
for f in "$INTER" "$ASYNC"; do
  n="$(basename "$(dirname "$f")")"
  grep -q 'user-invocable: false' "$f" && fail "$n must stay user-invocable" || pass "$n is user-invocable"
done

# async shape
grep -qiE '\bformat\b' "$ASYNC" && fail "async must not mention format" || pass "async has no format"
grep -q 'gh issue create' "$ASYNC" && pass "async creates an issue" || fail "async missing gh issue create"

# interactive shape
grep -q 'allowed-tools:.*Agent' "$INTER" && pass "interactive allows Agent" || fail "interactive missing Agent tool"
grep -q 'local-setup.sh' "$INTER" && pass "interactive calls local-setup.sh" || fail "interactive missing local-setup.sh"

echo; echo "Results: $PASS passed, $FAIL failed"
if [ $FAIL -gt 0 ]; then printf '  %s\n' "${FAIL_MSGS[@]}"; exit 1; fi
