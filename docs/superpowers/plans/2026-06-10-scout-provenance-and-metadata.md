# /scout Provenance Issue + Reliable Metadata — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Make local `/scout` expeditions recoverable and metadata-complete — a closed GitHub provenance issue carrying the verbatim prompt, plus deterministic `model`/`duration_sec`/`cost_usd` stamping that no longer depends on agent compliance.

**Architecture:** Two small deterministic helper scripts (`local-issue.sh`, `inject-run-metadata.sh`) that the agent-driven `scout.md` calls — mirroring how `scout.md` already uses `inject_cover.sh` for covers. All GitHub plumbing is non-fatal. A one-off backfill heals the existing Southern Vietnam expedition.

**Tech Stack:** Bash, `gh` CLI (stored auth), `jq`, `awk`. Tests are standalone bash scripts under `scout/tests/` following the repo's `pass`/`fail` harness.

**Working directory:** the `scout` repo root (`.../Scout+Atlas/scout`). The backfill task (Task 4) edits the sibling `atlas` repo.

---

### Task 1: `local-issue.sh` — create/close the provenance issue

**Files:**
- Create: `scripts/local-issue.sh`
- Test: `tests/test_local_issue.sh`

- [ ] **Step 1: Write the failing test**

Create `tests/test_local_issue.sh`:

```bash
#!/usr/bin/env bash
# Tests for scripts/local-issue.sh — provenance issue helper.
REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
PASS=0; FAIL=0
declare -a FAIL_MSGS
pass() { PASS=$((PASS + 1)); echo "  PASS: $1"; }
fail() { FAIL_MSGS+=("$1"); FAIL=$((FAIL + 1)); echo "  FAIL: $1"; }

echo "Testing local-issue.sh..."
TMP=$(mktemp -d)
mkdir -p "$TMP/scoutdir" "$TMP/bin"

# A scout checkout whose origin remote determines the target repo.
git -C "$TMP/scoutdir" init -q
git -C "$TMP/scoutdir" remote add origin git@github.com:Laoujin/Scout.git

# Stub gh: log argv; on create echo a realistic issue URL and dump the body file.
GH_LOG="$TMP/gh.log"; GH_BODY="$TMP/gh.body"
cat > "$TMP/bin/gh" <<STUB
#!/usr/bin/env bash
echo "\$*" >> "$GH_LOG"
if [ "\$1 \$2" = "issue create" ]; then
  while [ \$# -gt 0 ]; do [ "\$1" = "--body-file" ] && { cp "\$2" "$GH_BODY"; }; shift; done
  [ "\${GH_FAIL:-0}" = "1" ] && exit 1
  echo "https://github.com/Laoujin/Scout/issues/77"
fi
exit 0
STUB
chmod +x "$TMP/bin/gh"

PROMPT="$TMP/prompt.txt"
printf 'Build a complete first-visit guide to Hoi An.\nScope: our first-ever trip.\n' > "$PROMPT"

# --- open: creates against the derived repo with verbatim body, prints number ---
NUM="$(PATH="$TMP/bin:$PATH" SCOUT_DIR="$TMP/scoutdir" \
       bash "$REPO_ROOT/scripts/local-issue.sh" open "Hoi An guide" "$PROMPT")"
[ "$NUM" = "77" ] && pass "open prints parsed issue number" || fail "open number='$NUM' (want 77)"
grep -q -- "--repo Laoujin/Scout" "$GH_LOG" && pass "create targets repo from remote" || fail "wrong/no repo: $(cat "$GH_LOG")"
grep -q -- "--title Hoi An guide" "$GH_LOG" && pass "create passes title" || fail "no title in: $(cat "$GH_LOG")"
diff -q "$PROMPT" "$GH_BODY" >/dev/null 2>&1 && pass "issue body is the verbatim prompt" || fail "body not verbatim"

# --- close: comments Published then closes ---
: > "$GH_LOG"
PATH="$TMP/bin:$PATH" SCOUT_DIR="$TMP/scoutdir" \
  bash "$REPO_ROOT/scripts/local-issue.sh" close 77 "https://laoujin.github.io/Atlas/research/x/"
grep -q "issue comment 77 --repo Laoujin/Scout --body Published: https://laoujin.github.io/Atlas/research/x/" "$GH_LOG" \
  && pass "close comments the Published URL" || fail "no Published comment: $(cat "$GH_LOG")"
grep -q "issue close 77" "$GH_LOG" && pass "close closes the issue" || fail "issue not closed: $(cat "$GH_LOG")"

# --- non-fatal: gh create failure yields empty number, exit 0 ---
set +e
NUM2="$(PATH="$TMP/bin:$PATH" SCOUT_DIR="$TMP/scoutdir" GH_FAIL=1 \
        bash "$REPO_ROOT/scripts/local-issue.sh" open "T" "$PROMPT")"; RC=$?
set -e
[ "$RC" = "0" ] && pass "open exits 0 on gh failure" || fail "open exit=$RC on gh failure"
[ -z "$NUM2" ] && pass "open prints empty number on gh failure" || fail "open printed '$NUM2' on failure"

# --- non-fatal: close with empty number is a no-op ---
: > "$GH_LOG"
PATH="$TMP/bin:$PATH" SCOUT_DIR="$TMP/scoutdir" \
  bash "$REPO_ROOT/scripts/local-issue.sh" close "" "url"
[ ! -s "$GH_LOG" ] && pass "close with empty number does nothing" || fail "close ran gh: $(cat "$GH_LOG")"

rm -rf "$TMP"
echo
echo "Results: $PASS passed, $FAIL failed"
if [ $FAIL -gt 0 ]; then printf '  %s\n' "${FAIL_MSGS[@]}"; exit 1; fi
```

- [ ] **Step 2: Run test to verify it fails**

Run: `bash tests/test_local_issue.sh`
Expected: FAIL — `scripts/local-issue.sh` does not exist (`bash: .../local-issue.sh: No such file or directory`).

- [ ] **Step 3: Write minimal implementation**

Create `scripts/local-issue.sh`:

```bash
#!/usr/bin/env bash
# Deterministic GitHub-issue helper for the local /scout flow: opens a provenance
# issue carrying the verbatim originating prompt, and later comments the published
# URL + closes it. EVERY gh failure is non-fatal — research/publish must never
# block on issue plumbing. The target repo is derived from $SCOUT_DIR's origin
# remote; auth is gh's stored credentials (no token env needed).
#
# Usage:
#   ISSUE=$(SCOUT_DIR=<dir> bash local-issue.sh open "<title>" <prompt-file>)
#   SCOUT_DIR=<dir> bash local-issue.sh close "<num>" "<url>"
set -uo pipefail   # deliberately NOT -e: gh errors are handled, not fatal

SCOUT_DIR="${SCOUT_DIR:-$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)}"

# owner/repo from the origin remote. Handles SSH, HTTPS, and host-alias forms by
# dropping .git, turning ':' into '/', then taking the last two path segments.
_repo_slug() {
  local url
  url="$(git -C "$SCOUT_DIR" remote get-url origin 2>/dev/null)" || return 1
  [ -n "$url" ] || return 1
  url="${url%.git}"; url="${url//:/\/}"
  local repo rest owner
  repo="${url##*/}"; rest="${url%/*}"; owner="${rest##*/}"
  [ -n "$owner" ] && [ -n "$repo" ] || return 1
  printf '%s/%s' "$owner" "$repo"
}

cmd_open() {
  local title="$1" body_file="$2" repo num
  repo="$(_repo_slug)" || { echo "[local-issue] no origin remote; skipping issue" >&2; return 0; }
  [ -f "$body_file" ] || { echo "[local-issue] prompt file not found: $body_file" >&2; return 0; }
  num="$(gh issue create --repo "$repo" --title "$title" --body-file "$body_file" 2>/dev/null \
         | grep -oE '[0-9]+$' | tail -1)"
  if [ -n "$num" ]; then printf '%s\n' "$num"; else echo "[local-issue] issue create failed; continuing" >&2; fi
}

cmd_close() {
  local num="$1" url="$2" repo
  [ -n "$num" ] || { echo "[local-issue] no issue number; skipping close" >&2; return 0; }
  repo="$(_repo_slug)" || return 0
  gh issue comment "$num" --repo "$repo" --body "Published: $url" 2>/dev/null \
    || echo "[local-issue] comment failed; continuing" >&2
  gh issue close "$num" --repo "$repo" 2>/dev/null \
    || echo "[local-issue] close failed; continuing" >&2
}

case "${1:-}" in
  open)  shift; cmd_open "$@" ;;
  close) shift; cmd_close "$@" ;;
  *) echo "usage: local-issue.sh {open <title> <prompt-file> | close <num> <url>}" >&2; exit 2 ;;
esac
```

Then: `chmod +x scripts/local-issue.sh`

- [ ] **Step 4: Run test to verify it passes**

Run: `bash tests/test_local_issue.sh`
Expected: PASS — `Results: 8 passed, 0 failed`.

- [ ] **Step 5: Commit**

```bash
chmod +x scripts/local-issue.sh tests/test_local_issue.sh
git add scripts/local-issue.sh tests/test_local_issue.sh
git commit -m "Add local-issue.sh: provenance issue for local /scout runs"
```

---

### Task 2: `inject-run-metadata.sh` — deterministic frontmatter stamping

**Files:**
- Create: `scripts/inject-run-metadata.sh`
- Test: `tests/test_inject_run_metadata.sh`

- [ ] **Step 1: Write the failing test**

Create `tests/test_inject_run_metadata.sh`:

```bash
#!/usr/bin/env bash
# Tests for scripts/inject-run-metadata.sh — deterministic metadata stamping.
REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
PASS=0; FAIL=0
declare -a FAIL_MSGS
pass() { PASS=$((PASS + 1)); echo "  PASS: $1"; }
fail() { FAIL_MSGS+=("$1"); FAIL=$((FAIL + 1)); echo "  FAIL: $1"; }
fm() { awk -v k="$2" '/^---$/{n++} n==1 && $0 ~ "^"k":"{sub("^"k":[[:space:]]*","");print;exit}' "$1"; }

echo "Testing inject-run-metadata.sh..."
TMP=$(mktemp -d)
P="$TMP/parent"; mkdir -p "$P/a" "$P/b"

cat > "$P/index.md" <<'MD'
---
layout: expedition
title: Parent
synthesis: true
---
body
MD
cat > "$P/a/index.md" <<'MD'
---
title: A
citations: 5
---
child a
MD
cat > "$P/b/index.md" <<'MD'
---
title: B
citations: 7
---
child b
MD
cat > "$P/manifest.json" <<'JSON'
[
  {"slug":"a","title":"A","depth":"deep","status":"success","start":100,"end":250},
  {"slug":"b","title":"B","depth":"survey","status":"success","start":110,"end":300}
]
JSON

MODEL="Opus 4.8" ISSUE=42 bash "$REPO_ROOT/scripts/inject-run-metadata.sh" "$P"

# Parent
[ "$(fm "$P/index.md" model)" = '"Opus 4.8"' ] && pass "parent model stamped" || fail "parent model='$(fm "$P/index.md" model)'"
[ "$(fm "$P/index.md" cost_usd)" = '"sub"' ] && pass "parent cost_usd=sub" || fail "parent cost='$(fm "$P/index.md" cost_usd)'"
[ "$(fm "$P/index.md" issue)" = '42' ] && pass "parent issue stamped" || fail "parent issue='$(fm "$P/index.md" issue)'"
[ "$(fm "$P/index.md" duration_sec)" = '200' ] && pass "parent duration=wall-clock (200)" || fail "parent dur='$(fm "$P/index.md" duration_sec)'"

# Children — duration from manifest end-start; model+cost stamped; NO issue
[ "$(fm "$P/a/index.md" duration_sec)" = '150' ] && pass "child a duration=150" || fail "a dur='$(fm "$P/a/index.md" duration_sec)'"
[ "$(fm "$P/b/index.md" duration_sec)" = '190' ] && pass "child b duration=190" || fail "b dur='$(fm "$P/b/index.md" duration_sec)'"
[ "$(fm "$P/a/index.md" model)" = '"Opus 4.8"' ] && pass "child a model stamped" || fail "a model missing"
[ "$(fm "$P/a/index.md" cost_usd)" = '"sub"' ] && pass "child a cost=sub" || fail "a cost missing"
[ -z "$(fm "$P/a/index.md" issue)" ] && pass "child a has NO issue (sub-exempt)" || fail "a issue leaked"

# Idempotency: pre-existing value preserved; re-run is a no-op
cat > "$P/c.md" <<'MD'
---
title: C
model: "Sonnet 4.6"
duration_sec: 999
---
c
MD
MODEL="Opus 4.8" bash "$REPO_ROOT/scripts/inject-run-metadata.sh" "$P" >/dev/null
# stamp again on the parent dir; existing parent values must be untouched
before="$(cat "$P/index.md")"
MODEL="Sonnet 4.6" ISSUE=99 bash "$REPO_ROOT/scripts/inject-run-metadata.sh" "$P" >/dev/null
[ "$(cat "$P/index.md")" = "$before" ] && pass "re-run is a no-op (no overwrite)" || fail "re-run mutated parent"

# Single-pass (no manifest): DURATION env stamps parent
S="$TMP/single"; mkdir -p "$S"
cat > "$S/index.md" <<'MD'
---
title: Single
---
body
MD
MODEL="Opus 4.8" DURATION=321 bash "$REPO_ROOT/scripts/inject-run-metadata.sh" "$S"
[ "$(fm "$S/index.md" duration_sec)" = '321' ] && pass "single-pass duration from DURATION env" || fail "single dur='$(fm "$S/index.md" duration_sec)'"

rm -rf "$TMP"
echo
echo "Results: $PASS passed, $FAIL failed"
if [ $FAIL -gt 0 ]; then printf '  %s\n' "${FAIL_MSGS[@]}"; exit 1; fi
```

- [ ] **Step 2: Run test to verify it fails**

Run: `bash tests/test_inject_run_metadata.sh`
Expected: FAIL — script does not exist.

- [ ] **Step 3: Write minimal implementation**

Create `scripts/inject-run-metadata.sh`:

```bash
#!/usr/bin/env bash
# Deterministically stamp model / duration_sec / cost_usd (+ issue on the parent)
# into a /scout expedition's frontmatter — agent-independent, mirroring
# inject_cover.sh. Idempotent: inserts a field only when absent, never overwrites.
# Child duration comes from manifest.json (end-start); parent duration is the
# manifest wall-clock (max end - min start), or the DURATION env for single-pass.
#
# Usage: MODEL="Opus 4.8" [COST=sub] [ISSUE=42] [DURATION=<sec>] \
#          inject-run-metadata.sh <research-dir>
set -euo pipefail
DIR="${1:?usage: inject-run-metadata.sh <research-dir>}"
MODEL="${MODEL:?MODEL is required (friendly label, e.g. \"Opus 4.8\")}"
COST="${COST:-sub}"
ISSUE="${ISSUE:-}"
DURATION="${DURATION:-}"
command -v jq >/dev/null 2>&1 || { echo "inject-run-metadata: jq required" >&2; exit 1; }

# Insert "key: value" before the closing frontmatter delimiter, iff key is absent
# from the frontmatter block. No-op when already present. Mirrors backfill-metadata.sh.
_stamp() {
  local file="$1" key="$2" value="$3" end tmp
  [ -f "$file" ] || return 0
  if awk -v k="$key" '
        /^---[[:space:]]*$/ { if (++n==2) exit }
        n==1 && $0 ~ "^"k":" { found=1; exit }
        END { exit !found }' "$file"; then
    return 0   # already present
  fi
  end=$(awk '/^---$/{n++; if(n==2){print NR; exit}}' "$file")
  [ -n "$end" ] || return 0
  tmp="$(mktemp)"
  awk -v end="$end" -v line="$key: $value" 'NR==end{print line} {print}' "$file" > "$tmp"
  mv "$tmp" "$file"
}

_artifact() {
  local d="$1"
  [ -f "$d/index.md" ]   && { printf '%s' "$d/index.md";   return; }
  [ -f "$d/index.html" ] && { printf '%s' "$d/index.html"; return; }
}

MANIFEST="$DIR/manifest.json"

# --- Parent ---
P="$(_artifact "$DIR")"
if [ -n "$P" ]; then
  _stamp "$P" model "\"$MODEL\""
  _stamp "$P" cost_usd "\"$COST\""
  [ -n "$ISSUE" ] && _stamp "$P" issue "$ISSUE"
  if [ -f "$MANIFEST" ]; then
    wall="$(jq -r '([.[].end]|max) - ([.[].start]|min)' "$MANIFEST" 2>/dev/null || true)"
    [ -n "$wall" ] && [ "$wall" != "null" ] && _stamp "$P" duration_sec "$wall"
  elif [ -n "$DURATION" ]; then
    _stamp "$P" duration_sec "$DURATION"
  fi
fi

# --- Children (manifest order; model/cost/duration each) ---
if [ -f "$MANIFEST" ]; then
  while IFS=$'\t' read -r slug dur; do
    [ -n "$slug" ] || continue
    C="$(_artifact "$DIR/$slug")"
    [ -n "$C" ] || continue
    _stamp "$C" model "\"$MODEL\""
    _stamp "$C" cost_usd "\"$COST\""
    _stamp "$C" duration_sec "$dur"
  done < <(jq -r '.[] | "\(.slug)\t\(.end - .start)"' "$MANIFEST")
fi
```

Then: `chmod +x scripts/inject-run-metadata.sh`

- [ ] **Step 4: Run test to verify it passes**

Run: `bash tests/test_inject_run_metadata.sh`
Expected: PASS — `Results: 12 passed, 0 failed`.

- [ ] **Step 5: Commit**

```bash
chmod +x scripts/inject-run-metadata.sh tests/test_inject_run_metadata.sh
git add scripts/inject-run-metadata.sh tests/test_inject_run_metadata.sh
git commit -m "Add inject-run-metadata.sh: deterministic model/duration/cost stamping"
```

---

### Task 3: Wire the helpers into `scout.md`

**Files:**
- Modify: `.claude/commands/scout.md`

No automated test (it's the slash-command playbook); verified by `grep` checks. Make the three edits below exactly.

- [ ] **Step 1: Capture the verbatim prompt in Step 1**

In `.claude/commands/scout.md`, find the Step 1 block:

```
## Step 1 — Topic & options

If `$ARGUMENTS` is non-empty use it as the topic; else ask in chat (plain message).
Then call `AskUserQuestion` once:
```

Replace with:

```
## Step 1 — Topic & options

If `$ARGUMENTS` is non-empty use it as the topic; else ask in chat (plain message).
**Save the raw topic input verbatim** (the original pasted prompt, *before* Step 2
sharpens it) to a tempfile — `RAW_PROMPT_FILE=$(mktemp)` then write the exact text
into it. This is the issue body in Step 6.
Then call `AskUserQuestion` once:
```

- [ ] **Step 2: Stop making child/single agents responsible for the three fields**

Find in Step 4 (expedition child dispatch):

```
It must write `<child dir>/index.{md,html}` with full frontmatter — including
`model: "<MODEL>"`, `duration_sec: <its end − start epoch seconds>`, and
`cost_usd: "sub"` (mirrors what `inject_cost.sh` adds in the CI flow) — and return:
status, the artifact path, a one-line summary, and its start/end epoch seconds.
```

Replace with:

```
It must write `<child dir>/index.{md,html}` with content frontmatter (title, tags,
summary, citations, reading_time_min) and return: status, the artifact path, a
one-line summary, and its start/end epoch seconds. **Do not** ask the child to
stamp `model` / `duration_sec` / `cost_usd` — those are stamped deterministically
in Step 6 via `inject-run-metadata.sh` (agents drop them unreliably).
```

Find in Step 5 single-pass:

```
**Single-pass:** dispatch `scout-illustrator` for the single artifact
(`RESEARCH_DIR=$PARENT_DIR`), and add `model: "<MODEL>"`, `duration_sec`, and
`cost_usd: "sub"` to its frontmatter. No `manifest.json`, no `children:`.
```

Replace with:

```
**Single-pass:** dispatch `scout-illustrator` for the single artifact
(`RESEARCH_DIR=$PARENT_DIR`). `model` / `duration_sec` / `cost_usd` are stamped in
Step 6 via `inject-run-metadata.sh` (pass `DURATION=<now − START_TS>`). No
`manifest.json`, no `children:`.
```

Also remove the now-stale `cost_usd: "sub"` clause from the expedition Step 5.3 line so it reads (find):

```
   reading_time_min for successes — read from each child's frontmatter, else count
   its `citations*.jsonl`), `cover: cover.svg` only if step 1 wrote it,
   `duration_sec: <now − START_TS>`, `cost_usd: "sub"`, and 200–600 words of
```

Replace with:

```
   reading_time_min for successes — read from each child's frontmatter, else count
   its `citations*.jsonl`), `cover: cover.svg` only if step 1 wrote it, and
   200–600 words of
```

- [ ] **Step 3: Add issue + metadata wiring to Step 6**

In `.claude/commands/scout.md`, find the end of Step 6 — the block that runs `publish.sh`:

```
```
cd "$SCOUT_DIR" && ATLAS_REPO="<atlas_repo>" SLUG="<slug>" DATE="<date>" \
  TOPIC="<brief title>" bash scripts/publish.sh
```

It commits + pushes `atlas-checkout/` to Atlas `main` and prints
`Published: <url>` — surface that URL to the user.
```

Replace with:

```
```
cd "$SCOUT_DIR" && ATLAS_REPO="<atlas_repo>" SLUG="<slug>" DATE="<date>" \
  TOPIC="<brief title>" bash scripts/publish.sh
```

It commits + pushes `atlas-checkout/` to Atlas `main` and prints `Published: <url>`.

**Then, in this exact order (all non-fatal — a gh/network failure must not undo a
successful publish):**

1. Open the provenance issue with the verbatim prompt and stamp metadata BEFORE
   `publish.sh` so `issue:` is swept into the same commit. Move these two lines to
   run *just before* the `publish.sh` call above:
   ```
   ISSUE=$(SCOUT_DIR="$SCOUT_DIR" bash scripts/local-issue.sh open "<brief title>" "$RAW_PROMPT_FILE")
   MODEL="<friendly session model label, e.g. Opus 4.8>" ISSUE="$ISSUE" \
     bash scripts/inject-run-metadata.sh "$PARENT_DIR"
   ```
   For single-pass also pass `DURATION="$(( $(date +%s) - START_TS ))"` on the
   `inject-run-metadata.sh` line.
2. After `publish.sh` prints the URL, comment + close the issue:
   ```
   SCOUT_DIR="$SCOUT_DIR" bash scripts/local-issue.sh close "$ISSUE" "<published url>"
   ```

Surface the `Published: <url>` and the issue link to the user.
```

- [ ] **Step 4: Verify the edits**

Run:
```bash
grep -c "RAW_PROMPT_FILE" .claude/commands/scout.md          # expect >= 2
grep -c "inject-run-metadata.sh" .claude/commands/scout.md   # expect >= 2
grep -c "local-issue.sh" .claude/commands/scout.md           # expect >= 2
grep -c 'cost_usd: "sub"' .claude/commands/scout.md          # expect 0 (no longer agent-stamped)
```
Expected: first three ≥ 2, last = 0.

- [ ] **Step 5: Commit**

```bash
git add .claude/commands/scout.md
git commit -m "Wire local /scout to stamp metadata + open provenance issue"
```

---

### Task 4: Backfill the Southern Vietnam expedition

**Files:**
- Modify (atlas working tree): `atlas/research/2026-06-10-a-first-visit-guide-to-southern-vietnam/<7 children>/index.md`

This is a one-off data heal, not TDD. Runs from the `scout` repo root; edits the sibling `atlas` checkout.

- [ ] **Step 1: Backfill the children's metadata**

Run:
```bash
cd ../atlas    # the atlas repo (sibling of scout)
MODEL="Opus 4.8" bash ../scout/scripts/inject-run-metadata.sh \
  research/2026-06-10-a-first-visit-guide-to-southern-vietnam
```
Expected: the 7 children gain `model: "Opus 4.8"`, `cost_usd: "sub"`, and a
`duration_sec` from their manifest entry. The parent is already complete, so it is
left untouched (idempotent).

- [ ] **Step 2: Verify triage is clean for this expedition**

Run:
```bash
cd ..    # back to Scout+Atlas root
python3 scout/skills/scout-triage/scan.py atlas/research 2>&1 \
  | grep -c "southern-vietnam"
```
Expected: `0` (no findings reference the expedition).

Spot-check a child:
```bash
sed -n '1,14p' atlas/research/2026-06-10-a-first-visit-guide-to-southern-vietnam/eat-southern-vietnam/index.md
```
Expected: frontmatter now contains `model: "Opus 4.8"`, `duration_sec: 542`, `cost_usd: "sub"`.

- [ ] **Step 3: Commit the atlas changes**

```bash
git -C atlas add research/2026-06-10-a-first-visit-guide-to-southern-vietnam
git -C atlas commit -m "Backfill model/duration/cost for southern-vietnam children"
```

---

### Task 5: Final verification

- [ ] **Step 1: Run the full scout test suite**

Run: `cd scout && for t in tests/test_*.sh; do echo "### $t"; bash "$t" >/tmp/o 2>&1 || { echo FAIL; cat /tmp/o; }; tail -1 /tmp/o; done`
Expected: every suite ends `0 failed`; in particular `test_local_issue.sh`, `test_inject_run_metadata.sh`, and the existing `test_run_decompose_*` suites pass.

- [ ] **Step 2: Confirm no stray placeholders in scout.md**

Run: `grep -nE "TBD|TODO|FIXME" .claude/commands/scout.md` — expected: no output.

---

## Notes for the implementer

- **Push / PR:** the user commits and pushes the `scout` and `atlas` repos to
  `main` themselves (per their workflow). Do NOT push without asking.
- **Retro-issue for Vietnam:** optional and out of scope for this plan; if wanted,
  run `local-issue.sh open` with the `_travelling/vietnam/` source as the body,
  then re-run `inject-run-metadata.sh` with `ISSUE=<n>` on the parent, then `close`.
- The `START_TS` referenced in single-pass duration is parsed from
  `local-setup.sh` output in `scout.md` Step 3 (already present).
