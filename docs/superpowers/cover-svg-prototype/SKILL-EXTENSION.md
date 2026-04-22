# Cover SVG — SKILL extension draft

**Status:** DRAFT. Not applied anywhere yet. Evaluate the prototype at [`./index.html`](./index.html) first; commit only if the aesthetic holds up when you actually look at it in cards.

## What this is

Claude-drafted SVG cover images for each research artifact. Zero external API, zero new tokens, palette-matched to Atlas. See [`./index.html`](./index.html) for six hand-drafted examples (drafted by me deliberately, not on a real Scout run — so this is the *ceiling* of what to expect, not the floor).

Three ways forward from here:

| Option | What it is | Risk |
|---|---|---|
| **(i) Commit as-is** | Paste the SKILL section below into `skills/scout/SKILL.md`, wire Atlas layout to use `{{ page.cover }}`. First real run is the live test. | Cold-run quality may drift from prototype. Visible on Atlas before you get to review. |
| **(ii) Test first** | Open a throwaway issue, let Scout run with the extended SKILL, judge the output, **then** commit or iterate. | Slower, but avoids "my Atlas has an ugly cover" embarrassment. Recommended. |
| **(iii) Hedge with curated** | Commit the SKILL *and* ship `atlas/assets/covers/{tag}.svg` (~8 tag-keyed fallbacks). If Claude's SVG is weak on a run, drop it and use curated. | More upfront work. Highest safety. |

## Section to add to `skills/scout/SKILL.md`

Paste verbatim after the `## Supporting assets (images, data, screenshots)` section and before `## Inputs (parsed from the prompt)`.

---

```markdown
## Cover image (SVG, 3:2)

After writing `index.{md,html}`, also write a `cover.svg` in the same folder at `viewBox="0 0 600 400"`, then add `cover: cover.svg` to the frontmatter. Atlas's card layout will use it on the index page.

### Style guide — hard rules

- **No `<text>`, no letters, no numbers, no human faces.** Ever. AI-rendered text is ugly and layout wraps the title anyway.
- **2–4 main shapes; one clear hero element.** Avoid cluttered micro-shape grids.
- **Opacity layered 0.6–0.95.** Use `<linearGradient>` / `<radialGradient>` for depth.
- **Under 4 kB and under 60 elements.** If you're exceeding either, you're overworking.
- **Palette: rust family primary, topic-hue secondary.**

  Rust family (always):
  - `#c2410c` `#9a3309` `#78350f` `#d97706` `#fbbf24`
  - Backgrounds: `#faf8f2`, `#f0eadb`, `#fef3ec`, or dark `#1a0e0e`/`#5c2a1a` for nocturnal topics

  Topic-hue secondary (one, picked from the primary tag):
  | Tag bucket | Hue |
  |---|---|
  | ai / agents / research | `#6d28d9` (violet) |
  | food / restaurants / drink | `#be185d` (rose) |
  | hardware / homelab / infra | `#334155` (slate) |
  | web / tooling / software | `#0e7490` (teal) |
  | personal / ideas / lifestyle | `#d97706` (amber — stays in rust family) |
  | mcp / self-hosted / devops | `#0e7490` (teal) |
  | unclassified | omit secondary, rust-only |

### Composition inspiration by topic kind

These are suggestions, not templates. Invent when a topic doesn't fit:

- **Software / tools / libraries** — stacked rectangles (like pages), offset grids, flow arrows
- **Restaurants / food / drink** — round forms (plates), warm radial glow, dark bg
- **Hardware / infra** — isometric cubes, stacks of chassis, single LED accent
- **AI / agents** — concentric orbits, node-and-edge graphs, central hub
- **Gifts / personal** — overlapping boxes, ribbon paths, confetti
- **Self-hosted / MCP / protocols** — interlocking blocks, plug/port shapes, spark trails
- **Essays / SOTA / philosophy** — if no concrete motif feels honest: skip cover entirely (see fallback below).

### Fallback

If you cannot confidently produce a clean SVG for this topic (too abstract, no clear motif, you're second-guessing the composition, would need more than ~60 elements): **skip it.** Omit the `cover:` frontmatter field. Atlas renders the typographic fallback (tag-tinted watermark card). An absent cover is better than a muddled one.
```

---

## Atlas-side changes needed

Two layout changes. The card partial (probably `_includes/research-card.html` or similar) becomes:

```liquid
{% if page.cover %}
  <img class="cover" src="{{ page.url | append: page.cover }}" alt="">
{% elsif page.tags %}
  {%- assign primary = page.tags | first -%}
  {%- assign curated = '/assets/covers/' | append: primary | append: '.svg' -%}
  {%- if site.static_files contains curated -%}
    <img class="cover" src="{{ curated | relative_url }}" alt="">
  {%- else -%}
    {% include cover-typographic.html %}
  {%- endif -%}
{% else %}
  {% include cover-typographic.html %}
{% endif %}
```

And `_includes/cover-typographic.html` is the V6 fallback (CSS-only, gradient + watermark letter from first tag). Full CSS is in `docs/atlas-card-mockups.html` V6 section.

## Evaluation protocol (for option ii — the recommended path)

1. **Paste the SKILL section** into `skills/scout/SKILL.md` locally — don't push yet.
2. **Open a test issue** on your Scout repo with a topic that has a concrete motif (a "medium difficulty" case). Good candidates:
   - `[research] Best espresso machines under €500`  (food → rose)
   - `[research] Budget mechanical keyboards 2026`  (hardware → slate)
3. **Let Scout run.** Check the research folder on the Atlas side — is `cover.svg` there? Open it in a browser. Honest test: does it look like one of the six prototypes, or worse?
4. **Try a hard case too:** a non-concrete topic. Something like `[research] What makes a good product manager` — Scout should hit the fallback and omit `cover:`. Verify it did.
5. **Judgement call.** If the easy case looks good and the hard case correctly skipped: commit. If either fails: iterate on the SKILL prompt (tighten constraints, add negative examples) and repeat.

## Open questions to answer during evaluation

- Does Claude actually follow the size cap (4 kB / 60 elements)? Or drift into 15 kB monsters?
- Does the topic-hue table cover enough tag buckets, or do new tags keep falling into "unclassified"?
- Are the composition hints too prescriptive (cookie-cutter output) or too loose (inconsistent aesthetic)?
- Does the "skip if unsure" fallback actually fire, or does Claude always produce *something*?

Answers to these should steer the next revision of this doc before committing.

## When you've decided

- **Going with (i) or (ii):** apply the SKILL section, wire Atlas, delete this file.
- **Going with (iii):** same, plus create `atlas/assets/covers/{ai,food,hardware,web,mcp,personal,homelab,default}.svg` — can draft them from the prototype set here.
- **Not going with Claude-SVG at all:** delete this file and `docs/cover-svg-prototype/`. Revisit Nano Banana path (option a from the prior round).
