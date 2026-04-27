---
name: synthesis
description: Synthesise an expedition overview from N child research artifacts into a parent index. Invoked by scripts/run-decompose.sh after the children loop terminates.
---

# Synthesise an expedition overview

You receive the parent topic, a list of child sub-topics with their results, and write the parent `index.md`. The parent has two parts: synthesis prose at the top, an auto-generated children index below.

## Inputs

```
PARENT_TOPIC: <sharpened topic statement>
PARENT_DIR:   <absolute path to atlas/research/<DATE>-<slug>/>
CHILDREN:     <JSON array of {slug, title, depth, status, summary}>
DATE:         <YYYY-MM-DD>
FORMAT:       <md | html | auto>
SUCCESS_COUNT: <int — children with non-placeholder index.md>
```

`CHILDREN[i].summary` is pulled from each child's frontmatter. For failed children, `status: failed` and `summary` is the failure reason.

## Rules

1. **Honesty about gaps.** If a child failed or was skipped, *say so* in the synthesis prose. Do not paper over missing angles. Sentence template: "The <title> angle was not researched in this run (reason: <failure_reason>)."

2. **Cross-cutting only.** Don't re-summarise each child individually — the auto-generated index below the synthesis already lists each child's title and summary. The synthesis must add value beyond the sum: themes, contradictions, dependencies between angles, a unified recommendation, open questions left after all children ran.

3. **Citation discipline.** Inherits the Scout citation rule (`scout/CLAUDE.md`): every factual claim, quote, number, or summary line MUST carry its source URL inline. When citing across children, link to the child's URL using a relative link like `<child-slug>/#section`. When citing a fact from a child, copy the original source URL (don't reference the child as the source — the child cited the original).

4. **Length.** 200–600 words for the synthesis prose. No filler.

5. **No conclusion paragraph.** End on the sharpest open question or the strongest recommendation, not "in conclusion."

## Procedure

1. **Dispatch `scout-illustrator` for the cover.** Call `Agent(subagent_type="scout-illustrator", ...)` with a brief that contains `TOPIC=PARENT_TOPIC`, the final `tags` list (3–5 tags spanning the expedition), and `RESEARCH_DIR=PARENT_DIR`. It returns `wrote cover.svg` or `skipped: <reason>`. Record which — you will reference it in step 2's frontmatter.

   This is **required**, not optional. Skipping it leaves the expedition card on Atlas's homepage without a cover image. The agent itself decides whether to draft or skip; your job is to call it.

2. **Write the parent index.** Drop the file at `PARENT_DIR/index.md` (or `PARENT_DIR/index.html` if FORMAT=html). Do NOT print to stdout. If step 1 returned `wrote cover.svg`, include `cover: cover.svg` in the frontmatter; otherwise omit the field.

## Output

The file structure must be:

```yaml
---
layout: expedition
title: <inferred title>
date: <DATE>
topic: <PARENT_TOPIC>
format: <FORMAT>
tags: [tag1, tag2, tag3]              # 3–5 tags spanning the expedition's scope
summary: One sentence shown on the Atlas index card.
cover: cover.svg          # only if scout-illustrator returned wrote cover.svg
synthesis: true
children:
  - slug: <child slug>
    title: <child title>
    depth: <recon|survey|expedition>
    status: <success|failed>
    summary: <copied from child frontmatter or failure_reason>
    citations: <int>           # only when success
    reading_time_min: <int>    # only when success
---

<synthesis prose, 200-600 words, with inline `[[n]](url)` citations>
```

**`tags` and `summary` are required.** Atlas's homepage card uses `summary` as the description and `tags` as the chip row; without them the card is title-only. Pick `tags` that span the expedition (not duplicates of any single child's tags). Write `summary` to read as the expedition's elevator pitch, distinct from any child's summary.

The orchestrator (`run-decompose.sh`) injects `citations`, `reading_time_min`, `cost_usd`, and `duration_sec` (parent synthesis + sum of successful children) after this skill returns. Do NOT include those four fields yourself.

The Atlas `expedition` layout renders the `children` frontmatter as a card grid below the synthesis — you do NOT need to list children in the body. Only write the synthesis prose.

If SUCCESS_COUNT < 2, set `synthesis: false` and write a one-sentence body ("Synthesis skipped — only <SUCCESS_COUNT> sub-topic(s) produced output. See child page(s) below.") without citations. The layout will still render the children grid.
