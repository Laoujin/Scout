#!/usr/bin/env bash
# Tests for scripts/publish.sh. Run: bash tests/test_publish.sh
#
# Uses local bare repos as a fake Atlas remote. No network, no real gh.
# GH_TOKEN is set empty so publish.sh's issue-comment block is skipped.

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SCRIPT="$REPO_ROOT/scripts/publish.sh"
FIXTURES="$REPO_ROOT/tests/fixtures/publish"

PASS=0
FAIL=0
declare -a FAIL_MSGS

pass() { PASS=$((PASS + 1)); echo "  PASS: $1"; }
fail() { FAIL_MSGS+=("$1"); FAIL=$((FAIL + 1)); echo "  FAIL: $1"; }

# setup_tmp: tmpdir with bare atlas-remote.git (1 initial commit on master)
# and a working clone at atlas-checkout/ with a staged artifact.
# Echoes the tmpdir path.
setup_tmp() {
  local tmp; tmp=$(mktemp -d)
  git -c init.defaultBranch=master init -q "$tmp/seed"
  git -C "$tmp/seed" -c user.name=seed -c user.email=s@s commit --allow-empty -q -m "init"
  git clone -q --bare "$tmp/seed" "$tmp/atlas-remote.git" 2>/dev/null
  rm -rf "$tmp/seed"
  git clone -q "$tmp/atlas-remote.git" "$tmp/atlas-checkout"
  mkdir -p "$tmp/atlas-checkout/_research/2026-04-23-test"
  echo "# test artifact" > "$tmp/atlas-checkout/_research/2026-04-23-test/index.md"
  echo "$tmp"
}

# run_publish: runs publish.sh with tmp as CWD and test env.
# Writes combined stdout+stderr to $tmp/publish.log; sets global RC.
RC=0
run_publish() {
  local tmp="$1"
  ( cd "$tmp" && env \
      ATLAS_REPO="git@github.com-atlas:test/atlas.git" \
      DATE="2026-04-23" \
      SLUG="test" \
      TOPIC="test topic" \
      GH_TOKEN="" \
      GH_REPO="" \
      ISSUE_NUMBER="" \
      bash "$SCRIPT" >"$tmp/publish.log" 2>&1 )
  RC=$?
}

# Read the log from the last run_publish.
publish_log() { cat "$1/publish.log"; }

# remote_has_branch <remote.git> <branch>
remote_has_branch() {
  git --git-dir="$1" show-ref --verify --quiet "refs/heads/$2"
}

# remote_master_has_msg <remote.git> <grep-pattern>
remote_master_has_msg() {
  git --git-dir="$1" log master --format=%s 2>/dev/null | grep -q "$2"
}

# add_remote_commit <tmp> <path> <content> <msg>
# Pushes a new commit onto bare atlas-remote.git's master via a side clone.
add_remote_commit() {
  local tmp="$1" path="$2" content="$3" msg="$4"
  local side; side=$(mktemp -d)
  git clone -q "$tmp/atlas-remote.git" "$side/clone"
  mkdir -p "$(dirname "$side/clone/$path")"
  printf '%s\n' "$content" > "$side/clone/$path"
  git -C "$side/clone" add .
  git -C "$side/clone" -c user.name=other -c user.email=o@o commit -q -m "$msg"
  git -C "$side/clone" push -q origin master
  rm -rf "$side"
}

echo "Testing publish.sh..."

# --- Case 1: clean master, first push wins ---
tmp=$(setup_tmp)
run_publish "$tmp"
if [ "$RC" = "0" ] && remote_master_has_msg "$tmp/atlas-remote.git" "research: 2026-04-23 test" \
   && ! remote_has_branch "$tmp/atlas-remote.git" "scout/2026-04-23-test"; then
  pass "case 1: clean push lands on master"
else
  fail "case 1: rc=$RC, log: $(publish_log "$tmp")"
fi
rm -rf "$tmp"

# --- Case 2: remote has unrelated commit, rebase + retry wins ---
tmp=$(setup_tmp)
add_remote_commit "$tmp" "unrelated.md" "hi" "unrelated: side commit"
run_publish "$tmp"
if [ "$RC" = "0" ] \
   && remote_master_has_msg "$tmp/atlas-remote.git" "research: 2026-04-23 test" \
   && remote_master_has_msg "$tmp/atlas-remote.git" "unrelated: side commit" \
   && ! remote_has_branch "$tmp/atlas-remote.git" "scout/2026-04-23-test"; then
  pass "case 2: rebase + retry lands both commits on master"
else
  fail "case 2: rc=$RC, log: $(publish_log "$tmp")"
fi
rm -rf "$tmp"

# --- Case 3: rebase conflict → branch pushed + compare URL ---
tmp=$(setup_tmp)
add_remote_commit "$tmp" "_research/2026-04-23-test/index.md" "# conflicting" "conflict: same path"
run_publish "$tmp"
expected_url="https://github.com/test/atlas/compare/master...scout/2026-04-23-test?expand=1"
if [ "$RC" = "0" ] \
   && ! remote_master_has_msg "$tmp/atlas-remote.git" "research: 2026-04-23 test" \
   && remote_has_branch "$tmp/atlas-remote.git" "scout/2026-04-23-test" \
   && grep -qF "$expected_url" "$tmp/publish.log"; then
  pass "case 3: rebase conflict falls back to branch + compare URL"
else
  fail "case 3: rc=$RC, log: $(publish_log "$tmp")"
fi
rm -rf "$tmp"

# --- Case 4: all pushes to master rejected → fallback to branch ---
tmp=$(setup_tmp)
# pre-receive hook rejects every push to master with non-ff-looking text,
# accepts everything else (so the scout/... branch push succeeds).
cat > "$tmp/atlas-remote.git/hooks/pre-receive" <<'HOOK'
#!/usr/bin/env bash
while read _ _ ref; do
  if [ "$ref" = "refs/heads/master" ]; then
    echo "rejected (fetch first)" >&2
    exit 1
  fi
done
exit 0
HOOK
chmod +x "$tmp/atlas-remote.git/hooks/pre-receive"
run_publish "$tmp"
expected_url="https://github.com/test/atlas/compare/master...scout/2026-04-23-test?expand=1"
if [ "$RC" = "0" ] \
   && ! remote_master_has_msg "$tmp/atlas-remote.git" "research: 2026-04-23 test" \
   && remote_has_branch "$tmp/atlas-remote.git" "scout/2026-04-23-test" \
   && grep -qF "$expected_url" "$tmp/publish.log"; then
  pass "case 4: 3 retries exhausted → branch pushed + compare URL"
else
  fail "case 4: rc=$RC, log: $(publish_log "$tmp")"
fi
rm -rf "$tmp"

# --- Case 6: is_non_ff helper matches real git stderr ---
if (
  # shellcheck source=scripts/lib-publish.sh
  source "$REPO_ROOT/scripts/lib-publish.sh"
  is_non_ff "$(cat "$FIXTURES/non_ff.stderr")" \
    && ! is_non_ff "$(cat "$FIXTURES/auth_fail.stderr")" \
    && ! is_non_ff ""
); then
  pass "case 6: is_non_ff matches non-ff only"
else
  fail "case 6: is_non_ff helper wrong or missing"
fi

# --- Case 5: bad remote URL (push fails, no fallback) ---
tmp=$(setup_tmp)
git -C "$tmp/atlas-checkout" remote set-url origin "$tmp/does-not-exist.git"
run_publish "$tmp"
if [ "$RC" != "0" ]; then
  pass "case 5: bad remote exits non-zero"
else
  fail "case 5: expected non-zero exit, got $RC, log: $(publish_log "$tmp")"
fi
rm -rf "$tmp"

echo ""
echo "Results: $PASS passed, $FAIL failed"
[ "$FAIL" = "0" ] && exit 0 || exit 1
