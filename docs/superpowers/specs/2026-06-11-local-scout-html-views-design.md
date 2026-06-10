# Local `/scout`: HTML views + provenance hardening — design

**Date:** 2026-06-11
**Status:** approved design, pending implementation plan
**Scope:** the interactive/subscription `/scout` path only (`.claude/commands/scout.md` + `scripts/local-issue.sh` + `scripts/installer.sh`). The async path (`scout-async.md` → CI) and the CI views subsystem are untouched.

## Problem

The CI research path already ships bespoke HTML "views" end to end: `run.sh`/`run-decompose.sh` call `view-candidacy.sh` (LLM judge) → `publish.sh` calls `views-comment.sh` (posts a checkbox candidacy comment on the issue) → the user ticks a box → `views-dispatch.sh` fans out `scout-view-author` and commits the views.

The **interactive `/scout` command** (`scout.md`) never touches any of this. It researches and publishes the canonical only. The `scout-view-author` skill even documents the wiring as TODO ("`run.sh` (when this is wired up)"). So a local run can't produce the "Read as: [Default] [Magazine]" pill that CI runs get.

Separately, the local provenance issue opened by `local-issue.sh` is only *implicitly* shielded from CI: it survives by having a bare title and no label, but a brief title that happened to start with `[research] ` would trip CI's trigger guard.

## Section A — HTML views in local `/scout`

### Approach

Reuse the two existing skills (`skills/scout/view-candidacy.md` = judge, `skills/scout-view-author/SKILL.md` = author) **inline**, driven from `scout.md`. The command is subscription-only ("do not call `claude -p`"), so we do **not** call `view-candidacy.sh` (it shells out to `claude -p` and burns API); Scout performs the judgment itself in-session. No new scripts, no Atlas changes — Atlas-side rendering (`_layouts/view.html` + the "Read as" pill) is already live because CI ships views to the same repo. (Assumption to confirm on first real run.)

The user chose **"hold publish, ship everything in one commit"**: views are decided and authored *before* the canonical is committed, so canonical + covers + views + series edit land in a single push.

### New Step 5.5 — HTML views (inserted between current Step 5 "cover & synthesize" and Step 6 "publish")

1. **Judge inline (no API).** Build the `PAGES` array from frontmatter already written in Steps 3–5 (parent + each successful child for an expedition; the single page for single-pass). Apply `view-candidacy.md` directly to produce per-page `should_offer_view` / `view_name` / `title_suffix` / `vibe_hint`, honoring its override rules (parent force-offered; skip `format: html` canonicals; skip pages with ≤2 citations). The single-pass page is judged on its merits (not force-offered).

2. **Editable checklist in chat** — same shape `views-comment.sh` renders on the issue, but as a chat message:
   ```
   - [x] **Parent Title** — register: masthead
   - [x] youtube-channels — register: storyboard
   - [ ] podcasts
   ```
   Recommended pages pre-ticked with their proposed register; the user may tick/untick any (including all on / all off) and override a register. Untick everything → skip straight to publish. Wait for approval before authoring.

3. **Author ticked views in parallel.** Pre-create each `<research-dir>/views/`, then dispatch **one subagent per ticked page in a single message** (mirrors how Step 4 fans out children and Step 5 fans out illustrators). `scout-view-author` is a skill, not a registered agent type, so — exactly like Step 5's illustrator fallback — dispatch a `general-purpose` agent whose brief is the body of `skills/scout-view-author/SKILL.md` plus inputs `CANONICAL_PATH` / `RESEARCH_DIR` / `VIEW_NAME` / `TITLE_SUFFIX` / `VIBE_HINT`. Each writes `views/<name>.html` (+ `views/<name>.links.json` + `views/<name>/images/`). Output is identical to CI's dispatch.

4. **Non-blocking.** A view that fails or returns empty is reported; the user may retry or drop it. It never blocks the canonical — publish proceeds without that view.

### Step 6 (publish) — unchanged

`publish.sh` commits the whole `atlas-checkout/`, so any `views/` files ride along in the same commit as canonical + covers + series edit + issue stamp. The provenance-issue lifecycle (open → stamp → publish → close) is entirely inside Step 6, i.e. *after* the views are already on disk — so, unlike CI, the local flow never reopens a closed issue.

### Rejected alternatives

- **Publish canonical first, then views in a second commit** — mirrors CI semantics and keeps view failures off the canonical's critical path, but produces two commits. User preferred a single combined commit.
- **Always ask (skip candidacy)** — drops the "LLM pre-ticks the recommended pages" behaviour the user explicitly wanted.
- **Inline sequential authoring** (Scout writes each view itself) — simpler but slower and pollutes the main session's context; parallel subagents match the rest of the command.

## Section B — Local provenance hardening

Independent of Section A; shares the local surface. Makes the local provenance issue *explicitly* invisible to CI instead of relying on a bare title.

CI's trigger guard (`research.yml`, both issue jobs):
```
startsWith(github.event.issue.title, '[research] ')   // note trailing space
  || contains(github.event.issue.labels.*.name, 'scout-research')
```
`[research-local] …` does **not** match `[research] ` (the space after `research` is the discriminator), and `scout-local-research` is a different label, so neither trigger fires. Either guard alone suffices; we add both as belt-and-suspenders.

### Changes

1. **`scripts/local-issue.sh` (`open`)**
   - Prepend `[research-local] ` to the issue title.
   - Before `gh issue create`, ensure the label exists: `gh label create scout-local-research --color 0e7490 --description "Scout started with /scout slash command on subscription" --repo "$repo" --force 2>/dev/null || true` (colour `0e7490`/cyan, distinct from `scout-research`'s `c2410c`/rust). Required because `gh issue create --label X` *fails* on a missing label and `local-issue.sh` swallows all gh failures → the provenance issue would silently vanish.
   - Pass `--label scout-local-research` on the create.

2. **`scripts/installer.sh`** — beside the existing `scout-research` block (line ~139), add a `gh label create scout-local-research` block (same `… || true` non-fatal style, distinct colour, description "Scout started with /scout slash command on subscription").

3. **`tests/test_local_issue.sh`** (TDD — change tests first):
   - Update the existing assertion `--title Hoi An guide` → `--title [research-local] Hoi An guide`.
   - Add an assertion that `--label scout-local-research` is passed on create.
   - (The gh stub already logs argv; a `gh label create` call against the stub is harmless and returns 0.)

## Out of scope

- No changes to `scout-async.md` — the async issue is intentionally `[research]`-titled + `scout-research`-labelled so CI *does* process it (including views, end to end).
- No changes to the CI views scripts (`view-candidacy.sh`, `views-comment.sh`, `views-dispatch.sh`, `lib-views-parse.sh`) or `research.yml`.
- No Atlas changes (view rendering already live).

## Files touched

| File | Section | Change |
|---------------------------------|---------|--------------------------------------------------|
| `.claude/commands/scout.md`     | A       | Insert Step 5.5 (judge → checklist → author) between Steps 5 and 6; publish stays Step 6 |
| `scripts/local-issue.sh`        | B       | Title prefix + ensure/apply `scout-local-research` label |
| `scripts/installer.sh`          | B       | Create `scout-local-research` label at setup |
| `tests/test_local_issue.sh`     | B       | Update title assertion; add label assertion |
