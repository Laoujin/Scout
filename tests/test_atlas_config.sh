#!/usr/bin/env bash
# Tests scripts/atlas-config.sh: resolve/save/validate atlas + worktree-home.
# Hermetic: SCOUT_CONFIG_DIR points at a throwaway dir (never the real ~/.scout).
REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
PASS=0; FAIL=0; declare -a FAIL_MSGS
pass() { PASS=$((PASS + 1)); echo "  PASS: $1"; }
fail() { FAIL_MSGS+=("$1"); FAIL=$((FAIL + 1)); echo "  FAIL: $1"; }
WORK="$(mktemp -d)"; trap 'rm -rf "$WORK"' EXIT
AC="$REPO_ROOT/scripts/atlas-config.sh"
export SCOUT_CONFIG_DIR="$WORK/cfg"

# A valid atlas checkout: a clone (so it has an origin remote).
REMOTE="$WORK/atlas.git"; git init -q --bare "$REMOTE"
ATLAS="$WORK/atlas"; git clone -q "$REMOTE" "$ATLAS"
( cd "$ATLAS" && git -c user.email=t@t -c user.name=t commit -q --allow-empty -m seed )

# A non-git dir (invalid).
NOGIT="$WORK/plain"; mkdir -p "$NOGIT"

# resolve-atlas before save -> exit 3
SCOUT_CONFIG_DIR="$SCOUT_CONFIG_DIR" bash "$AC" resolve-atlas >/dev/null 2>&1
[ $? -eq 3 ] && pass "resolve-atlas unset -> 3" || fail "resolve-atlas should exit 3 when unset"

# save-atlas valid -> prints absolute path, persists
OUT="$(bash "$AC" save-atlas "$ATLAS")"
[ "$OUT" = "$ATLAS" ] && pass "save-atlas echoes abs path" || fail "save-atlas wrong echo: $OUT"
[ "$(cat "$SCOUT_CONFIG_DIR/atlas")" = "$ATLAS" ] && pass "atlas pointer persisted" || fail "pointer not persisted"

# resolve-atlas after save -> prints path, exit 0
OUT="$(bash "$AC" resolve-atlas)"; rc=$?
[ $rc -eq 0 ] && [ "$OUT" = "$ATLAS" ] && pass "resolve-atlas returns saved" || fail "resolve-atlas after save failed"

# save-atlas invalid (no git) -> non-zero, clear error
if bash "$AC" save-atlas "$NOGIT" >/dev/null 2>"$WORK/e1"; then fail "save-atlas should reject non-git"; else
  grep -qi 'origin\|git' "$WORK/e1" && pass "save-atlas clear error" || fail "unclear error"; fi

# save-atlas with empty / missing path -> non-zero, must NOT save CWD
if bash "$AC" save-atlas "" >/dev/null 2>"$WORK/e2"; then fail "save-atlas '' should error"; else
  grep -qi 'path not found' "$WORK/e2" && pass "save-atlas '' clear error" || fail "save-atlas '' unclear error"; fi
if bash "$AC" save-atlas >/dev/null 2>"$WORK/e3"; then fail "save-atlas no-arg should error"; else
  pass "save-atlas no-arg errors"; fi

# detect-sibling: scout/../atlas valid
LAY="$WORK/lay"; mkdir -p "$LAY"; cp -r "$ATLAS" "$LAY/atlas"; mkdir -p "$LAY/scout"
OUT="$(bash "$AC" detect-sibling "$LAY/scout")"
[ "$OUT" = "$LAY/atlas" ] && pass "detect-sibling finds ../atlas" || fail "detect-sibling: $OUT"

# resolve-worktrees before save -> exit 3
bash "$AC" resolve-worktrees >/dev/null 2>&1
[ $? -eq 3 ] && pass "resolve-worktrees unset -> 3" || fail "resolve-worktrees should exit 3 when unset"

# save-worktrees plain -> persists abs path, creates dir
WT="$WORK/wts"
OUT="$(bash "$AC" save-worktrees "$WT")"
[ -d "$WT" ] && [ "$(cat "$SCOUT_CONFIG_DIR/worktrees-dir")" = "$OUT" ] && pass "save-worktrees persists" || fail "save-worktrees failed"

# resolve-worktrees after save -> prints saved path, exit 0
OUT="$(bash "$AC" resolve-worktrees)"; rc=$?
[ $rc -eq 0 ] && [ "$OUT" = "$WT" ] && pass "resolve-worktrees returns saved" || fail "resolve-worktrees after save failed"

# save-worktrees inside-atlas -> appends worktrees/ to .git/info/exclude (idempotent)
mkdir -p "$ATLAS/.git/info"
bash "$AC" save-worktrees "$ATLAS/worktrees" "$ATLAS" >/dev/null
bash "$AC" save-worktrees "$ATLAS/worktrees" "$ATLAS" >/dev/null
n="$(grep -cxF 'worktrees/' "$ATLAS/.git/info/exclude")"
[ "$n" -eq 1 ] && pass "exclude wired once (idempotent)" || fail "exclude count=$n"

echo; echo "Results: $PASS passed, $FAIL failed"
[ $FAIL -gt 0 ] && { printf '  %s\n' "${FAIL_MSGS[@]}"; exit 1; } || exit 0
