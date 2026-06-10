#!/usr/bin/env bash
# Tests for commit_with_identity() in scripts/lib-publish.sh — the shared commit
# identity precedence used by publish.sh AND triage-health.sh. Run:
#   bash tests/test_commit_identity.sh
#
# No network. Global/system git config is disabled (GIT_CONFIG_GLOBAL/SYSTEM=/dev/null)
# so the "no identity configured" fallback is deterministic regardless of the dev
# machine's ~/.gitconfig.

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
LIB="$REPO_ROOT/scripts/lib-publish.sh"
export GIT_CONFIG_GLOBAL=/dev/null GIT_CONFIG_SYSTEM=/dev/null

PASS=0; FAIL=0; declare -a FAIL_MSGS
pass() { PASS=$((PASS + 1)); echo "  PASS: $1"; }
fail() { FAIL_MSGS+=("$1"); FAIL=$((FAIL + 1)); echo "  FAIL: $1"; }

# new_repo: fresh repo with one staged change, no local identity. Echoes path.
new_repo() {
  local tmp; tmp=$(mktemp -d)
  git -c init.defaultBranch=main init -q "$tmp"
  echo x > "$tmp/f.txt"
  git -C "$tmp" add f.txt
  echo "$tmp"
}
author() { git -C "$1" log -1 --format='%an <%ae>'; }
# Run commit_with_identity inside <repo> with a controlled environment.
commit_in() { ( cd "$1" && shift && env "$@" bash -c "source '$LIB'; commit_with_identity 'snapshot'" ); }

# --- Case 1: no GIT_AUTHOR_* → the checkout's own git config authors the commit ---
t=$(new_repo)
git -C "$t" config user.name "Local User"
git -C "$t" config user.email "local@example.com"
commit_in "$t" -u GIT_AUTHOR_NAME -u GIT_AUTHOR_EMAIL -u GIT_COMMITTER_NAME -u GIT_COMMITTER_EMAIL
a=$(author "$t")
[ "$a" = "Local User <local@example.com>" ] \
  && pass "case 1: local git config authors when GIT_AUTHOR_* unset" \
  || fail "case 1: author='$a' (expected 'Local User <local@example.com>')"
rm -rf "$t"

# --- Case 2: explicit GIT_AUTHOR_* wins over local config (CI behavior) ---
t=$(new_repo)
git -C "$t" config user.name "Local User"
git -C "$t" config user.email "local@example.com"
commit_in "$t" GIT_AUTHOR_NAME="Issue Author" GIT_AUTHOR_EMAIL="ci@example.com"
a=$(author "$t")
[ "$a" = "Issue Author <ci@example.com>" ] \
  && pass "case 2: explicit GIT_AUTHOR_* wins" \
  || fail "case 2: author='$a' (expected 'Issue Author <ci@example.com>')"
rm -rf "$t"

# --- Case 3: nothing configured → "Scout" last-resort fallback ---
t=$(new_repo)
commit_in "$t" -u GIT_AUTHOR_NAME -u GIT_AUTHOR_EMAIL -u GIT_COMMITTER_NAME -u GIT_COMMITTER_EMAIL
a=$(author "$t")
[ "$a" = "Scout <scout@users.noreply.github.com>" ] \
  && pass "case 3: falls back to Scout when no identity configured" \
  || fail "case 3: author='$a' (expected 'Scout <scout@users.noreply.github.com>')"
rm -rf "$t"

echo ""
echo "Results: $PASS passed, $FAIL failed"
[ "$FAIL" = "0" ] && exit 0 || { printf '%s\n' "${FAIL_MSGS[@]}"; exit 1; }
