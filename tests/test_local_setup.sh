#!/usr/bin/env bash
# Tests scripts/local-setup.sh: fetches origin/main, adds a per-run worktree on
# a scout/<date>-<slug> branch, makes child dirs, prints env. Hermetic.
REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
PASS=0; FAIL=0; declare -a FAIL_MSGS
pass() { PASS=$((PASS + 1)); echo "  PASS: $1"; }
fail() { FAIL_MSGS+=("$1"); FAIL=$((FAIL + 1)); echo "  FAIL: $1"; }
WORK="$(mktemp -d)"; trap 'rm -rf "$WORK"' EXIT

# Throwaway SCOUT_DIR (local-setup only needs skills/scout/SKILL.md + slug.sh).
SCOUTD="$WORK/scout"; mkdir -p "$SCOUTD/skills/scout" "$SCOUTD/scripts"
touch "$SCOUTD/skills/scout/SKILL.md"
cp "$REPO_ROOT/scripts/slug.sh" "$SCOUTD/scripts/slug.sh"
FAKE_HOME="$WORK/home"; mkdir -p "$FAKE_HOME/.scout"; printf '%s\n' "$SCOUTD" > "$FAKE_HOME/.scout/dir"

# Registered Atlas checkout = a clone of a bare remote, seeded with research/.
REMOTE="$WORK/atlas.git"; git init -q --bare "$REMOTE"
ATLAS="$WORK/atlas"; git clone -q "$REMOTE" "$ATLAS"
( cd "$ATLAS" && mkdir -p research && echo seed > research/.keep && git add -A \
  && git -c user.email=t@t -c user.name=t commit -qm seed && git push -q origin HEAD:main )
WT_HOME="$WORK/wts"

run() { HOME="$FAKE_HOME" DATE=2026-06-02 ATLAS_DIR="$ATLAS" WT_HOME="$WT_HOME" \
        SUB_TOPICS_TSV="$1" bash "$REPO_ROOT/scripts/local-setup.sh" "$2"; }

OUT="$(run $'Routing angle\tdeep\nState angle\tsurvey' 'My Expedition Topic')"
echo "$OUT" | grep -q "^ATLAS_DIR=$ATLAS$" && pass "prints ATLAS_DIR" || fail "no ATLAS_DIR"
echo "$OUT" | grep -q '^BRANCH=scout/2026-06-02-my-expedition-topic$' && pass "prints BRANCH" || fail "no/bad BRANCH"
echo "$OUT" | grep -q '^SLUG=my-expedition-topic$' && pass "prints SLUG" || fail "no SLUG"
echo "$OUT" | grep -q '^START_TS=[0-9]\+$' && pass "prints START_TS" || fail "no START_TS"
WTREE="$(echo "$OUT" | sed -n 's/^WORKTREE=//p')"
[ "$WTREE" = "$WT_HOME/2026-06-02-my-expedition-topic" ] && pass "worktree path" || fail "bad worktree: $WTREE"
{ [ -d "$WTREE/.git" ] || [ -f "$WTREE/.git" ]; } && pass "worktree is a git tree" || fail "worktree not a git tree"
git -C "$ATLAS" worktree list | grep -q "$WTREE" && pass "worktree registered" || fail "worktree not registered"
PARENT="$(echo "$OUT" | sed -n 's/^PARENT_DIR=//p')"
case "$PARENT" in "$WTREE"/research/2026-06-02-my-expedition-topic) pass "parent dir" ;; *) fail "bad parent: $PARENT" ;; esac
[ -d "$PARENT/routing-angle" ] && pass "child dir created" || fail "missing child"
[ "$(echo "$OUT" | grep -c '^CHILD=')" -eq 2 ] && pass "two CHILD lines" || fail "expected 2 CHILD"
# No clobber: a SECOND run coexists (different worktree), first run's files survive.
echo marker > "$PARENT/keep.txt"
OUT2="$(run '' 'My Expedition Topic')"
WTREE2="$(echo "$OUT2" | sed -n 's/^WORKTREE=//p')"
[ "$WTREE2" != "$WTREE" ] && pass "second run distinct worktree" || fail "second run reused worktree"
echo "$OUT2" | sed -n 's/^SLUG=//p' | grep -q -- '-2$' && pass "second run unique slug -2" || fail "slug not uniquified"
[ -f "$PARENT/keep.txt" ] && pass "first run NOT clobbered" || fail "first run was clobbered"
# missing ATLAS_DIR -> error
if HOME="$FAKE_HOME" DATE=2026-06-02 WT_HOME="$WT_HOME" env -u ATLAS_DIR \
     bash "$REPO_ROOT/scripts/local-setup.sh" "X" >/dev/null 2>"$WORK/err"; then
  fail "should error without ATLAS_DIR"
else grep -qi 'ATLAS_DIR' "$WORK/err" && pass "clear ATLAS_DIR error" || fail "unclear error"; fi

echo; echo "Results: $PASS passed, $FAIL failed"
[ $FAIL -gt 0 ] && { printf '  %s\n' "${FAIL_MSGS[@]}"; exit 1; } || exit 0
