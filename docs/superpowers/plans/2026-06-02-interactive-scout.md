# Interactive `/scout` Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add a `/scout` slash command that runs a full Scout research — including parallel multi-angle expeditions — inside the interactive Claude Code session (subscription-billed, no `claude -p`), and rename the existing issue→runner command to `/scout-async`.

**Architecture:** The interactive command is a prompt that makes the session the orchestrator: it sharpens in chat, calls a new `scripts/local-setup.sh` to clone Atlas + make dirs, dispatches `scout-researcher`-style subagents (full `SKILL.md`) per sub-topic in parallel, dispatches `scout-illustrator` for a cover, synthesizes the parent per `synthesis.md`, then pushes via the existing `publish.sh`. `run.sh`/`run-decompose.sh` are untouched. A small compass-theme edit renders `cost_usd: "sub"` as "on subscription".

**Tech Stack:** Bash, awk/sed, git, Claude Code slash commands + subagents (`Agent` tool), Jekyll/Liquid (compass theme). Tests are standalone bash scripts under `tests/`.

**Repos touched:** `Atlas/compass` (submodule), `Atlas` (submodule bump), `Scout` (everything else). Paths below are relative to the **Scout** checkout unless prefixed `Atlas/`.

---

## File Structure

- `Atlas/compass/_layouts/research.html`, `Atlas/compass/_layouts/expedition.html` — cost-badge conditional for the `"sub"` sentinel.
- `.claude/commands/scout-async.md` — renamed from `commands/scout.md` (issue→runner; Format reverted).
- `.claude/commands/scout.md` — new interactive command (the orchestration prompt).
- `scripts/local-setup.sh` — new; resolve `SCOUT_DIR`/`ATLAS_REPO`, clone Atlas, make parent/child dirs, print `KEY=VALUE`.
- `install.sh` — install both commands (async = copy+substitute; interactive = symlink + write `~/.scout/dir`).
- `tests/test_local_setup.sh`, `tests/test_commands_present.sh` — new.
- `README.md`, `docs/OPERATE.md` — document the two commands.

**Run a single test:** `bash tests/<file>.sh` (exit 0 = pass). The harness is per-file pass/fail counters (see existing tests for the `pass()/fail()` shape).

---

## Task 1: compass cost-badge renders the `"sub"` sentinel

**Files:**
- Modify: `Atlas/compass/_layouts/research.html` (≈line 165)
- Modify: `Atlas/compass/_layouts/expedition.html` (≈line 113)

`compass` is a submodule with its own git repo. Land this first — otherwise a `cost_usd: "sub"` page renders a literal `$sub`.

- [ ] **Step 1: Edit `research.html`**

Replace:
```liquid
        {% if page.cost_usd %}<div class="pcell"><div class="lbl">Cost</div><div class="val">${{ page.cost_usd }}</div></div>{% endif %}
```
with:
```liquid
        {% if page.cost_usd == "sub" %}<div class="pcell"><div class="lbl">Cost</div><div class="val">on subscription</div></div>
        {% elsif page.cost_usd %}<div class="pcell"><div class="lbl">Cost</div><div class="val">${{ page.cost_usd }}</div></div>{% endif %}
```

- [ ] **Step 2: Edit `expedition.html`** — make the identical replacement at its cost line (≈113).

- [ ] **Step 3: Verify Liquid is balanced**

Run: `cd Atlas/compass && grep -c 'endif' _layouts/research.html _layouts/expedition.html`
Expected: counts increased by 0 (we replaced one `if/endif` with one `if/elsif/endif` — still one `endif` per block; the count is unchanged from before). Confirm visually that each edited block has exactly one `{% endif %}`.

- [ ] **Step 4: Commit compass, then bump the pointer in Atlas**

```bash
cd Atlas/compass
git add _layouts/research.html _layouts/expedition.html
git commit -m "research/expedition: render cost_usd \"sub\" as on subscription"
git push
cd ..   # now in Atlas
git add compass
git commit -m "bump compass: subscription cost badge"
git push
```
(If you don't have push rights set up here, commit locally and note the pointer bump is pending — the Scout work below is independent.)

---

## Task 2: Rename to `/scout-async` (revert the Format edit)

**Files:**
- Create: `.claude/commands/scout-async.md`
- Delete: `commands/scout.md`
- Modify: `tests/test_commands_present.sh` (created here, async assertions)

- [ ] **Step 1: Write the failing test**

Create `tests/test_commands_present.sh`:
```bash
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

# --- interactive (filled in Task 4) ---
[ -f "$INTER" ] && pass "interactive command exists" || fail "missing $INTER"
if [ -f "$INTER" ]; then
  grep -q 'allowed-tools:.*Agent' "$INTER" && pass "interactive allows Agent" || fail "interactive missing Agent tool"
  grep -q 'local-setup.sh' "$INTER" && pass "interactive calls local-setup.sh" || fail "interactive missing local-setup.sh"
fi

echo; echo "Results: $PASS passed, $FAIL failed"
if [ $FAIL -gt 0 ]; then printf '  %s\n' "${FAIL_MSGS[@]}"; exit 1; fi
```

- [ ] **Step 2: Run it to verify it fails**

Run: `bash tests/test_commands_present.sh`
Expected: FAIL — `missing …/.claude/commands/scout-async.md` and `old commands/scout.md should be gone`.

- [ ] **Step 3: Create `.claude/commands/scout-async.md`**

Create it with the committed (pre-Format) content, `description` updated, and **no Format** question:
```markdown
---
description: Open a Scout research Issue (async runner).
argument-hint: "[topic]"
allowed-tools: AskUserQuestion, Bash(gh issue create:*)
---

`$ARGUMENTS` is the research topic (free text, may be empty).

## Step 1 — Topic

If `$ARGUMENTS` is non-empty, use it verbatim as the topic. Otherwise ask the user for one in chat (plain message, not `AskUserQuestion` — topic is free text).

## Step 2 — Options

Call `AskUserQuestion` once with these two questions:

1. **Depth** (header `Depth`, single-select):
   - `survey` — 2-4 pages, balanced overview (Recommended)
   - `recon` — one-page decision brief
   - `expedition` — all angles, long-form
2. **Do a sharpening round-trip** (header `Sharpen`, single-select):
   - `Yes` — let Scout propose a sharpened prompt before researching (Recommended)
   - `No` — use my topic verbatim and start research

## Step 3 — Create the Issue

```
gh issue create --repo {{SCOUT_REPO}} \
  --title "[research] <truncate topic to ~60 chars>" \
  --label scout-research \
  --body "$(printf '### Topic\n\n%s\n\n### Depth\n\n%s\n\n### Options\n\n- [%s] Skip sharpening (use my topic verbatim)\n' "<topic>" "<depth>" "<x if sharpen=No else space>")"
```

Print the Issue URL. If sharpen is Yes, tell the user: "Scout will reply with a sharpened proposal in ~30s. Tick the **Start research** checkbox to publish, or reply with feedback for another proposal." If sharpen is No, tell the user the research job will kick off directly (5-30 min).

Do not poll. The sharpen step takes 10-30 seconds; the research step takes 5-30 minutes. The published artifact will appear at {{ATLAS_URL}}.
```

- [ ] **Step 4: Remove the old file**

Run: `git rm commands/scout.md` (this also drops the uncommitted Format edit).
Note: if `git rm` complains about the unstaged Format change, run `git checkout -- commands/scout.md` first, then `git rm commands/scout.md`.

- [ ] **Step 5: Run the test — async assertions pass, interactive still fails**

Run: `bash tests/test_commands_present.sh`
Expected: async asserts PASS; the two interactive asserts FAIL (`missing …/scout.md`). That's expected — Task 4 fills them.

- [ ] **Step 6: Commit**

```bash
git add .claude/commands/scout-async.md tests/test_commands_present.sh
git rm commands/scout.md
git commit -m "Rename /scout issue command to /scout-async (drop stray Format edit)"
```

---

## Task 3: `scripts/local-setup.sh` (clone Atlas, make dirs, print env)

**Files:**
- Create: `scripts/local-setup.sh`
- Create: `tests/test_local_setup.sh`

- [ ] **Step 1: Write the failing test**

Create `tests/test_local_setup.sh`:
```bash
#!/usr/bin/env bash
# Tests scripts/local-setup.sh: resolves ATLAS_REPO, clones, makes dirs, prints env.
REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
PASS=0; FAIL=0; declare -a FAIL_MSGS
pass() { PASS=$((PASS + 1)); echo "  PASS: $1"; }
fail() { FAIL_MSGS+=("$1"); FAIL=$((FAIL + 1)); echo "  FAIL: $1"; }

WORK="$(mktemp -d)"; trap 'rm -rf "$WORK"' EXIT

# Build a fake Atlas repo to clone.
FAKE_ATLAS="$WORK/atlas.git"
mkdir -p "$FAKE_ATLAS" && ( cd "$FAKE_ATLAS" && git init -q && mkdir -p research \
  && echo "seed" > research/.keep && git add -A \
  && git -c user.email=t@t -c user.name=t commit -qm seed )

run() { DATE=2026-06-02 ATLAS_REPO="$FAKE_ATLAS" SUB_TOPICS_TSV="$1" \
        bash "$REPO_ROOT/scripts/local-setup.sh" "$2"; }

# --- expedition: two sub-topics ---
OUT="$(run $'Routing angle\tdeep\nState angle\tsurvey' 'My Expedition Topic')"
echo "$OUT" | grep -q '^SCOUT_DIR=' && pass "prints SCOUT_DIR" || fail "no SCOUT_DIR"
echo "$OUT" | grep -q '^DATE=2026-06-02$' && pass "prints DATE" || fail "no DATE"
echo "$OUT" | grep -q '^START_TS=[0-9]\+$' && pass "prints START_TS" || fail "no START_TS"
PARENT="$(echo "$OUT" | sed -n 's/^PARENT_DIR=//p')"
case "$PARENT" in */research/2026-06-02-my-expedition-topic) pass "parent dir slug" ;; *) fail "bad parent: $PARENT" ;; esac
[ -d "$PARENT" ] && pass "parent dir created" || fail "parent not created"
[ "$(echo "$OUT" | grep -c '^CHILD=')" -eq 2 ] && pass "two CHILD lines" || fail "expected 2 CHILD lines"
[ -d "$PARENT/routing-angle" ] && pass "child dir 1 created" || fail "missing child 1"

# --- uniqueness: second run with same title → -2 ---
OUT2="$(run '' 'My Expedition Topic')"
echo "$OUT2" | sed -n 's/^PARENT_DIR=//p' | grep -q -- '-my-expedition-topic-2$' && pass "unique slug -2" || fail "slug not uniquified"

# --- missing ATLAS_REPO → error ---
if env -u ATLAS_REPO DATE=2026-06-02 bash "$REPO_ROOT/scripts/local-setup.sh" "X" >/dev/null 2>"$WORK/err"; then
  fail "should error without ATLAS_REPO"
else
  grep -qi 'ATLAS_REPO' "$WORK/err" && pass "clear ATLAS_REPO error" || fail "unclear error"
fi

echo; echo "Results: $PASS passed, $FAIL failed"
if [ $FAIL -gt 0 ]; then printf '  %s\n' "${FAIL_MSGS[@]}"; exit 1; fi
```

Note: this test runs `local-setup.sh` from inside the Scout repo, so its upward walk finds `skills/scout/SKILL.md` and resolves `SCOUT_DIR` to `$REPO_ROOT` (no `~/.scout/dir` needed). The clone writes `atlas-checkout/` into `$REPO_ROOT` — the test relies on `PARENT_DIR` being under there; cleanup of `atlas-checkout` is handled by the second run's `rm -rf` inside the script.

- [ ] **Step 2: Run it to verify it fails**

Run: `bash tests/test_local_setup.sh`
Expected: FAIL — `local-setup.sh: No such file or directory`.

- [ ] **Step 3: Write `scripts/local-setup.sh`**

```bash
#!/usr/bin/env bash
# Setup for an interactive (subscription) Scout run. Resolves SCOUT_DIR +
# ATLAS_REPO, clones Atlas fresh, computes a unique research dir, makes child
# dirs, and prints KEY=VALUE lines for the /scout command. No claude -p — the
# interactive session is the research agent.
set -euo pipefail

TITLE="${1:?usage: local-setup.sh <title>}"

# Resolve SCOUT_DIR: explicit pointer, else walk up to the playbook.
if [ -f "$HOME/.scout/dir" ]; then
  SCOUT_DIR="$(cat "$HOME/.scout/dir")"
else
  d="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
  while [ "$d" != "/" ] && [ ! -f "$d/skills/scout/SKILL.md" ]; do d="$(dirname "$d")"; done
  [ -f "$d/skills/scout/SKILL.md" ] || {
    echo "Error: cannot locate SCOUT_DIR (no skills/scout/SKILL.md above $(pwd) and no ~/.scout/dir)" >&2
    exit 1; }
  SCOUT_DIR="$d"
fi

# Resolve ATLAS_REPO: env override, else docker/.env, else error.
if [ -z "${ATLAS_REPO:-}" ] && [ -f "$SCOUT_DIR/docker/.env" ]; then
  ATLAS_REPO="$(grep -E '^ATLAS_REPO=' "$SCOUT_DIR/docker/.env" | head -1 | cut -d= -f2-)"
fi
[ -n "${ATLAS_REPO:-}" ] || {
  echo "Error: set ATLAS_REPO (env) or add it to \$SCOUT_DIR/docker/.env" >&2
  exit 1; }

DATE="${DATE:-$(date +%F)}"

cd "$SCOUT_DIR"
# shellcheck source=scripts/slug.sh
source "$SCOUT_DIR/scripts/slug.sh"

rm -rf atlas-checkout
git clone --depth=1 --filter=blob:none "$ATLAS_REPO" atlas-checkout >/dev/null 2>&1

BASE_SLUG="$(slugify "$TITLE")"
SLUG="$BASE_SLUG"; n=2
while [ -d "atlas-checkout/research/${DATE}-${SLUG}" ]; do
  SLUG="${BASE_SLUG}-${n}"; n=$((n + 1))
done
PARENT_DIR="$SCOUT_DIR/atlas-checkout/research/${DATE}-${SLUG}"
mkdir -p "$PARENT_DIR"

printf 'SCOUT_DIR=%s\n' "$SCOUT_DIR"
printf 'DATE=%s\n' "$DATE"
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

- [ ] **Step 4: Run the test to verify it passes**

Run: `bash tests/test_local_setup.sh`
Expected: PASS — `Results: 9 passed, 0 failed`. Then clean the scratch clone: `rm -rf atlas-checkout`.

- [ ] **Step 5: Commit**

```bash
git add scripts/local-setup.sh tests/test_local_setup.sh
git commit -m "Add local-setup.sh: clone Atlas + make research dirs for interactive runs"
```

---

## Task 4: The interactive `/scout` command

**Files:**
- Create: `.claude/commands/scout.md`
- Test: `tests/test_commands_present.sh` (interactive assertions already written in Task 2)

- [ ] **Step 1: Confirm the test currently fails on the interactive asserts**

Run: `bash tests/test_commands_present.sh`
Expected: the two interactive asserts FAIL (`missing …/scout.md`).

- [ ] **Step 2: Create `.claude/commands/scout.md`**

```markdown
---
description: Run a Scout research now on your subscription (no API).
argument-hint: "[topic]"
allowed-tools: AskUserQuestion, Agent, Bash, Read, Write, WebSearch, WebFetch
---

`$ARGUMENTS` is the research topic (free text, may be empty). You ARE the research
agent — do not call `claude -p`; you and your subagents run on the subscription.

## Step 1 — Topic & options

If `$ARGUMENTS` is non-empty use it as the topic; else ask in chat (plain message).
Then call `AskUserQuestion` once:
1. **Depth** (`Depth`): `survey` (Recommended) · `recon` · `expedition`.
2. **Format** (`Format`): `auto` (Recommended) · `md` · `html`.

## Step 2 — Sharpen & decompose (in chat)

Read `skills/scout/sharpen.md` and follow it to rewrite the topic into the
structured brief. For `expedition`, also produce its `scout-subtopics` list.
Show the brief (and sub-topics) to the user; incorporate their edits. Stop until
they approve. The approved sub-topic set (title + depth each) decides the mode:
sub-topics kept → **expedition**; none → **single-pass**.

## Step 3 — Setup

Build `SUB_TOPICS_TSV` (one `title<TAB>depth` line per approved sub-topic; empty
for single-pass), then run:
`SUB_TOPICS_TSV=$'…' bash <scout>/scripts/local-setup.sh "<brief title>"`
where `<scout>/scripts/local-setup.sh` is resolved via `~/.scout/dir` if set,
else this repo's `scripts/local-setup.sh`. Parse its output for `SCOUT_DIR`,
`DATE`, `PARENT_DIR`, `START_TS`, and the `CHILD=<slug><TAB><dir>` lines. Read
the playbooks under `$SCOUT_DIR/skills/scout/`.

## Step 4 — Research

**Expedition:** dispatch ALL children in ONE message (parallel) — one
`Agent` call per `CHILD`. Each agent's prompt: the full procedure from
`$SCOUT_DIR/skills/scout/SKILL.md`, plus `TOPIC=<sub-topic title>`,
`DEPTH=<child depth>`, `FORMAT=<format>`, `DATE=<date>`,
`RESEARCH_DIR=<child dir>`. It must write `<child dir>/index.{md,html}` with full
frontmatter and return: status, the artifact path, a one-line summary, and its
start/end epoch seconds. Children are single-pass (do not nest dispatch).

**Single-pass:** you do the research yourself per
`$SCOUT_DIR/skills/scout/SKILL.md` and write `$PARENT_DIR/index.{md,html}`.

If a child returns blocked/empty, tell the user and let them choose: re-dispatch
that one, drop the angle, or proceed.

## Step 5 — Cover & synthesize (expedition)

Read `$SCOUT_DIR/skills/scout/synthesis.md` and follow it:
1. Dispatch `Agent(subagent_type="scout-illustrator", …)` with `TOPIC`, the final
   `TAGS`, `RESEARCH_DIR=$PARENT_DIR`. Record `wrote cover.svg` vs `skipped`.
2. Write `$PARENT_DIR/manifest.json` = a JSON array, one object per child:
   `{"slug","title","depth","status","start","end"}`.
3. Write `$PARENT_DIR/index.md` with `layout: expedition`, the `children:`
   frontmatter list (slug/title/depth/status/summary, plus citations &
   reading_time_min for successes — read from each child's frontmatter, else
   count its `citations*.jsonl`), `cover: cover.svg` only if step 1 wrote it,
   `duration_sec: <now − START_TS>`, `cost_usd: "sub"`, and 200–600 words of
   cross-cutting synthesis with inline citations. If <2 children succeeded set
   `synthesis: false` per the skill.

**Single-pass:** dispatch `scout-illustrator` for the single artifact
(`RESEARCH_DIR=$PARENT_DIR`), and add `duration_sec` + `cost_usd: "sub"` to its
frontmatter. No `manifest.json`, no `children:`.

## Step 6 — Publish

`cd "$SCOUT_DIR" && bash scripts/publish.sh` (it commits + pushes
`atlas-checkout/` to Atlas `main`). Print the resulting Atlas URL.
```

- [ ] **Step 3: Run the test to verify it passes**

Run: `bash tests/test_commands_present.sh`
Expected: PASS — `Results: 7 passed, 0 failed` (all async + interactive asserts green).

- [ ] **Step 4: Commit**

```bash
git add .claude/commands/scout.md
git commit -m "Add interactive /scout command (subscription research + expeditions)"
```

---

## Task 5: Installer — install both commands

**Files:**
- Modify: `install.sh` (the `Install /scout slash command` block, lines ≈218-248)

No unit test (installer is interactive I/O); verified by `bash -n` and reading.

- [ ] **Step 1: Replace the command-install block**

Replace the whole block from `# Optional: install the /scout Claude Code slash command` through the closing `fi` before `rm -f "$INSTALL_DIR/.next"` with:

```bash
  # Optional: install the Scout slash commands. /scout-async is copied with the
  # repo slug substituted; /scout is symlinked to the local checkout so it
  # self-locates and auto-updates on `git pull`. ~/.scout/dir records the path.
  read -rp "Install Scout slash commands (/scout, /scout-async) to ~/.claude/commands/? [y/N]: " _ans
  if [[ "${_ans,,}" =~ ^(y|yes)$ ]]; then
    _cmddir="$HOME/.claude/commands"
    mkdir -p "$_cmddir"
    _scout_local="$CLONE_PATH"   # local Scout checkout created by this installer
    _atlas_url="https://${ATLAS_OWNER}.github.io/${ATLAS_NAME}/"

    # /scout-async — copy + substitute (needs the repo slug, can't be a symlink).
    _async_src="$_scout_local/.claude/commands/scout-async.md"
    if [[ -f "$_async_src" ]]; then
      sed -e "s|{{SCOUT_REPO}}|$SCOUT_OWNER/$SCOUT_NAME|g" \
          -e "s|{{ATLAS_URL}}|$_atlas_url|g" \
          "$_async_src" > "$_cmddir/scout-async.md"
      echo "  installed: $_cmddir/scout-async.md → $SCOUT_OWNER/$SCOUT_NAME"
    else
      echo "  skipped scout-async: $_async_src missing" >&2
    fi

    # /scout — symlink (self-locating); record the checkout path.
    mkdir -p "$HOME/.scout"
    printf '%s\n' "$_scout_local" > "$HOME/.scout/dir"
    _inter_src="$_scout_local/.claude/commands/scout.md"
    if [[ -f "$_inter_src" ]]; then
      if ln -sf "$_inter_src" "$_cmddir/scout.md" 2>/dev/null; then
        echo "  linked:    $_cmddir/scout.md → $_inter_src"
      else
        cp "$_inter_src" "$_cmddir/scout.md"   # filesystems without symlinks
        echo "  copied:    $_cmddir/scout.md (symlink unavailable; re-run install after updates)"
      fi
    else
      echo "  skipped scout: $_inter_src missing" >&2
    fi
  fi
```

(Note: `$CLONE_PATH` is the local Scout checkout path the installer already
computed near the top of `install.sh`.)

- [ ] **Step 2: Syntax-check**

Run: `bash -n install.sh && echo OK`
Expected: `OK`.

- [ ] **Step 3: Commit**

```bash
git add install.sh
git commit -m "installer: install /scout (symlink) and /scout-async (copy)"
```

---

## Task 6: Docs

**Files:**
- Modify: `docs/OPERATE.md`
- Modify: `README.md`

- [ ] **Step 1: Add a commands section to `docs/OPERATE.md`**

Add (near where running research is described):
```markdown
## Two ways to run research

| Command | Where | Billing | Use |
|---------|-------|---------|-----|
| `/scout` | interactive Claude Code | your subscription | at the desk; runs in-session, incl. parallel expeditions |
| `/scout-async` | GitHub issue → NAS runner | API (headless `claude -p`) | hands-off, fire-from-phone, durable, rerun machinery |

After 2026-06-15 headless `claude -p` is API-billed, so `/scout-async` always
costs API; `/scout` stays on your subscription because the interactive session
(and its subagents) are the model.

`/scout` self-locates the Scout checkout via `~/.scout/dir` (written by the
installer) and reads `ATLAS_REPO` from `docker/.env`. It's symlinked into
`~/.claude/commands/`, so `git pull` in Scout updates it automatically.

**Upgrading an existing install:** re-run the installer's slash-command step (or
manually: symlink `~/.claude/commands/scout.md` → `<scout>/.claude/commands/scout.md`,
copy+substitute `scout-async.md`, and write `<scout>` to `~/.scout/dir`).
```

- [ ] **Step 2: Update `README.md`**

Find the line(s) describing `/scout` opening an issue and adjust to mention both
commands: `/scout` (interactive, subscription) and `/scout-async` (issue→runner).
Keep it to 1–3 lines, matching the surrounding style.

- [ ] **Step 3: Commit**

```bash
git add docs/OPERATE.md README.md
git commit -m "docs: /scout (interactive) vs /scout-async"
```

---

## Self-Review

- **Spec coverage:** naming/rename (T2) ✓; project-scoped `.claude/commands/` (T2/T4) ✓; self-locating `local-setup.sh` + `~/.scout/dir` + ATLAS_REPO resolution (T3) ✓; parallel children via `Agent`/`SKILL.md` (T4 step 2) ✓; cover via `scout-illustrator` (T4 step 5) ✓; synthesis + `children:` + manifest (T4 step 5) ✓; `duration_sec` from `START_TS` (T3 prints it, T4 uses it) ✓; `cost_usd: "sub"` (T4) + compass render (T1) ✓; installer symlink/copy (T5) ✓; docs (T6) ✓; format reverted on async + `test_format_removed` untouched (T2) ✓.
- **Placeholder scan:** none — every code step has complete content. `{{SCOUT_REPO}}`/`{{ATLAS_URL}}` are intentional async substitution tokens.
- **Naming consistency:** `local-setup.sh` outputs `SCOUT_DIR`/`DATE`/`PARENT_DIR`/`START_TS`/`CHILD=` are produced in T3 and consumed by the same names in T4. `cost_usd: "sub"` identical in T1 (render) and T4 (write). `~/.scout/dir` written in T5, read in T3.
- **Sequencing note:** T1 (compass) should land before a `cost_usd:"sub"` page is published, but the Scout tasks (T2–T6) don't depend on it to pass their tests — so T2–T6 can proceed even if compass push is deferred.
- **Known limitation:** the command prompt and Liquid aren't unit-tested; `local-setup.sh`, the command's presence/shape, and reused `publish.sh` are. The compass edit is verified by a local Jekyll render.
