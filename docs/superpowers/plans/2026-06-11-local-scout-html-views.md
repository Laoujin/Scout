# Local `/scout`: HTML views + provenance hardening — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Give the interactive `/scout` command the ability to author bespoke HTML "views" (held before publish so they ship in the canonical's commit), and make its provenance issue explicitly invisible to CI.

**Architecture:** Section B (Tasks 1–2) is plain shell + TDD against the existing `test_local_issue.sh` harness. Section A (Task 3) is a prose edit to the `/scout` command doc that reuses the existing `view-candidacy.md` (judge) and `scout-view-author` (author) skills inline — no new scripts, no Atlas changes. Do Section B first (independent, test-backed), then Section A.

**Tech Stack:** Bash, `gh` CLI, GitHub Actions (`research.yml` trigger guards), Claude Code command docs + skills.

**Spec:** `docs/superpowers/specs/2026-06-11-local-scout-html-views-design.md`

**Conventions:**
- Commits are imperative subject ≤72 chars, one concern each. Do NOT push (Wouter's rule: ask before pushing).
- Each standalone test is run directly: `bash tests/<name>.sh` (no central runner). Shell syntax check: `bash -n <script>` (shellcheck is not installed).

---

## Task 1: Provenance issue — `[research-local]` prefix + `scout-local-research` label

Make `local-issue.sh open` prefix the title and apply a distinct label, so CI's `research.yml` guard (`startsWith(title,'[research] ') || has-label scout-research`) never matches. Ensure the label exists first, because `gh issue create --label X` fails on a missing label and this script swallows gh failures — which would silently drop the provenance issue.

**Files:**
- Modify: `scripts/local-issue.sh` (the `cmd_open` function, currently lines ~36–44)
- Test: `tests/test_local_issue.sh` (the `--- open: ---` block, currently lines ~46–52)

- [ ] **Step 1: Update the test assertions (red first)**

In `tests/test_local_issue.sh`, find this line in the `# --- open: ... ---` block:

```bash
grep -q -- "--title Hoi An guide" "$GH_LOG" && pass "create passes title" || fail "no title in: $(cat "$GH_LOG")"
```

Replace that single line with these two assertions (note `-F`: `[research-local]` is a regex char-class otherwise):

```bash
grep -qF -- "--title [research-local] Hoi An guide" "$GH_LOG" && pass "create prefixes title with [research-local]" || fail "no prefixed title in: $(cat "$GH_LOG")"
grep -qF -- "--label scout-local-research" "$GH_LOG" && pass "create applies scout-local-research label" || fail "no label in: $(cat "$GH_LOG")"
```

(The existing gh stub in this test logs argv and returns 0 for any non-`issue create` call, so the new `gh label create` call is logged harmlessly and the `num=77` parse is unaffected — only the `issue create` stdout is piped to `grep -oE`.)

- [ ] **Step 2: Run the test to verify it fails**

Run: `bash tests/test_local_issue.sh`
Expected: FAIL — `no prefixed title` and `no label` (script still emits the bare title, no label).

- [ ] **Step 3: Implement the prefix + label in `cmd_open`**

In `scripts/local-issue.sh`, replace the whole `cmd_open` function:

```bash
cmd_open() {
  local title="$1" body_file="$2" repo num
  repo="$(_repo_slug)" || { echo "[local-issue] no origin remote; skipping issue" >&2; return 0; }
  [ -f "$body_file" ] || { echo "[local-issue] prompt file not found: $body_file" >&2; return 0; }
  # The [research-local] prefix dodges research.yml's startsWith(title,'[research] ')
  # guard and the scout-local-research label is distinct from the scout-research
  # trigger label — so CI never processes a local provenance issue. Ensure the label
  # first: `gh issue create --label` fails on a missing label, and we swallow that
  # failure below, which would silently drop the whole issue.
  gh label create scout-local-research --color 0e7490 \
    --description "Scout started with /scout slash command on subscription" \
    --repo "$repo" --force >/dev/null 2>&1 || true
  num="$(gh issue create --repo "$repo" --title "[research-local] $title" \
         --label scout-local-research --body-file "$body_file" 2>/dev/null \
         | grep -oE '[0-9]+$' | tail -1)"
  if [ -n "$num" ]; then printf '%s\n' "$num"; else echo "[local-issue] issue create failed; continuing" >&2; fi
}
```

- [ ] **Step 4: Run the test to verify it passes**

Run: `bash tests/test_local_issue.sh`
Expected: PASS on all assertions, including the two new ones and the unchanged non-fatal/close cases. Final line: `Results: N passed, 0 failed`.

- [ ] **Step 5: Syntax-check the script**

Run: `bash -n scripts/local-issue.sh`
Expected: no output, exit 0.

- [ ] **Step 6: Commit**

```bash
git add scripts/local-issue.sh tests/test_local_issue.sh
git commit -m "Tag local provenance issues with [research-local] + label so CI skips them"
```

---

## Task 2: Create the `scout-local-research` label at install time

Mirror the existing `scout-research` label-creation block so a fresh setup pre-creates the label (the per-run ensure in Task 1 is the safety net; this gives it the right colour/description at provisioning).

**Files:**
- Modify: `scripts/installer.sh` (just after the `scout-research` block, currently lines ~139–143)

No unit test: `installer.sh` is a one-shot provisioning script that runs `gh` against a real repo; there is no harness for it and adding one is disproportionate. Verification is a syntax check + a grep that the block landed.

- [ ] **Step 1: Add the label block**

In `scripts/installer.sh`, find:

```bash
step "Creating scout-research label..."
gh label create scout-research \
  --color c2410c \
  --description "Scout research request" \
  --repo "$SCOUT_OWNER/$SCOUT_NAME" >/dev/null 2>&1 || true
ok
```

Insert immediately after that block (before the next `SCOUT_DIR="/work/$SCOUT_NAME"` line):

```bash
step "Creating scout-local-research label..."
gh label create scout-local-research \
  --color 0e7490 \
  --description "Scout started with /scout slash command on subscription" \
  --repo "$SCOUT_OWNER/$SCOUT_NAME" >/dev/null 2>&1 || true
ok
```

- [ ] **Step 2: Verify the block landed and the script still parses**

Run: `grep -n "scout-local-research" scripts/installer.sh && bash -n scripts/installer.sh && echo OK`
Expected: prints the matching line(s), then `OK`, exit 0.

- [ ] **Step 3: Commit**

```bash
git add scripts/installer.sh
git commit -m "Create scout-local-research label during install"
```

---

## Task 3: Insert Step 5.5 — HTML views into the `/scout` command

Add the views step to `.claude/commands/scout.md` between Step 5 (cover & synthesize) and Step 6 (publish). It judges candidacy inline (no `claude -p`), shows an editable pre-ticked checklist in chat, and fans out `scout-view-author` sub-agents — all before publish, so views ride the canonical's single commit.

**Files:**
- Modify: `.claude/commands/scout.md` (insert a new section before the `## Step 6 — Publish` header at line ~115)

No automated test — this is a command/prose doc. Verification is a structural grep + a read-through for step-numbering and cross-reference consistency.

- [ ] **Step 1: Insert the new section**

In `.claude/commands/scout.md`, insert the following block immediately **before** the line `## Step 6 — Publish`:

````markdown
## Step 5.5 — HTML views

Offer bespoke HTML "views" of the pages you just wrote, then author the ticked ones.
This runs **before** Step 6 so the views land in the same commit as the canonical. Do
NOT call `view-candidacy.sh` or `views-dispatch.sh` — they shell out to `claude -p`
(API). You do the judging and the dispatch yourself, on the subscription.

**1. Judge (inline).** Read `$SCOUT_DIR/skills/scout/view-candidacy.md` and apply it
yourself. Build its inputs from what you already wrote in Steps 3–5: `RUN_KIND`
(`decompose` for an expedition, else `single`), `PARENT_PATH`, and a `PAGES` array —
one entry per page actually written (parent + each successful child for an
expedition; just the parent for single-pass), each carrying
`row`/`slug`/`path`/`title`/`summary`/`depth`/`citations`/`format` read from that
page's frontmatter. Produce the skill's JSON: per page `should_offer_view` plus
`view_name`/`title_suffix`/`vibe_hint`. Follow its criteria and override rules —
force the parent to be offered, skip a page whose canonical is already `format: html`,
skip pages with ≤2 citations, and never reuse a `view_name` across sibling children.

**2. Checklist (in chat).** Render the candidacy as a checklist and ask the user to
confirm. Pre-tick recommended pages with their register; leave the rest unticked:

```
- [x] **<parent title>** — register: <view_name>
- [x] <child-slug> — register: <view_name>
- [ ] <child-slug>
```

Tell the user they can tick/untick any line (including all on / all off) and change a
register. **Stop until they reply.** If they untick everything, skip to Step 6.

**3. Author (parallel sub-agents).** For each ticked page, create its
`<research-dir>/views/` directory, then dispatch ALL views in ONE message — one
`Agent` call per ticked page. `scout-view-author` is a skill, not an agent type, so
(mirroring the Step 5 illustrator fallback) give a `general-purpose` agent the body of
`$SCOUT_DIR/skills/scout-view-author/SKILL.md` as its brief, plus:
`CANONICAL_PATH=<research-dir>/index.{md,html}`, `RESEARCH_DIR=<research-dir>`,
`VIEW_NAME=<view_name>`, `TITLE_SUFFIX=<title_suffix>`, `VIBE_HINT=<vibe_hint>`. Each
agent writes `views/<view_name>.html` (+ `views/<view_name>.links.json` and any
`views/<view_name>/images/`) and returns a one-line status + the view path.

If a view agent fails or returns empty, tell the user and let them choose: retry,
drop, or proceed. A failed view never blocks Step 6 — publish proceeds without it.

````

- [ ] **Step 2: Verify structure and ordering**

Run: `grep -n "^## Step" .claude/commands/scout.md`
Expected: the headers appear in order … `Step 5 — Cover & synthesize`, then `Step 5.5 — HTML views`, then `Step 6 — Publish`.

- [ ] **Step 3: Read-through consistency check**

Read the inserted Step 5.5 and the surrounding Steps 5 and 6. Confirm: it references real paths (`$SCOUT_DIR/skills/scout/view-candidacy.md`, `$SCOUT_DIR/skills/scout-view-author/SKILL.md`), `$PARENT_DIR`/child dirs match the names used in Steps 3–5, and Step 6's publish wording still makes sense as the next step. Fix any drift inline.

- [ ] **Step 4: Commit**

```bash
git add .claude/commands/scout.md
git commit -m "Add Step 5.5: author HTML views in local /scout before publish"
```

---

## Final verification

- [ ] **Re-run the affected unit test**

Run: `bash tests/test_local_issue.sh`
Expected: `Results: N passed, 0 failed`.

- [ ] **Syntax-check both modified scripts**

Run: `bash -n scripts/local-issue.sh && bash -n scripts/installer.sh && echo OK`
Expected: `OK`, exit 0.

- [ ] **Confirm CI guard immunity (manual reasoning, no command)**

Verify the title `[research-local] <anything>` does not start with `[research] ` (trailing space) and `scout-local-research ≠ scout-research`. Both guard clauses in `.github/workflows/research.yml` therefore stay false. No change to `scout-async.md` (it intentionally still matches and triggers CI).
