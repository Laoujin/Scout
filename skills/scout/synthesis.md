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

## Output

Write the parent `index.md` (or `index.html` if FORMAT=html) directly to `PARENT_DIR/index.md`. Do NOT print to stdout.

The file structure must be:

```yaml
---
layout: expedition
title: <inferred title>
date: <DATE>
topic: <PARENT_TOPIC>
format: <FORMAT>
synthesis: true
citations: <sum of CHILDREN[i].citations across status:success>
reading_time_min: <sum across status:success>
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

The Atlas `expedition` layout renders the `children` frontmatter as a card grid below the synthesis — you do NOT need to list children in the body. Only write the synthesis prose.

If SUCCESS_COUNT < 2, set `synthesis: false` and write a one-sentence body ("Synthesis skipped — only <SUCCESS_COUNT> sub-topic(s) produced output. See child page(s) below.") without citations. The layout will still render the children grid.
