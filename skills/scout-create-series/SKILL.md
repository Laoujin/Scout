---
name: scout-create-series
description: Use to CREATE a new Atlas series — pick the title/blurb, triage which existing research belongs in it, choose optional category labels, author a cover SVG, and scaffold the series.yml block + page stub. Human-invoked curation (the complement to series-suggestion, which only auto-adds entries to series that already exist). Run when you want to group already-published research under a new /series/<slug>/ page.
user-invocable: false
disable-model-invocation: true
---

# Scout create-series — author a new Atlas series

## Overview

A *series* groups related Atlas research under `/series/<slug>/`. Scout's automated
`series-suggestion` flow only adds new entries to series that **already exist** — inventing a
new series is a human decision. This skill is that human-driven half: it walks you from a topic
idea to a complete, reviewable series in the Atlas working tree.

Deterministic file edits are done by `scripts/create-series.sh` (scaffold) and
`scripts/add-to-series.sh` (members). The judgment — title, blurb, *which research belongs*,
group labels, cover art — is yours, with this skill's guidance.

**Boundaries (hard):** you only edit the Atlas **working tree** (`_data/series.yml`,
`series/<slug>.md`, `series/<slug>.svg`). You do **not** commit or push — the human reviews and
commits. Never edit existing series membership here (that's `add-to-series.sh` / series-suggestion).

## When to use

- A cluster of published research shares a theme worth a landing page (e.g. a city/topic series).
- You want to hand-curate a new grouping that the auto-suggester would never create on its own.

## Inputs

- **ATLAS_DIR** — the Atlas checkout. Use `$ATLAS_DIR` if set, else a sibling `../atlas`, else ask.
  `local-setup.sh` can provide one. The manifest is `$ATLAS_DIR/_data/series.yml`.

## Flow

### 1. Definition

- Get a **title** from the human (or propose one). Derive the **slug** with the repo's slugifier:
  `source scripts/slug.sh && slugify "<title>"`.
- Check for collision: if `grep -qE "^- slug: <slug>$" "$ATLAS_DIR/_data/series.yml"` matches, the
  slug is taken — pick another or stop. (`create-series.sh` also enforces this and aborts.)
- Get a one-line **blurb** (or propose one; keep it under ~12 words, matches the existing entries' tone).

### 2. Triage — which research belongs (judgment)

- List candidates: read frontmatter across `$ATLAS_DIR/research/*/index.{md,html}` —
  `title`, `date`, `tags`, `summary`. (Grep/Read directly; there is no scan helper for this yet.)
- Rank by genuine topical overlap with the series definition. **Propose** a candidate list to the
  human with one-line reasons. Be conservative: do **not** pre-select on weak signal — the human
  confirms the final member set. They can add any entry you missed.
- Record each confirmed member's directory slug (the `research/<dir>` name).

### 3. Category labels (optional)

- Decide grouped vs flat **with the human**. If the members split cleanly along a facet (country,
  topic, audience), propose ordered group labels and assign each member to one. Otherwise keep it flat.

### 4. Cover SVG (tone of `hero-banner.png`)

Author `$ATLAS_DIR/series/<slug>.svg`. Project 1 uses it as the s1/s5 hero background, so keep it
**title-less and abstract** (text sits on top). Match the muted, cartographic tone. Start from this
template and vary the palette hues + motif per series:

```svg
<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 1200 480" preserveAspectRatio="xMidYMid slice">
  <rect width="1200" height="480" fill="#eceff4"/>
  <g fill="none" stroke="#9aa7bd" stroke-width="1.5" opacity="0.55">
    <path d="M0 120 Q300 60 600 120 T1200 120"/>
    <path d="M0 220 Q300 160 600 220 T1200 220"/>
    <path d="M0 320 Q300 260 600 320 T1200 320"/>
    <path d="M0 420 Q300 360 600 420 T1200 420"/>
  </g>
  <g fill="#5b6b86" opacity="0.5">
    <circle cx="240" cy="160" r="6"/><circle cx="560" cy="250" r="6"/>
    <circle cx="880" cy="180" r="6"/><circle cx="1020" cy="330" r="6"/>
  </g>
</svg>
```

Keep the `viewBox="0 0 1200 480"` aspect so `background-size: cover` crops cleanly. No `cover:`
line is needed in `series.yml` — Project 1 resolves `series/<slug>.svg` by convention.

### 5. Scaffold + members (deterministic)

Scaffold the block and stub:

```bash
# grouped:
scripts/create-series.sh "$ATLAS_DIR/_data/series.yml" "<slug>" "<title>" "<blurb>" \
  --group "<Label A>" --group "<Label B>"
# flat: omit all --group flags.
```

Then add each confirmed member (group label only for grouped series):

```bash
scripts/add-to-series.sh "$ATLAS_DIR/_data/series.yml" "<entry-dir-slug>" "<slug>" "<Label A>"
```

`add-to-series.sh` is idempotent and fail-soft — safe to re-run. Note: its idempotency
is **file-global** — an entry already listed in *any* series silently no-ops (single-membership
is by design). If a confirmed member doesn't appear, it already belongs to another series; pick a
different entry or move it deliberately by hand.

### 6. Review

Print a summary: slug, title, group→member counts, the cover path. Tell the human to review the
working tree (`git -C "$ATLAS_DIR" diff`, the new `series/<slug>.svg`, and a local
`compass/serve.ps1` preview) and to **commit it themselves**. Do not commit or push.

## Guardrails

- Conservative triage: propose, never force. The human owns the final membership.
- One series per run. No multi-series membership.
- Never overwrite an existing series, stub, or cover.
- Never `git commit`/`git push` — leave a clean, reviewable working tree.
