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

# setup_tmp: tmpdir with bare atlas-remote.git (1 initial commit on main)
# and a working clone at atlas-checkout/ with a staged artifact.
# Echoes the tmpdir path.
setup_tmp() {
  local tmp; tmp=$(mktemp -d)
  git -c init.defaultBranch=main init -q "$tmp/seed"
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

# remote_main_has_msg <remote.git> <grep-pattern>
remote_main_has_msg() {
  git --git-dir="$1" log main --format=%s 2>/dev/null | grep -q "$2"
}

# add_remote_commit <tmp> <path> <content> <msg>
# Pushes a new commit onto bare atlas-remote.git's main via a side clone.
add_remote_commit() {
  local tmp="$1" path="$2" content="$3" msg="$4"
  local side; side=$(mktemp -d)
  git clone -q "$tmp/atlas-remote.git" "$side/clone"
  mkdir -p "$(dirname "$side/clone/$path")"
  printf '%s\n' "$content" > "$side/clone/$path"
  git -C "$side/clone" add .
  git -C "$side/clone" -c user.name=other -c user.email=o@o commit -q -m "$msg"
  git -C "$side/clone" push -q origin main
  rm -rf "$side"
}

echo "Testing publish.sh..."

# --- Case 1: clean main, first push wins ---
tmp=$(setup_tmp)
run_publish "$tmp"
if [ "$RC" = "0" ] && remote_main_has_msg "$tmp/atlas-remote.git" "research: 2026-04-23 test" \
   && ! remote_has_branch "$tmp/atlas-remote.git" "scout/2026-04-23-test"; then
  pass "case 1: clean push lands on main"
else
  fail "case 1: rc=$RC, log: $(publish_log "$tmp")"
fi
rm -rf "$tmp"

# --- Case 2: remote has unrelated commit, rebase + retry wins ---
tmp=$(setup_tmp)
add_remote_commit "$tmp" "unrelated.md" "hi" "unrelated: side commit"
run_publish "$tmp"
if [ "$RC" = "0" ] \
   && remote_main_has_msg "$tmp/atlas-remote.git" "research: 2026-04-23 test" \
   && remote_main_has_msg "$tmp/atlas-remote.git" "unrelated: side commit" \
   && ! remote_has_branch "$tmp/atlas-remote.git" "scout/2026-04-23-test"; then
  pass "case 2: rebase + retry lands both commits on main"
else
  fail "case 2: rc=$RC, log: $(publish_log "$tmp")"
fi
rm -rf "$tmp"

# --- Case 3: rebase conflict → branch pushed + compare URL ---
tmp=$(setup_tmp)
add_remote_commit "$tmp" "_research/2026-04-23-test/index.md" "# conflicting" "conflict: same path"
run_publish "$tmp"
expected_url="https://github.com/test/atlas/compare/main...scout/2026-04-23-test?expand=1"
if [ "$RC" = "0" ] \
   && ! remote_main_has_msg "$tmp/atlas-remote.git" "research: 2026-04-23 test" \
   && remote_has_branch "$tmp/atlas-remote.git" "scout/2026-04-23-test" \
   && grep -qF "$expected_url" "$tmp/publish.log"; then
  pass "case 3: rebase conflict falls back to branch + compare URL"
else
  fail "case 3: rc=$RC, log: $(publish_log "$tmp")"
fi
rm -rf "$tmp"

# --- Case 4: all pushes to main rejected → fallback to branch ---
tmp=$(setup_tmp)
# pre-receive hook rejects every push to main with non-ff-looking text,
# accepts everything else (so the scout/... branch push succeeds).
cat > "$tmp/atlas-remote.git/hooks/pre-receive" <<'HOOK'
#!/usr/bin/env bash
while read _ _ ref; do
  if [ "$ref" = "refs/heads/main" ]; then
    echo "rejected (fetch first)" >&2
    exit 1
  fi
done
exit 0
HOOK
chmod +x "$tmp/atlas-remote.git/hooks/pre-receive"
run_publish "$tmp"
expected_url="https://github.com/test/atlas/compare/main...scout/2026-04-23-test?expand=1"
if [ "$RC" = "0" ] \
   && ! remote_main_has_msg "$tmp/atlas-remote.git" "research: 2026-04-23 test" \
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

# --- Case 7: mixed-success expedition surfaces failed children in SOFT_FAIL_LOG ---
tmp=$(setup_tmp)
PARENT="$tmp/atlas-checkout/_research/2026-04-23-test"
mkdir -p "$PARENT/a" "$PARENT/b"
cat > "$PARENT/a/index.md" <<MD
---
status: success
title: A
---
ok
MD
cat > "$PARENT/b/index.md" <<MD
---
status: failed
failure_reason: hard timeout
title: B
---
placeholder
MD
SOFT_LOG="$tmp/soft.log"
( cd "$tmp" && env \
    ATLAS_REPO="git@github.com-atlas:test/atlas.git" \
    DATE="2026-04-23" SLUG="test" TOPIC="test topic" \
    GH_TOKEN="" GH_REPO="" ISSUE_NUMBER="" \
    SOFT_FAIL_LOG="$SOFT_LOG" \
    RESEARCH_DIR="$PARENT" \
    bash "$SCRIPT" >"$tmp/publish.log" 2>&1 )
RC=$?
if [ "$RC" = "0" ] && [ -s "$SOFT_LOG" ] && grep -q '^- `b`: hard timeout' "$SOFT_LOG"; then
  pass "case 7: failed child surfaced in SOFT_FAIL_LOG"
else
  fail "case 7: rc=$RC, soft.log: $(cat "$SOFT_LOG" 2>/dev/null), publish.log: $(publish_log "$tmp")"
fi
rm -rf "$tmp"

# --- Case 8: gh issue close is never called after publish ---
# Issue lifecycle moved: issue stays open after publish, closes only after
# views ship (Task 8). Verify gh issue close is not invoked even when
# ISSUE_NUMBER / GH_TOKEN / GH_REPO are all set.
tmp=$(setup_tmp)
mkdir -p "$tmp/bin"
cat > "$tmp/bin/gh" <<'STUB'
#!/usr/bin/env bash
if [ "$1" = "issue" ] && [ "$2" = "close" ]; then
  echo "UNEXPECTED: gh issue close was called" >&2
  exit 1
fi
exit 0
STUB
chmod +x "$tmp/bin/gh"
( cd "$tmp" && env \
    PATH="$tmp/bin:$PATH" \
    ATLAS_REPO="git@github.com-atlas:test/atlas.git" \
    DATE="2026-04-23" SLUG="test" TOPIC="test topic" \
    GH_TOKEN="x" GH_REPO="test/atlas" ISSUE_NUMBER="1" \
    bash "$SCRIPT" >"$tmp/publish.log" 2>&1 )
RC=$?
if [ "$RC" = "0" ] && ! grep -qF "UNEXPECTED" "$tmp/publish.log"; then
  pass "case 8: gh issue close is not called after publish"
else
  fail "case 8: rc=$RC, log: $(publish_log "$tmp")"
fi
rm -rf "$tmp"

# --- Case 9: local git identity authors the commit when GIT_AUTHOR_NAME unset ---
# Local /scout runs don't set GIT_AUTHOR_NAME; the commit should be attributed to
# the user's own git identity, not the "Scout" CI fallback.
tmp=$(setup_tmp)
git -C "$tmp/atlas-checkout" config user.name "Local User"
git -C "$tmp/atlas-checkout" config user.email "local@example.com"
( cd "$tmp" && env -u GIT_AUTHOR_NAME -u GIT_AUTHOR_EMAIL \
    ATLAS_REPO="git@github.com-atlas:test/atlas.git" \
    DATE="2026-04-23" SLUG="test" TOPIC="test topic" \
    GH_TOKEN="" GH_REPO="" ISSUE_NUMBER="" \
    bash "$SCRIPT" >"$tmp/publish.log" 2>&1 )
RC=$?
author="$(git --git-dir="$tmp/atlas-remote.git" log main -1 --format='%an <%ae>')"
if [ "$RC" = "0" ] && [ "$author" = "Local User <local@example.com>" ]; then
  pass "case 9: local git identity authors local-run commits"
else
  fail "case 9: rc=$RC author='$author' (expected 'Local User <local@example.com>'), log: $(publish_log "$tmp")"
fi
rm -rf "$tmp"

# --- Case 10: explicit GIT_AUTHOR_NAME still wins (CI behavior preserved) ---
tmp=$(setup_tmp)
git -C "$tmp/atlas-checkout" config user.name "Local User"
git -C "$tmp/atlas-checkout" config user.email "local@example.com"
( cd "$tmp" && env \
    ATLAS_REPO="git@github.com-atlas:test/atlas.git" \
    DATE="2026-04-23" SLUG="test" TOPIC="test topic" \
    GH_TOKEN="" GH_REPO="" ISSUE_NUMBER="" \
    GIT_AUTHOR_NAME="Issue Author" GIT_AUTHOR_EMAIL="ci@example.com" \
    bash "$SCRIPT" >"$tmp/publish.log" 2>&1 )
RC=$?
author="$(git --git-dir="$tmp/atlas-remote.git" log main -1 --format='%an <%ae>')"
if [ "$RC" = "0" ] && [ "$author" = "Issue Author <ci@example.com>" ]; then
  pass "case 10: explicit GIT_AUTHOR_NAME wins (CI)"
else
  fail "case 10: rc=$RC author='$author' (expected 'Issue Author <ci@example.com>'), log: $(publish_log "$tmp")"
fi
rm -rf "$tmp"

# --- push from a non-main branch lands on origin/main (worktree case) ---
WORK="$(mktemp -d)"
WT_REMOTE="$WORK/wt-remote.git"; git init -q --bare "$WT_REMOTE"
WT_SRC="$WORK/wt-src"; git clone -q "$WT_REMOTE" "$WT_SRC"
( cd "$WT_SRC" && git -c user.email=t@t -c user.name=t commit -q --allow-empty -m seed \
  && git push -q origin HEAD:main && git checkout -q -b scout/2026-06-02-x \
  && echo hi > f.txt && git add -A && git -c user.email=t@t -c user.name=t commit -qm work )
( cd "$WT_SRC" && source "$REPO_ROOT/scripts/lib-publish.sh" && try_push >/dev/null 2>&1 )
landed="$(git --git-dir="$WT_REMOTE" cat-file -e refs/heads/main:f.txt && echo yes)"
[ "$landed" = yes ] && pass "try_push HEAD->main from feature branch" || fail "try_push did not land on main"
rm -rf "$WORK"

echo ""
echo "Results: $PASS passed, $FAIL failed"
[ "$FAIL" = "0" ] && exit 0 || exit 1
