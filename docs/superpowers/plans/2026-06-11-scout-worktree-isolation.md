# Scout Worktree Isolation Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Give every local `/scout` run its own git worktree off a registered Atlas checkout, so parallel runs never clobber each other and the destructive `rm -rf atlas-checkout` is gone.

**Architecture:** One long-lived local Atlas checkout (registered once in `~/.scout/atlas`) is the shared object store. Each run does `git worktree add` on a fresh `scout/<date>-<slug>` branch based on freshly-fetched `origin/main`, works there, publishes by pushing `HEAD:main`, then removes its worktree on success. A small `atlas-config.sh` helper holds the testable resolve/save/validate logic; the interactive first-run prompts live in `scout.md`.

**Tech Stack:** Bash, git worktrees, the existing hermetic `tests/test_*.sh` harness (no bats).

**Spec:** `docs/superpowers/specs/2026-06-11-scout-worktree-isolation-design.md`

---

## File Structure

| File | Responsibility | Change |
|---|---|---|
| `scripts/atlas-config.sh` | Resolve/validate/persist the Atlas checkout path + worktree-home path; detect sibling; wire `.git/info/exclude`. Non-interactive, unit-testable core of discovery. | **Create** |
| `scripts/local-setup.sh` | Fetch + `worktree add` per run; print `ATLAS_DIR/WORKTREE/BRANCH/…`. No more clone/`rm -rf`/`ATLAS_REPO`. | **Rewrite** |
| `scripts/publish.sh` | Commit + push `HEAD:main` from the worktree; derive URL from `origin`; remove worktree + branch on success. | **Modify** |
| `scripts/lib-publish.sh` | `try_push` pushes `HEAD:main` instead of `main`. | **Modify** |
| `.claude/commands/scout.md` | First-run bootstrap (AskUserQuestion); thread `WORKTREE/BRANCH/ATLAS_DIR`; drop `atlas-checkout` references. | **Modify** |
| `tests/test_atlas_config.sh` | Cover the helper. | **Create** |
| `tests/test_local_setup.sh` | Rewrite for the worktree flow. | **Rewrite** |
| `tests/test_publish.sh` | Extend for worktree push + cleanup. | **Modify** |
| `tests/test_scout_md_worktree.sh` | Guard: `scout.md` has no `atlas-checkout` refs and uses the new helper. | **Create** |

Conventions (from existing tests): each test is `bash tests/test_X.sh`, prints `Results: P passed, F failed`, exits non-zero on any fail. Hermetic: `WORK="$(mktemp -d)"; trap 'rm -rf "$WORK"' EXIT`. `atlas-config.sh` reads its config dir from `SCOUT_CONFIG_DIR` (default `$HOME/.scout`) so tests point it at a throwaway dir.

---

## Task 1: `lib-publish.sh` — push `HEAD:main`

The worktree's HEAD is `scout/<slug>`, not `main`, so `git push origin main` would push the wrong ref. `HEAD:main` is correct from any branch and identical when HEAD is already `main` (CI), so it is backward-compatible.

**Files:**
- Modify: `scripts/lib-publish.sh:24` (the `try_push` body)
- Test: `tests/test_publish.sh` (a focused case added here; full cleanup case in Task 4)

- [ ] **Step 1: Write the failing test** — append to `tests/test_publish.sh` a case that publishes from a non-`main` branch and asserts `origin/main` advanced. Add before the final `Results:` block:

```bash
# --- push from a non-main branch lands on origin/main (worktree case) ---
WT_REMOTE="$WORK/wt-remote.git"; git init -q --bare "$WT_REMOTE"
WT_SRC="$WORK/wt-src"; git clone -q "$WT_REMOTE" "$WT_SRC"
( cd "$WT_SRC" && git -c user.email=t@t -c user.name=t commit -q --allow-empty -m seed \
  && git push -q origin HEAD:main && git checkout -q -b scout/2026-06-02-x \
  && echo hi > f.txt && git add -A && git -c user.email=t@t -c user.name=t commit -qm work )
( cd "$WT_SRC" && source "$REPO_ROOT/scripts/lib-publish.sh" && try_push >/dev/null 2>&1 )
landed="$(git --git-dir="$WT_REMOTE" cat-file -e refs/heads/main:f.txt && echo yes)"
[ "$landed" = yes ] && pass "try_push HEAD->main from feature branch" || fail "try_push did not land on main"
```

- [ ] **Step 2: Run test to verify it fails**

Run: `bash tests/test_publish.sh`
Expected: FAIL line `try_push did not land on main` (old code pushes local `main`, which has no `f.txt`), non-zero exit.

- [ ] **Step 3: Make the minimal change** — in `scripts/lib-publish.sh`, change the push line inside `try_push`:

```bash
  err=$(git push origin HEAD:main 2>&1) || rc=$?
```

(Only `main` → `HEAD:main` on that one line. Leave `fetch origin main` and `rebase origin/main` untouched.)

- [ ] **Step 4: Run test to verify it passes**

Run: `bash tests/test_publish.sh`
Expected: PASS `try_push HEAD->main from feature branch`; all prior cases still pass.

- [ ] **Step 5: Commit**

```bash
git add scripts/lib-publish.sh tests/test_publish.sh
git commit -m "fix(publish): push HEAD:main so worktree branches land on main"
```

---

## Task 2: `atlas-config.sh` — discovery/persistence helper

Non-interactive resolve/save/validate. `scout.md` calls these around its `AskUserQuestion`.

**Files:**
- Create: `scripts/atlas-config.sh`
- Test: `tests/test_atlas_config.sh`

- [ ] **Step 1: Write the failing test** — create `tests/test_atlas_config.sh`:

```bash
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

# detect-sibling: scout/../atlas valid
SCOUTD="$WORK/scout"; mkdir -p "$SCOUTD"; ln -s "$ATLAS" "$WORK/atlas2" 2>/dev/null || true
# Build a layout where <scoutdir>/../atlas is the valid checkout:
LAY="$WORK/lay"; mkdir -p "$LAY"; cp -r "$ATLAS" "$LAY/atlas"; mkdir -p "$LAY/scout"
OUT="$(bash "$AC" detect-sibling "$LAY/scout")"
[ "$OUT" = "$LAY/atlas" ] && pass "detect-sibling finds ../atlas" || fail "detect-sibling: $OUT"

# save-worktrees plain -> persists abs path, creates dir
WT="$WORK/wts"
OUT="$(bash "$AC" save-worktrees "$WT")"
[ -d "$WT" ] && [ "$(cat "$SCOUT_CONFIG_DIR/worktrees-dir")" = "$OUT" ] && pass "save-worktrees persists" || fail "save-worktrees failed"

# save-worktrees inside-atlas -> appends worktrees/ to .git/info/exclude (idempotent)
mkdir -p "$ATLAS/.git/info"
bash "$AC" save-worktrees "$ATLAS/worktrees" "$ATLAS" >/dev/null
bash "$AC" save-worktrees "$ATLAS/worktrees" "$ATLAS" >/dev/null
n="$(grep -cxF 'worktrees/' "$ATLAS/.git/info/exclude")"
[ "$n" -eq 1 ] && pass "exclude wired once (idempotent)" || fail "exclude count=$n"

echo; echo "Results: $PASS passed, $FAIL failed"
[ $FAIL -gt 0 ] && { printf '  %s\n' "${FAIL_MSGS[@]}"; exit 1; } || exit 0
```

- [ ] **Step 2: Run test to verify it fails**

Run: `bash tests/test_atlas_config.sh`
Expected: FAIL — `scripts/atlas-config.sh` does not exist yet (errors on every case), non-zero exit.

- [ ] **Step 3: Write minimal implementation** — create `scripts/atlas-config.sh`:

```bash
#!/usr/bin/env bash
# Resolve / validate / persist the local Atlas checkout and worktree-home paths
# for the interactive /scout flow. All persisted paths are absolute. The config
# dir is $SCOUT_CONFIG_DIR (default ~/.scout) so tests can redirect it.
set -uo pipefail
CFG_DIR="${SCOUT_CONFIG_DIR:-$HOME/.scout}"
ATLAS_PTR="$CFG_DIR/atlas"
WT_PTR="$CFG_DIR/worktrees-dir"

_abs() { ( cd "$1" 2>/dev/null && pwd ); }

# Valid = a git working tree that has an 'origin' remote (the publish target).
_valid_atlas() {
  local d="$1"
  [ -n "$d" ] || return 1
  git -C "$d" rev-parse --is-inside-work-tree >/dev/null 2>&1 || return 1
  git -C "$d" remote get-url origin >/dev/null 2>&1 || return 1
}

cmd_resolve_atlas() {
  [ -f "$ATLAS_PTR" ] || return 3
  local d; d="$(cat "$ATLAS_PTR" 2>/dev/null)"
  _valid_atlas "$d" || return 3
  printf '%s\n' "$d"
}

cmd_save_atlas() {
  local d; d="$(_abs "${1:-}")" || true
  [ -n "$d" ] || { echo "atlas-config: path not found: ${1:-}" >&2; return 2; }
  _valid_atlas "$d" || { echo "atlas-config: not a git checkout with an 'origin' remote: $d" >&2; return 2; }
  mkdir -p "$CFG_DIR"; printf '%s\n' "$d" > "$ATLAS_PTR"; printf '%s\n' "$d"
}

cmd_detect_sibling() {
  local s; s="$(_abs "${1:?usage: detect-sibling <scout-dir>}/../atlas")" || return 1
  _valid_atlas "$s" || return 1
  printf '%s\n' "$s"
}

cmd_resolve_worktrees() {
  [ -f "$WT_PTR" ] || return 3
  local d; d="$(cat "$WT_PTR" 2>/dev/null)"; [ -n "$d" ] || return 3
  printf '%s\n' "$d"
}

cmd_save_worktrees() {
  local p="${1:?usage: save-worktrees <path> [atlas-dir-if-inside]}" inside="${2:-}"
  mkdir -p "$p"; local d; d="$(_abs "$p")"
  mkdir -p "$CFG_DIR"; printf '%s\n' "$d" > "$WT_PTR"
  if [ -n "$inside" ]; then
    local ex="$inside/.git/info/exclude"
    mkdir -p "$inside/.git/info"
    grep -qxF 'worktrees/' "$ex" 2>/dev/null || printf 'worktrees/\n' >> "$ex"
  fi
  printf '%s\n' "$d"
}

case "${1:-}" in
  resolve-atlas)     shift; cmd_resolve_atlas "$@" ;;
  save-atlas)        shift; cmd_save_atlas "$@" ;;
  detect-sibling)    shift; cmd_detect_sibling "$@" ;;
  resolve-worktrees) shift; cmd_resolve_worktrees "$@" ;;
  save-worktrees)    shift; cmd_save_worktrees "$@" ;;
  *) echo "usage: atlas-config.sh {resolve-atlas | save-atlas <path> | detect-sibling <scout-dir> | resolve-worktrees | save-worktrees <path> [atlas-dir]}" >&2; exit 2 ;;
esac
```

- [ ] **Step 4: Run test to verify it passes**

Run: `bash tests/test_atlas_config.sh`
Expected: PASS all cases; `Results: 9 passed, 0 failed`.

- [ ] **Step 5: Commit**

```bash
git add scripts/atlas-config.sh tests/test_atlas_config.sh
git commit -m "feat(scout): add atlas-config helper for checkout/worktree discovery"
```

---

## Task 3: `local-setup.sh` — worktree instead of clone

**Files:**
- Rewrite: `scripts/local-setup.sh`
- Rewrite: `tests/test_local_setup.sh`

- [ ] **Step 1: Write the failing test** — replace `tests/test_local_setup.sh` with:

```bash
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
[ -d "$WTREE/.git" ] || [ -f "$WTREE/.git" ] && pass "worktree is a git tree" || fail "worktree not a git tree"
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
```

- [ ] **Step 2: Run test to verify it fails**

Run: `bash tests/test_local_setup.sh`
Expected: FAIL — old `local-setup.sh` prints `ATLAS_REPO=`/`SCOUT_DIR=` and clones `atlas-checkout`; no `WORKTREE`/`BRANCH`. Non-zero exit.

- [ ] **Step 3: Write the implementation** — replace `scripts/local-setup.sh` with:

```bash
#!/usr/bin/env bash
# Per-run setup for the interactive (subscription) Scout flow. Given a registered
# Atlas checkout (ATLAS_DIR) and a worktree home (WT_HOME), fetch origin/main and
# add an isolated git worktree on a fresh scout/<date>-<slug> branch. No clone, no
# rm -rf: parallel runs get independent worktrees and never clobber each other.
set -euo pipefail

TITLE="${1:?usage: local-setup.sh <title>}"
ATLAS_DIR="${ATLAS_DIR:?ATLAS_DIR is required (registered Atlas checkout; see atlas-config.sh)}"
WT_HOME="${WT_HOME:?WT_HOME is required (worktree home dir; see atlas-config.sh)}"
DATE="${DATE:-$(date +%F)}"

# Resolve SCOUT_DIR for slug.sh: explicit pointer, else walk up to the playbook.
if [ -f "$HOME/.scout/dir" ]; then
  SCOUT_DIR="$(cat "$HOME/.scout/dir")"
else
  d="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
  while [ "$d" != "/" ] && [ ! -f "$d/skills/scout/SKILL.md" ]; do d="$(dirname "$d")"; done
  [ -f "$d/skills/scout/SKILL.md" ] || { echo "Error: cannot locate SCOUT_DIR" >&2; exit 1; }
  SCOUT_DIR="$d"
fi
# shellcheck source=scripts/slug.sh
source "$SCOUT_DIR/scripts/slug.sh"

git -C "$ATLAS_DIR" worktree prune >/dev/null 2>&1 || true
git -C "$ATLAS_DIR" fetch origin main >/dev/null 2>&1 || {
  echo "Error: failed to fetch origin/main in $ATLAS_DIR" >&2; exit 1; }

# Unique slug vs what's published (origin/main), live branches, and live worktrees.
BASE_SLUG="$(slugify "$TITLE")"
SLUG="$BASE_SLUG"; n=2
while git -C "$ATLAS_DIR" cat-file -e "origin/main:research/${DATE}-${SLUG}" 2>/dev/null \
   || git -C "$ATLAS_DIR" show-ref --verify --quiet "refs/heads/scout/${DATE}-${SLUG}" \
   || [ -e "$WT_HOME/${DATE}-${SLUG}" ]; do
  SLUG="${BASE_SLUG}-${n}"; n=$((n + 1))
done

BRANCH="scout/${DATE}-${SLUG}"
WORKTREE="$WT_HOME/${DATE}-${SLUG}"
mkdir -p "$WT_HOME"
git -C "$ATLAS_DIR" worktree add -b "$BRANCH" "$WORKTREE" origin/main >/dev/null 2>&1 || {
  echo "Error: git worktree add failed for $WORKTREE" >&2; exit 1; }

PARENT_DIR="$WORKTREE/research/${DATE}-${SLUG}"
mkdir -p "$PARENT_DIR"

printf 'ATLAS_DIR=%s\n' "$ATLAS_DIR"
printf 'WORKTREE=%s\n' "$WORKTREE"
printf 'BRANCH=%s\n' "$BRANCH"
printf 'DATE=%s\n' "$DATE"
printf 'SLUG=%s\n' "$SLUG"
printf 'PARENT_DIR=%s\n' "$PARENT_DIR"
printf 'START_TS=%s\n' "$(date +%s)"

if [ -n "${SUB_TOPICS_TSV:-}" ]; then
  while IFS=$'\t' read -r ctitle cdepth; do
    [ -n "$ctitle" ] || continue
    cslug="$(slugify "$ctitle")"
    mkdir -p "$PARENT_DIR/$cslug"
    printf 'CHILD=%s\t%s\n' "$cslug" "$PARENT_DIR/$cslug"
  done <<< "$SUB_TOPICS_TSV"
fi
```

- [ ] **Step 4: Run test to verify it passes**

Run: `bash tests/test_local_setup.sh`
Expected: PASS all; `Results: 15 passed, 0 failed`.

- [ ] **Step 5: Commit**

```bash
git add scripts/local-setup.sh tests/test_local_setup.sh
git commit -m "feat(scout): isolate each local run in its own git worktree"
```

---

## Task 4: `publish.sh` — push from worktree, then clean up

**Files:**
- Modify: `scripts/publish.sh`
- Test: `tests/test_publish.sh` (add the worktree publish+cleanup case)

- [ ] **Step 1: Write the failing test** — append to `tests/test_publish.sh` (before the final `Results:` block):

```bash
# --- worktree publish: pushes to origin/main, removes worktree + branch ---
PR2="$WORK/p2-remote.git"; git init -q --bare "$PR2"
AT2="$WORK/p2-atlas"; git clone -q "$PR2" "$AT2"
( cd "$AT2" && mkdir -p research && echo s > research/.keep && git add -A \
  && git -c user.email=t@t -c user.name=t commit -qm seed && git push -q origin HEAD:main )
git -C "$AT2" remote set-url origin "git@github.com:Laoujin/Atlas.git"   # exercise URL parse
git -C "$AT2" remote add pushtgt "$PR2"   # actual push target for the test
# Point publish at a real bare via a temporary origin swap:
git -C "$AT2" remote set-url origin "$PR2"
WT2="$WORK/p2-wts/2026-06-02-place"; mkdir -p "$WORK/p2-wts"
git -C "$AT2" worktree add -q -b scout/2026-06-02-place "$WT2" origin/main
mkdir -p "$WT2/research/2026-06-02-place"
echo body > "$WT2/research/2026-06-02-place/index.md"
OUT="$(cd "$AT2" && WORKTREE="$WT2" BRANCH="scout/2026-06-02-place" ATLAS_DIR="$AT2" \
      SLUG=2026-06-02-place DATE=2026-06-02 TOPIC=t bash "$REPO_ROOT/scripts/publish.sh" 2>&1)"
echo "$OUT" | grep -q '^Published: https://' && pass "publish prints URL" || fail "no Published URL: $OUT"
git --git-dir="$PR2" cat-file -e "refs/heads/main:research/2026-06-02-place/index.md" 2>/dev/null \
  && pass "artifact on origin/main" || fail "artifact not pushed"
git -C "$AT2" worktree list | grep -q "$WT2" && fail "worktree not removed" || pass "worktree removed on success"
git -C "$AT2" show-ref --verify --quiet refs/heads/scout/2026-06-02-place \
  && fail "branch not deleted" || pass "branch deleted on success"
```

- [ ] **Step 2: Run test to verify it fails**

Run: `bash tests/test_publish.sh`
Expected: FAIL — current `publish.sh` does `cd atlas-checkout` (no such dir here) and never removes a worktree. Non-zero exit.

- [ ] **Step 3: Edit `scripts/publish.sh`.** Replace the head section (lines ~11–21, the `ATLAS_DIR="atlas-checkout"` block and `cd "$ATLAS_DIR"`) with worktree inputs:

```bash
WORKTREE="${WORKTREE:?WORKTREE is required (per-run worktree path from local-setup.sh)}"
BRANCH="${BRANCH:?BRANCH is required (scout/<date>-<slug>)}"
ATLAS_DIR="${ATLAS_DIR:?ATLAS_DIR is required (registered Atlas checkout)}"
TOPIC="${TOPIC:-research}"
SLUG="${SLUG:-unknown}"
DATE="${DATE:-$(date +%F)}"

if [ ! -e "$WORKTREE/.git" ]; then
  echo "Error: $WORKTREE is not a git worktree." >&2
  exit 1
fi
cd "$WORKTREE"
```

Replace the Pages-URL derivation block (the `atlas_slug="${ATLAS_REPO#*:}"` lines) with an origin-based parse that handles SSH, host-alias SSH, and HTTPS:

```bash
origin_url="$(git -C "$WORKTREE" remote get-url origin)"
u="${origin_url%.git}"
if [[ "$u" == http*://* ]]; then path="${u#*://}"; path="${path#*/}"; else path="${u##*:}"; fi
owner="${path%%/*}"; repo="${path##*/}"
ATLAS_URL="https://${owner,,}.github.io/${repo}/research/${DATE}-${SLUG}/"
echo "Published: ${ATLAS_URL}"
```

Then, immediately after the `echo "Published: ..."` line, add cleanup-on-success (place it before the existing optional `SOFT_FAIL_LOG`/issue-comment blocks, which remain unchanged):

```bash
# Success: retire this run's worktree + branch (non-fatal — publish already done).
git -C "$ATLAS_DIR" worktree remove "$WORKTREE" 2>/dev/null \
  || echo "publish.sh: could not remove worktree $WORKTREE (remove it manually)" >&2
git -C "$ATLAS_DIR" branch -D "$BRANCH" >/dev/null 2>&1 || true
```

Also update the `publish_path "$COMMIT_MSG" "." "$BRANCH"` call site: it stays the same (stages `.`, commits, pushes `HEAD:main` via the Task-1 change, PR-fallback branch is `$BRANCH`). Update the header comment on line 2 from `atlas-checkout/_research/` to `the run's worktree`.

- [ ] **Step 4: Run test to verify it passes**

Run: `bash tests/test_publish.sh`
Expected: PASS the new cases plus the Task-1 case and all originals; `Results: N passed, 0 failed`.

- [ ] **Step 5: Commit**

```bash
git add scripts/publish.sh tests/test_publish.sh
git commit -m "feat(scout): publish from per-run worktree and clean it up on success"
```

---

## Task 5: `scout.md` — first-run bootstrap + threading

`scout.md` is the interactive command. The `AskUserQuestion` prompts can't be unit-tested, so the test is a static guard: no `atlas-checkout` references remain and the new helper + worktree vars are referenced.

**Files:**
- Modify: `.claude/commands/scout.md`
- Test: `tests/test_scout_md_worktree.sh`

- [ ] **Step 1: Write the failing test** — create `tests/test_scout_md_worktree.sh`:

```bash
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
```

- [ ] **Step 2: Run test to verify it fails**

Run: `bash tests/test_scout_md_worktree.sh`
Expected: FAIL — `still references atlas-checkout`, `missing atlas-config.sh`, etc.

- [ ] **Step 3: Edit `.claude/commands/scout.md`.** Make these changes:

(a) Add a new **Step 0 — Resolve Atlas checkout & worktree home** before Step 1:

```markdown
## Step 0 — Resolve Atlas checkout & worktree home

Locate `atlas-config.sh` (next to this command: `<scout>/scripts/atlas-config.sh`).

1. **Atlas checkout.** Run `bash <scout>/scripts/atlas-config.sh resolve-atlas`.
   - Exit 0 → use the printed absolute path as `ATLAS_DIR`.
   - Non-zero → first run. Call `AskUserQuestion` once. If
     `bash <scout>/scripts/atlas-config.sh detect-sibling <scout>` prints a path,
     offer it as the recommended option. Options:
     - **Use detected checkout** `<printed path>` (when present)
     - **Provide a path** to an existing Atlas checkout
     - **Clone fresh** into `~/.scout/atlas` (ask for the repo URL; default
       `git@github.com:Laoujin/Atlas`; `git clone` it, then continue)
     Persist with `bash <scout>/scripts/atlas-config.sh save-atlas "<chosen path>"`
     (it validates git + origin and stores the absolute path). Use its echo as `ATLAS_DIR`.
2. **Worktree home.** Run `bash <scout>/scripts/atlas-config.sh resolve-worktrees`.
   - Exit 0 → use the printed path as `WT_HOME`.
   - Non-zero → `AskUserQuestion` once. Options:
     - **`~/.scout/atlas-worktrees/`**
     - **Custom** — the user types a path
     - **`<ATLAS_DIR>/worktrees/`** (inside the checkout)
     For the inside-Atlas choice, persist with
     `save-worktrees "<ATLAS_DIR>/worktrees" "<ATLAS_DIR>"` (wires `.git/info/exclude`);
     otherwise `save-worktrees "<chosen path>"`. Use its echo as `WT_HOME`.

`ATLAS_DIR`'s `origin` remote is the publish target — there is no `ATLAS_REPO` anymore.
```

(b) In **Step 3 — Setup**, replace the `SUB_TOPICS_TSV=… bash <scout>/scripts/local-setup.sh` invocation so it passes the resolved vars and parses the new keys:

```markdown
Build `SUB_TOPICS_TSV` and run:

    ATLAS_DIR="<ATLAS_DIR>" WT_HOME="<WT_HOME>" SUB_TOPICS_TSV=$'…' \
      bash <scout>/scripts/local-setup.sh "<brief title>"

Parse its output for `ATLAS_DIR`, `WORKTREE`, `BRANCH`, `DATE`, `SLUG`,
`PARENT_DIR`, `START_TS`, and the `CHILD=<slug><TAB><dir>` lines.
```

(c) Replace the two `atlas-checkout` references later in the file:
- Series step: `"$SCOUT_DIR/atlas-checkout/_data/series.yml"` → `"$WORKTREE/_data/series.yml"`.
- Publish step: change the `add-to-series.sh` path the same way, and update the `publish.sh` invocation/description to pass the worktree:

```markdown
    cd "<scout>" && WORKTREE="<WORKTREE>" BRANCH="<BRANCH>" ATLAS_DIR="<ATLAS_DIR>" \
      SLUG="<slug>" DATE="<date>" TOPIC="<brief title>" bash scripts/publish.sh
```

  and change the sentence "It commits + pushes `atlas-checkout/` to Atlas `main`…" to
  "It commits + pushes the run's `WORKTREE` to Atlas `main` (as `HEAD:main`), then
  removes the worktree + branch on success, and prints `Published: <url>`."

- [ ] **Step 4: Run test to verify it passes**

Run: `bash tests/test_scout_md_worktree.sh`
Expected: PASS all four; `Results: 4 passed, 0 failed`.

- [ ] **Step 5: Commit**

```bash
git add .claude/commands/scout.md tests/test_scout_md_worktree.sh
git commit -m "docs(scout): bootstrap Atlas/worktree resolution; thread worktree through /scout"
```

---

## Task 6: Full regression + RUNBOOK note

**Files:**
- Modify: `_travelling/RUNBOOK.md` (the consuming repo's note that says `ATLAS_REPO=../atlas`)

- [ ] **Step 1: Run the whole suite**

Run: `for t in tests/test_*.sh; do echo "== $t =="; bash "$t" || echo "FAILED: $t"; done`
Expected: every script ends `… 0 failed`; no `FAILED:` lines. Pay attention to `test_run_decompose_*` and `test_commit_identity` — they exercise `lib-publish.sh`; they must still pass with the `HEAD:main` change (CI works on `main`, so identical).

- [ ] **Step 2: Update the RUNBOOK note** in `_travelling/RUNBOOK.md` — replace the `ATLAS_REPO=../atlas` guidance with the new model:

```markdown
- **Atlas location:** resolved once and stored in `~/.scout/atlas` (the registered
  local Atlas checkout; its `origin` is the publish target). First `/scout` run
  prompts for it. No `ATLAS_REPO` needed.
- **Isolation:** each run gets its own git worktree under the configured worktree
  home (`~/.scout/worktrees-dir`); parallel runs never clobber. No `rm -rf`.
```

- [ ] **Step 3: Commit**

```bash
git add _travelling/RUNBOOK.md
git commit -m "docs(runbook): document worktree-based Atlas resolution"
```

(Note: `_travelling/` is a separate repo from `scout/`. Run this commit from the `_travelling` working tree, the other steps from `scout/`.)

---

## Self-Review

**Spec coverage:**
- Worktree-per-run mechanism → Task 3. ✅
- `HEAD:main` push → Task 1. ✅
- Discovery/bootstrap (`~/.scout/atlas`, `~/.scout/worktrees-dir`, detect-sibling, three worktree-home options, `.git/info/exclude` wiring) → Task 2 (logic) + Task 5 (interactive prompts). ✅
- Publish + cleanup (remove worktree/branch on success, keep on failure) → Task 4. ✅
- `scout.md` threading + drop `atlas-checkout` → Task 5. ✅
- Origin-based URL parse (SSH/host-alias/HTTPS) → Task 4 Step 3, tested via the `git@github.com:` set-url in the test. ✅
- CI out of scope; RUNBOOK updated → Task 6. ✅

**Placeholder scan:** No TBD/TODO; every code step shows full code; every test step shows assertions and expected output. ✅

**Type/name consistency:** Output keys (`ATLAS_DIR`, `WORKTREE`, `BRANCH`, `PARENT_DIR`, `SLUG`, `DATE`, `START_TS`, `CHILD=`) are identical across `local-setup.sh` (Task 3), `publish.sh` inputs (Task 4), and `scout.md` (Task 5). Helper subcommands (`resolve-atlas`, `save-atlas`, `detect-sibling`, `resolve-worktrees`, `save-worktrees`) match between `atlas-config.sh` (Task 2) and `scout.md` (Task 5). `SCOUT_CONFIG_DIR` override used consistently in Task 2's test. ✅

**Failure-mode note:** Task 4's cleanup is non-fatal (publish already succeeded), and Task 3 leaves a failed run's worktree in place (distinct dated slug), so a kept worktree never blocks the next run.
