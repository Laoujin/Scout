---
name: scout
description: Run a Scout research now on your subscription (no API).
argument-hint: "[topic]"
allowed-tools: AskUserQuestion, Agent, Bash, Read, Write, WebSearch, WebFetch
---

`$ARGUMENTS` is the research topic (free text, may be empty). You ARE the research
agent — do not call `claude -p`; you and your subagents run on the subscription.

## Step 0a — Resolve `SCOUT_DIR` (do this first)

`SCOUT_DIR` is the Scout install holding `scripts/` and `skills/`. Resolve it once:

- If the text `${CLAUDE_PLUGIN_ROOT}` on this line reads as an absolute path (you're
  running as an installed plugin), then `SCOUT_DIR=${CLAUDE_PLUGIN_ROOT}`.
- Otherwise it's still the literal `${CLAUDE_PLUGIN_ROOT}` (you're running from a
  checkout, not an installed plugin): if `~/.scout/dir` exists use
  `SCOUT_DIR=$(cat ~/.scout/dir)`; else this skill file lives at
  `<checkout>/skills/scout/SKILL.md`, so `SCOUT_DIR=<checkout>`.

Every `$SCOUT_DIR/scripts/…` and `$SCOUT_DIR/skills/…` path below resolves against it.

## Step 0 — Resolve Atlas checkout & worktree home

Locate `atlas-config.sh` at `$SCOUT_DIR/scripts/atlas-config.sh`.

1. **Atlas checkout.** Run `bash $SCOUT_DIR/scripts/atlas-config.sh resolve-atlas`.
   - Exit 0 → use the printed absolute path as `ATLAS_DIR`.
   - Non-zero → first run. Call `AskUserQuestion` once. If
     `bash $SCOUT_DIR/scripts/atlas-config.sh detect-sibling $SCOUT_DIR` prints a path,
     offer it as the recommended option. Options:
     - **Use detected checkout** `<printed path>` (when present)
     - **Provide a path** to an existing Atlas checkout
     - **Clone fresh** into `~/.scout/atlas` (ask for the repo URL; default
       `git@github.com:Laoujin/Atlas`; `git clone` it, then continue)
     Persist with `bash $SCOUT_DIR/scripts/atlas-config.sh save-atlas "<chosen path>"`
     (it validates git + origin and stores the absolute path). Use its echo as `ATLAS_DIR`.
2. **Worktree home.** Run `bash $SCOUT_DIR/scripts/atlas-config.sh resolve-worktrees`.
   - Exit 0 → use the printed path as `WT_HOME`.
   - Non-zero → `AskUserQuestion` once. Options:
     - **`~/.scout/atlas-worktrees/`**
     - **Custom** — the user types a path
     - **`<ATLAS_DIR>/worktrees/`** (inside the checkout)
     For the inside-Atlas choice, persist with
     `save-worktrees "<ATLAS_DIR>/worktrees" "<ATLAS_DIR>"` (wires `.git/info/exclude`);
     otherwise `save-worktrees "<chosen path>"`. Use its echo as `WT_HOME`.

`ATLAS_DIR`'s `origin` remote is the publish target — there is no `ATLAS_REPO` anymore.

## Step 1 — Topic & options

If `$ARGUMENTS` is non-empty use it as the topic; else ask in chat (plain message).
**Save the raw topic input verbatim** (the original pasted prompt, *before* Step 2
sharpens it) to a tempfile — `RAW_PROMPT_FILE=$(mktemp)` then write the exact text
into it. This is the issue body in Step 6.
Then call `AskUserQuestion` once:
1. **Depth** (`Depth`): `survey` (Recommended) · `recon` · `expedition`.
2. **Format** (`Format`): `auto` (Recommended) · `md` · `html`.

## Step 2 — Sharpen & decompose (in chat)

Read `$SCOUT_DIR/skills/scout-research/sharpen.md` (`SCOUT_DIR` resolved in Step 0a) and
follow it to rewrite the topic into the structured brief. For `expedition`, also produce its
`scout-subtopics` list.

**Series match.** Read the Atlas series list from `$ATLAS_DIR/_data/series.yml`
(the checkout resolved in Step 0; skip this whole step if the file is absent). Pass it to
the sharpening as `sharpen.md`'s `Existing series:` input and apply its rule 9: if the
brief *confidently* belongs to exactly one existing series, propose a `scout-series`
block per `sharpen.md`'s format. If no confident match, propose nothing.

### Gate 1 — approve the brief (chat)

Show the brief and — each only if sharpen produced one — the `scout-subtopics` and
`scout-series` blocks, verbatim (their `- [x]` / `- [ ]` marks, `(depth)` codes and
rationales). **Stop until the user approves.**

Every *edit* happens here, because a checkbox can only select — it can't reword a
brief, change an angle's `(depth)`, invent an angle, or move a series group. Feedback
of any kind means a re-sharpen round, then show Gate 1 again.

### Gate 2 — select the angles (AskUserQuestion)

Once the user approves, call `AskUserQuestion` **once**. Build its questions from the
approved blocks, skipping any question whose list is empty. If that leaves no questions
at all (no sub-topics and no series match), skip Gate 2 entirely and continue as
single-pass.

| Question    | Header        | Kind          | Options                                        |
|-------------|---------------|---------------|------------------------------------------------|
| Core angles | `Core angles` | multiSelect   | the stated (`- [x]`) angles, first 4           |
| More angles | `More angles` | multiSelect   | stated angles 5–8; only when there are >4      |
| Also cover? | `Also cover?` | multiSelect   | the suggested (`- [ ]`) completeness angles    |
| Series      | `Series`      | single-select | `Yes — <slug> › <group>` / `No`                |

- Option `label` is the angle title (trim to ~5 words); `description` carries its
  `(depth)` and one-line rationale.
- **Nothing is pre-ticked** — `AskUserQuestion` has no `- [x]` equivalent. An angle
  runs only if the user ticks it. Gate 1 is where they saw what Scout recommends.
- **A question needs ≥2 options.** Any list above holding exactly *one* entry is asked
  as a **single-select Yes/No** instead. `Series` always is — sharpen matches at most
  one series.
- The 4-question budget always fits: sharpen caps sub-topics at 8 with ≤3 completeness
  suggestions, so the worst case (5 stated + 3 suggested + series) is exactly 4.
- An **Other** answer on any question is re-sharpen feedback — go back to Gate 1.

**The Gate-2 selection is what runs** — not the list shown at Gate 1. The ticked angles
are the sub-topic set Step 3 turns into `SUB_TOPICS_TSV`; an unticked angle is dropped,
stated or suggested alike. Each angle keeps the full title and `(depth)` it carried at
Gate 1; the ~5-word trim is display-only. ≥1 angle ticked → **expedition**; none ticked
(or no `scout-subtopics` block at all) → **single-pass**. A `Yes` on `Series` carries
`<series-slug>` (and optional `<group-label>`) into Step 6; a `No` means no series
filing.

## Step 3 — Setup

Build `SUB_TOPICS_TSV` (one `title<TAB>depth` line per sub-topic ticked in Step 2's
Gate 2; empty for single-pass) and run `local-setup.sh` (from the `SCOUT_DIR` resolved
in Step 0a) with the resolved paths:

```
ATLAS_DIR="<ATLAS_DIR>" WT_HOME="<WT_HOME>" SUB_TOPICS_TSV=$'Routing angle\tdeep\nState angle\tsurvey' \
  bash $SCOUT_DIR/scripts/local-setup.sh "<brief title>"
```

Parse its output for `ATLAS_DIR`, `WORKTREE`, `BRANCH`, `DATE`, `SLUG`,
`PARENT_DIR`, `START_TS`, and the `CHILD=<slug><TAB><dir>` lines. Read the
playbooks under `$SCOUT_DIR/skills/scout-research/`.

## Step 4 — Research

**Depth codes:** when you pass `DEPTH` into a `SKILL.md` research prompt (child or
single-pass), translate the user-facing depth to SKILL.md's internal code —
`recon`→`ceo`, `survey`→`standard`, `expedition`→`deep` (mirrors `run.sh`).
Keep the user-facing value (`recon`/`survey`/`expedition`) in the `children:`
frontmatter.

**Expedition:** dispatch ALL children in ONE message (parallel) — one `Agent`
call per `CHILD`. Each agent's prompt: the full procedure from
`$SCOUT_DIR/skills/scout-research/SKILL.md`, plus `TOPIC=<sub-topic title>`,
`DEPTH=<child depth>`, `FORMAT=<format>`, `DATE=<date>`, `RESEARCH_DIR=<child dir>`,
and `MODEL=<friendly label of the model running this session, e.g. "Opus 4.8">`.
It must write `<child dir>/index.{md,html}` with content frontmatter (title, tags,
summary, citations, reading_time_min) and return: status, the artifact path, a
one-line summary, and its start/end epoch seconds. **Do not** ask the child to
stamp `model` / `duration_sec` / `cost_usd` — those are stamped deterministically
in Step 6 via `inject-run-metadata.sh` (agents drop them unreliably).
Children are single-pass (do not nest dispatch) — so a child does **not** draft its
own cover; covers are added centrally in Step 5.

**Single-pass:** you do the research yourself per
`$SCOUT_DIR/skills/scout-research/SKILL.md` and write `$PARENT_DIR/index.{md,html}`.

If a child returns blocked/empty, tell the user and let them choose: re-dispatch
that one, drop the angle, or proceed.

## Step 5 — Cover & synthesize (expedition)

Read `$SCOUT_DIR/skills/scout-research/synthesis.md` and follow it:
1. **Covers — parent AND every successful child** (the CI flow gives each angle its
   own cover; match it). In ONE message dispatch `scout-illustrator` once per
   successful `CHILD` (`TOPIC=<child title>`, `TAGS=<child tags>`,
   `RESEARCH_DIR=<child dir>`) **and** once for the parent (`RESEARCH_DIR=$PARENT_DIR`,
   the final expedition `TAGS`). Then wire each child's cover **deterministically** —
   the children's artifacts were already written in Step 4, so don't hand-edit them:
   for every successful `CHILD` run
   `bash $SCOUT_DIR/scripts/inject_cover.sh <child dir>/index.{md,html}`. It adds
   `cover: cover.svg` iff the illustrator wrote one and is a no-op otherwise, so an
   orphaned `cover.svg` can't slip past. (The parent's `cover:` is set when you write
   its index in step 3 below.) If the `scout-illustrator` agent type isn't registered
   in this harness, run a `general-purpose` agent with the body of
   `$SCOUT_DIR/.claude/agents/scout-illustrator.md` as its brief — same inputs, same
   one-line return.
2. Write `$PARENT_DIR/manifest.json` = a JSON array, one object per child:
   `{"slug","title","depth","status","start","end"}`.
3. Write `$PARENT_DIR/index.md` with `layout: expedition`, the `children:`
   frontmatter list (slug/title/depth/status/summary, plus citations &
   reading_time_min for successes — read from each child's frontmatter, else count
   its `citations*.jsonl`), `cover: cover.svg` only if step 1 wrote it, and
   200–600 words of
   cross-cutting synthesis with inline citations. If <2 children succeeded set
   `synthesis: false` per the skill.

**Single-pass:** dispatch `scout-illustrator` for the single artifact
(`RESEARCH_DIR=$PARENT_DIR`). `model` / `duration_sec` / `cost_usd` are stamped in
Step 6 via `inject-run-metadata.sh` (pass `DURATION=<now − START_TS>`). No
`manifest.json`, no `children:`.

## Step 5.5 — HTML views

Offer bespoke HTML "views" of the pages you just wrote, then author the ticked ones.
This runs **before** Step 6 so the views land in the same commit as the canonical. Do
NOT call `view-candidacy.sh` or `views-dispatch.sh` — they shell out to `claude -p`
(API). You do the judging and the dispatch yourself, on the subscription.

**1. Judge (inline).** Read `$SCOUT_DIR/skills/scout-research/view-candidacy.md` and apply it
yourself. Build its inputs from what you already wrote in Steps 3–5: `RUN_KIND`
(`decompose` for an expedition, else `single`), `PARENT_PATH`, and a `PAGES` array —
one entry per page actually written (parent + each successful child for an
expedition; just the parent for single-pass), each carrying
`row`/`slug`/`path`/`title`/`summary`/`depth`/`citations`/`format` read from that
page's frontmatter. Produce the skill's JSON: per page `should_offer_view` plus
`view_name`/`title_suffix`/`vibe_hint`. Follow its criteria and override rules —
force the **expedition** parent to be offered (a single-pass page is judged on its
merits, not force-offered), skip a page whose canonical is already `format: html`,
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

**3. Author (parallel sub-agents).** For each ticked page — `<research-dir>` is
`$PARENT_DIR` for the parent, the child dir for a child — create its
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

## Step 6 — Publish

**Validate first (non-fatal — mirrors `run.sh`'s pre-publish checks).** For each
canonical page you're about to publish — the single-pass `$PARENT_DIR`, or each
**successful child** dir of an expedition — run both validators against its
`index.{md,html}`:

```
bash "$SCOUT_DIR/scripts/validate_frontmatter.sh" <dir>/index.{md,html}
[ -f "<dir>/citations.jsonl" ] && \
  bash "$SCOUT_DIR/scripts/validate_ledger.sh" "<dir>/citations.jsonl" "<dir>/index.{md,html}"
```

`validate_frontmatter.sh` auto-fixes safe YAML issues and exits non-zero only on an
unfixable parse error; `validate_ledger.sh` checks the citations schema and that every
`[[n]]` in the artifact resolves. Neither blocks publishing — if either reports a
problem, show it to the user and let them fix-and-revalidate or publish as-is. Like
`run.sh`, validate **per page**: the single-pass artifact, or each expedition child.
The expedition **parent** synthesis index is intentionally not frontmatter-validated
(its hand-written summary is kept out of the YAML validator, matching CI).

**File into the series first (only if the user answered `Yes` to Step 2's `Series`
question).** Run this *before* `publish.sh` so the `series.yml` edit is swept into the
same commit (mirrors `run-decompose.sh`'s wiring). `add-to-series.sh` edits the
worktree's copy and never creates a new series:

```
bash "$SCOUT_DIR/scripts/add-to-series.sh" \
  "$WORKTREE/_data/series.yml" \
  "<date>-<slug>" "<series-slug>" "<group-label>"   # omit group-label for a flat series
```

Then forward the values from Step 3 so the commit message and published URL are
correct (`publish.sh` defaults them to `unknown` otherwise, and needs `ATLAS_DIR`
to build the URL from its `origin` remote):

```
cd "$SCOUT_DIR" && WORKTREE="<WORKTREE>" BRANCH="<BRANCH>" ATLAS_DIR="<ATLAS_DIR>" \
  SLUG="<slug>" DATE="<date>" TOPIC="<brief title>" bash scripts/publish.sh
```

It commits + pushes the run's `WORKTREE` to Atlas `main` (as `HEAD:main`), then
removes the worktree + branch on success, and prints `Published: <url>`.

**Provenance issue + metadata (all non-fatal — a gh/network failure must not undo a
successful publish). Run BEFORE `publish.sh` above so `issue:` is swept into the
same commit:**

1. Open the issue with the verbatim prompt, then stamp metadata — place these two
   lines just before the `publish.sh` call:
   ```
   ISSUE=$(SCOUT_DIR="$SCOUT_DIR" bash scripts/local-issue.sh open "<brief title>" "$RAW_PROMPT_FILE")
   MODEL="<friendly session model label, e.g. Opus 4.8>" ISSUE="$ISSUE" \
     bash scripts/inject-run-metadata.sh "$PARENT_DIR"
   ```
   For a single-pass run also pass `DURATION="$(( $(date +%s) - START_TS ))"` on the
   `inject-run-metadata.sh` line.
2. After `publish.sh` prints the URL, comment + close the issue:
   ```
   SCOUT_DIR="$SCOUT_DIR" bash scripts/local-issue.sh close "$ISSUE" "<published url>"
   ```

Surface the `Published: <url>` and the issue link to the user.
