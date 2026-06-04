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

Read `skills/scout/sharpen.md` (under the `SCOUT_DIR` resolved in Step 3 — if you
haven't resolved it yet, run Step 3's command first) and follow it to rewrite the
topic into the structured brief. For `expedition`, also produce its
`scout-subtopics` list. Show the brief (and sub-topics) to the user; incorporate
their edits. Stop until they approve. The approved sub-topic set (title + depth
each) decides the mode: sub-topics kept → **expedition**; none → **single-pass**.

**Series match.** Read the Atlas series list from `<scout>/../atlas/_data/series.yml`
(the sibling Atlas checkout; skip this whole step if the file is absent). Pass it to
the sharpening as `sharpen.md`'s `Existing series:` input and apply its rule 9: if the
brief *confidently* belongs to exactly one existing series, propose a `scout-series`
block — ticked `- [x]`, with `› <group-label>` only when that series has `groups:`
(pick the single best-fitting label). Show the block under the brief; the user may
untick it or change the group. Carry the approved `<series-slug>` (and optional
`<group-label>`) into Step 6. If no confident match, propose nothing.

## Step 3 — Setup

Locate the helper: if `~/.scout/dir` exists, use
`$(cat ~/.scout/dir)/scripts/local-setup.sh`; otherwise this command file lives in
`<scout>/.claude/commands/`, so use `<scout>/scripts/local-setup.sh`.

Build `SUB_TOPICS_TSV` (one `title<TAB>depth` line per approved sub-topic; empty
for single-pass) and run it:

```
SUB_TOPICS_TSV=$'Routing angle\tdeep\nState angle\tsurvey' \
  bash <scout>/scripts/local-setup.sh "<brief title>"
```

Parse its output for `SCOUT_DIR`, `ATLAS_REPO`, `DATE`, `SLUG`, `PARENT_DIR`,
`START_TS`, and the `CHILD=<slug><TAB><dir>` lines. Read the playbooks under
`$SCOUT_DIR/skills/scout/`.

## Step 4 — Research

**Depth codes:** when you pass `DEPTH` into a `SKILL.md` research prompt (child or
single-pass), translate the user-facing depth to SKILL.md's internal code —
`recon`→`ceo`, `survey`→`standard`, `expedition`→`deep` (mirrors `run.sh`).
Keep the user-facing value (`recon`/`survey`/`expedition`) in the `children:`
frontmatter.

**Expedition:** dispatch ALL children in ONE message (parallel) — one `Agent`
call per `CHILD`. Each agent's prompt: the full procedure from
`$SCOUT_DIR/skills/scout/SKILL.md`, plus `TOPIC=<sub-topic title>`,
`DEPTH=<child depth>`, `FORMAT=<format>`, `DATE=<date>`, `RESEARCH_DIR=<child dir>`,
and `MODEL=<friendly label of the model running this session, e.g. "Opus 4.8">`.
It must write `<child dir>/index.{md,html}` with full frontmatter — including
`model: "<MODEL>"`, `duration_sec: <its end − start epoch seconds>`, and
`cost_usd: "sub"` (mirrors what `inject_cost.sh` adds in the CI flow) — and return:
status, the artifact path, a one-line summary, and its start/end epoch seconds.
Children are single-pass (do not nest dispatch) — so a child does **not** draft its
own cover; covers are added centrally in Step 5.

**Single-pass:** you do the research yourself per
`$SCOUT_DIR/skills/scout/SKILL.md` and write `$PARENT_DIR/index.{md,html}`.

If a child returns blocked/empty, tell the user and let them choose: re-dispatch
that one, drop the angle, or proceed.

## Step 5 — Cover & synthesize (expedition)

Read `$SCOUT_DIR/skills/scout/synthesis.md` and follow it:
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
   its `citations*.jsonl`), `cover: cover.svg` only if step 1 wrote it,
   `duration_sec: <now − START_TS>`, `cost_usd: "sub"`, and 200–600 words of
   cross-cutting synthesis with inline citations. If <2 children succeeded set
   `synthesis: false` per the skill.

**Single-pass:** dispatch `scout-illustrator` for the single artifact
(`RESEARCH_DIR=$PARENT_DIR`), and add `model: "<MODEL>"`, `duration_sec`, and
`cost_usd: "sub"` to its frontmatter. No `manifest.json`, no `children:`.

## Step 6 — Publish

**File into the series first (if one was approved in Step 2).** Run this *before*
`publish.sh` so the `series.yml` edit is swept into the same commit (mirrors
`run-decompose.sh`'s wiring). `add-to-series.sh` edits the cloned checkout's copy
and never creates a new series:

```
bash "$SCOUT_DIR/scripts/add-to-series.sh" \
  "$SCOUT_DIR/atlas-checkout/_data/series.yml" \
  "<date>-<slug>" "<series-slug>" "<group-label>"   # omit group-label for a flat series
```

Then forward the values from Step 3 so the commit message and published URL are
correct (`publish.sh` defaults them to `unknown` otherwise, and needs
`ATLAS_REPO` to build the URL):

```
cd "$SCOUT_DIR" && ATLAS_REPO="<atlas_repo>" SLUG="<slug>" DATE="<date>" \
  TOPIC="<brief title>" bash scripts/publish.sh
```

It commits + pushes `atlas-checkout/` to Atlas `main` and prints
`Published: <url>` — surface that URL to the user.
