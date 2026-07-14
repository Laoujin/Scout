---
name: scout-view-author
description: Author a bespoke, one-off HTML "view" of an existing canonical research page. Takes a canonical path + a view name, produces a self-contained HTML file at <canonical-dir>/views/<view_name>.html with best-effort sourced images. Each view is its own visual world — pick or invent the register that fits THIS topic. Invoked after a research run when the user has selected which pages deserve a richer presentation.
user-invocable: false
disable-model-invocation: true
---

# Scout View Author

You are the view-author. The canonical artifact (an `index.md` or `index.html` somewhere under `atlas/research/...`) already exists and is the source of truth. Your job is to author **one** alternate visual treatment — a "view" — of that canonical.

The canonical is unchanged. You write a new file at `<canonical-dir>/views/<view_name>.html` that the Atlas Jekyll layout will render through `_layouts/view.html`. The default page detects the new file and adds a "Read as: [Default] [Magazine]" pill row in its cover.

**This is not template-filling. It's commissioning a one-off visual treatment.** Read the canonical, decide what the topic wants to feel like, then build it.

## Inputs

```
CANONICAL_PATH:  <absolute path to the canonical's index.md or index.html>
RESEARCH_DIR:    <absolute path to the canonical's directory>
SCOUT_DIR:       <absolute path to the Scout install, holds scripts/>
VIEW_NAME:       <slug for the view file, e.g. "magazine" or "manifesto" or "corkboard">
TITLE_SUFFIX:    <optional human-readable name shown in the pill, e.g. "Magazine">
VIBE_HINT:       <optional, one-sentence hint about the desired register, e.g. "tactile and intimate" or "brutalist statement">
```

`run.sh` (when this is wired up) pre-creates `RESEARCH_DIR/views/`. You write `views/<VIEW_NAME>.html` and any image assets in `views/<VIEW_NAME>/images/`.

## Hard rules (non-negotiable)

These five constraints define the contract. Everything else is creative judgment.

### 1. Frontmatter contract

Every view file starts with this exact frontmatter shape:

```yaml
---
layout: view
view_name: "<TITLE_SUFFIX, e.g. Magazine>"
view_of: ../
title: "<canonical title> — <TITLE_SUFFIX>"
---
```

`layout: view` is mandatory (the renderer keys off it). `view_of: ../` is the relative href the back-link uses. Don't add other top-level fields — views don't carry their own citation counts or read times; that's the canonical's job.

### 2. LINKS.json sidecar

Write `views/<VIEW_NAME>.links.json` **before** authoring the view. It is your safe URL list — never invent URLs that aren't in it. Schema:

```json
{
  "atlas":  { "url": "/", "title": "Atlas" },
  "canonical": { "url": "../", "title": "<canonical title>" },
  "parent": { "url": "../../", "title": "<parent title>" } | null,
  "siblings": [
    { "url": "../../<sibling-slug>/", "title": "...", "summary": "...", "depth": "recon|survey|expedition" }
  ],
  "sources": [
    { "n": 1, "url": "https://...", "title": "...", "claim": "...", "source_type": "official|forum|news|...", "github_stars": 12000 | null }
  ]
}
```

How to populate:
- `canonical`: from canonical's frontmatter (`title`).
- `parent`: only if the canonical is a sub-topic. Detect by inspecting the URL path — a sub-topic lives at `research/<parent>/<child>/`, parent at `research/<parent>/`. Read parent's `index.html` frontmatter for its title.
- `siblings`: only if parent exists. Read parent frontmatter's `children:` array. Skip entries with `status: failed`.
- `sources`: read `<RESEARCH_DIR>/citations.jsonl` line by line. Pass through `n`, `url`, `claim`, `source_type`, `github_stars`. Use `url` as `title` when no human-readable title is available.

**Cross-reference rule:** every `<a href>` in the view body must resolve to a URL listed in this file (sources, siblings, parent, canonical, atlas). Never invent paths like `/research/some-other-topic/` — they 404. Free-text "next steps" / "future work" lines stay as plain text without `<a>` tags.

### 3. No JavaScript

Views are fixed HTML+CSS. **No `<script>` tags.** No filter chips that don't filter, no sort dropdowns that don't sort, no "click to expand" buttons that need JS. CSS-only interactivity is fine: `<details>`/`<summary>` for collapse, `:hover`, `:target`, `:has()`. If a wireframe shows a control surface (e.g., the filter chips in `05-research-agents-grid.html`), strip it — those were illustrative of "what could be" and produce a broken UX in a static file.

### 4. Image strategy — best effort, real images first

Real images dramatically change how a view feels. Try hard. There is no cap — fetch as many as the topic earns.

The whole chain lives in **`<SCOUT_DIR>/scripts/fetch-image.sh`**. Use it; never hand-roll the `curl`/`convert`/`rm` pipeline inline.

```bash
bash <SCOUT_DIR>/scripts/fetch-image.sh commons "<subject>"
bash <SCOUT_DIR>/scripts/fetch-image.sh og "<source-url>"
bash <SCOUT_DIR>/scripts/fetch-image.sh fetch "<RESEARCH_DIR>/views/<VIEW_NAME>/images" "<slug>" "<image-url>"
```

`commons` prints a 1200px thumburl, `og` prints the page's `og:image`, `fetch` prints `<slug>.webp`. Exit 1 means *this source came up empty — try the next one*, never "give up on the slot". `fetch` creates the dir, enforces a 10s timeout, rejects non-images and anything under 2KB, downscales to 1600px longest edge, encodes WebP q80, and cleans up its temp file. It is the only thing that may write into the images dir.

**Run each call as its own separate Bash invocation, with the path written out in full.** Do not chain them with `&&`, `||`, `;` or a pipe, do not wrap them in `$(…)`, and do not hoist the path into a shell variable. A local run permission-checks *each subcommand of a compound command separately*, so any chain re-introduces the prompt-per-image that this script exists to remove. Read the URL from one call's output, then pass it as an argument to the next.

For each image slot, **match the source to the subject** and exhaust both real-image sources before any gradient. The `og:image` of a cited page only exists for the specific named thing that page is about — it is useless for a generic subject (a dish, a festival, an animal, a landmark). That mismatch is what produces gradient-filled card grids; Commons is the fix.

1. **Wikimedia Commons (`commons`) — primary for generic & photogenic subjects.** Dishes, landmarks, festivals, markets, flora/fauna, generic activities — the things no single citation page has an `og:image` for — almost always have a Commons photo, license-clean and hotlink-safe. Prefer a specific subject (`cendol penang`) over a generic one (`dessert`), but a clean generic shot beats a gradient every time.

2. **OG extraction (`og`) — primary for named venues/products/businesses.** When the slot is a specific named entity with its own site (restaurant, hotel, attraction, conference), pull its `og:image`. Pass the entity's own URL, not a listicle that mentions it.

So per slot: try `commons` first for a generic subject (or `og` first for a named entity); if it exits 1, try the other; if both come up dry, fall back to a gradient. Then hand the winning URL to `fetch` — as a separate call.

A raw 4–12 MB OG/PNG hero is what makes Atlas slow to publish and pushes it toward the 1 GB GitHub Pages cap — which is why every image goes through `fetch`. Reference the WebP it prints: `<img src="<VIEW_NAME>/images/<slug>.webp" alt="...">`. Never commit a raw `.jpg`/`.png` into a view — WebP only.

3. **Existing assets in the canonical's directory.** If `RESEARCH_DIR/cover.svg` exists, you can use it as `<img src="../cover.svg">` for hero or accent.

4. **Favicon-as-thumbnail (utility, not hero).** Source-card thumbnails inline `<img src="https://www.google.com/s2/favicons?domain=<domain>&sz=128">`. No download — the URL is stable. These work everywhere.

5. **Gradient placeholder — genuine last resort, not a default.** Only after BOTH Commons and OG-extraction have failed for that specific subject. A gradient sitting in a card *photo* slot reads as a broken/missing image — the exact thing this strategy exists to prevent. Fine for *decorative* slots (a section band, a postmark, tape) or a truly unfindable subject; never as a shortcut to skip the search above.

6. **Unicode glyphs as graphic elements.** ⌥ ★ ⊠ ✎ ∞ ↑ ↓ → ← ⚖ 💬 etc. — used at large display sizes (40px+) they become typographic illustrations. Useful when no image source exists but you want graphical density.

Most photo slots should hold real photos. A few favicons (source cards) and the rare gradient for a genuinely unfindable subject are fine; a card grid where a third of the photo slots are gradients means the search was cut short, not that the topic is image-poor — Commons almost always has the generic ones. If a topic *truly* is image-poor, lean the register *typographic* (manifesto, poster) rather than shipping a photo grid full of gradients.

Place all downloads at `<RESEARCH_DIR>/views/<VIEW_NAME>/images/`. The HTML lives at `views/<VIEW_NAME>.html`, so the correct relative reference is **`<VIEW_NAME>/images/<filename>`** — NOT `images/<filename>` (that resolves to `views/images/...` and 404s).

### 5. Display labels — translate at authoring time

Atlas's chrome auto-translates depth labels at render time, but views are static HTML. Use the **display labels** directly. Never write `ceo` / `standard` / `deep` in user-facing text.

| Internal | Display |
|---|---|
| `ceo` | `recon` |
| `standard` | `survey` |
| `deep` | `expedition` |

GitHub stars: copy the `⭐ N` format from the canonical (`⭐ 52k` for ≥10k, `⭐ 1.2k` for 1–10k, `⭐ 320` raw). Don't refetch.

### 6. Named entities link to their official site

When you display an entity by name (project, channel, venue, restaurant, conference, performance) in the view body — in cards, tiles, list rows, prose foregrounds — wrap its name in `<a href="...">` pointing to its **official** URL. The URL must come from `LINKS.json::sources` (the same whitelist that gates rule 2). If no source entry covers the entity, leave the name plain — don't fabricate.

The entity-link is independent of the citation marker. Keep both: `<a href="https://astro.build">Astro</a> ⭐ 52k <sup><a href="https://wirecutter.com/astro-review">[1]</a></sup>`.

Examples:
- GitHub repo: `<a href="https://github.com/Laoujin/Scout">Scout</a>`
- YouTube channel: `<a href="https://youtube.com/@aiexplained">AI Explained</a>` (channel index, not a single video)
- Restaurant: `<a href="https://oak-restaurant.be">OAK</a>` (restaurant's own site)
- Conference: `<a href="https://iconip2026.org">ICONIP 2026</a>` (conference index)
- Performance: `<a href="https://opera.be/opus">OPUS (Bach × Papadopoulos ballet)</a>` (the venue's detail page for that show — not Wikipedia)

If the only source you have is a third-party review or aggregator, that's a citation, not an official site — don't link the entity name to it.

## Creative brief

This is the part that's open, not constrained. Reading order:

1. **Read the canonical.** Notice: what's the topic's emotional register? What does it want the reader to feel?
2. **Read `inspirations.md`** (next to this SKILL). It's a guided tour through eight bold one-off treatments — restaurants as editorial magazine, talk-prep as brutalist stat poster, gifts as tactile corkboard. Study the *thinking*, not the recipes. Each one chose a register that *matched the topic*.
3. **Read VIBE_HINT** if the user provided one. It's a direct steer.
4. **Pick the register.** Maybe one of the eight inspirations fits this topic verbatim. More often, it doesn't — invent something that fits THIS topic. A restaurant guide doesn't have to be magazine; a tools survey doesn't have to be GitHub-card-grid. Surprise.
5. **Build it.** One self-contained HTML file. Inline `<style>` block. Whatever sections fit the topic — cover, hero, cards, timeline, stats, callouts, anything. The wireframes show how varied "good" can look.

The goal is: when the user lands on the view, they think *"oh, that's interesting"* — not *"oh, that's the magazine layout again."* If two views from different topics could be swapped without anyone noticing, you're producing templates, not commissions. Make each one inhabit its topic.

## Quality bar — what makes a view succeed

A view succeeds when it does at least one of these:
- **Surfaces the answer faster than the canonical does.** Verdict callout in 24pt at the top, beats reading three paragraphs to find the same conclusion.
- **Uses graphic elements as graphics.** Big numbers as posters. Quotes as pull-outs. Comparisons as actual visual comparisons (cells, color, position) — not just markdown tables with thicker borders.
- **Earns its visual identity.** A magazine spread feels different from a brutalist poster, which feels different from a corkboard. The visual register telegraphs the topic's register before the reader processes a word.
- **Has actual photos when the topic is photogenic.** Restaurants, places, products, hardware — these want pictures. Don't ship five gradient placeholders with text overlay if real images were extractable.

A view fails when:
- It looks like the canonical's MD with a custom palette and one extra `<table>`. That's the wrong layer.
- It uses a familiar template visual that doesn't fit the topic (gift-list rendered as GitHub-card-grid).
- The `<a href>`s 404 because URLs were invented.
- Photos appear as broken-image icons because file checks were skipped.

## Procedure

1. **Parse inputs.** Note paths and any vibe hint.
2. **Read the canonical** (`CANONICAL_PATH`). Extract: title, summary, tags, body content, depth, citations count. Form an internal model of the topic's register and what it most needs to communicate.
3. **Read citations ledger** (`<RESEARCH_DIR>/citations.jsonl`) if present. Parse line by line.
4. **Detect parent** if any (URL path inspection per the rules). Read parent's frontmatter for title and `children:` list.
5. **Build `links.json`** and write it to `<RESEARCH_DIR>/views/<VIEW_NAME>.links.json`.
6. **Read `inspirations.md`** in this skill directory. Study the eight case studies for breadth.
7. **Decide the visual register.** What does this topic want to feel like? Reach for an inspiration if one fits. Invent if none fits.
8. **Plan images.** Identify visual slots (hero / card-photos / accent images). For each, run the image strategy chain. No cap on download attempts — pull as many as the topic earns. Per-download timeout (10s) and validity checks still apply.
9. **Author the view.** Single `Write` to `<RESEARCH_DIR>/views/<VIEW_NAME>.html`. Frontmatter + inline `<style>` + body sections. No `<!doctype>`, `<html>`, `<head>`, `<body>` — the layout provides them. No `← Default view` link — the layout provides that too.
10. **Verify image paths — MANDATORY, not optional.** Every previous batch shipped with broken `<img src>` paths because the author "checked" by reading instead of running. Run this exact command after writing the view:

    ```bash
    grep -oE 'src="[^"]+\.(jpg|jpeg|png|gif|svg|webp)"' "<RESEARCH_DIR>/views/<VIEW_NAME>.html" \
      | sed -E 's/src="//;s/"$//' \
      | grep -vE '^(https?:|//|data:)' \
      | while read p; do
          [ -f "<RESEARCH_DIR>/views/$p" ] || echo "BROKEN: $p"
        done
    ```

    Empty output = pass. Any `BROKEN:` line = fix the `src` attribute (almost always: missing `<VIEW_NAME>/` prefix) and re-run until clean. Do not proceed to step 11 with broken paths.

11. **Self-check the rest:**
    - Frontmatter has `layout: view`, `view_name`, `view_of: ../`, `title`. No other fields.
    - No `<!doctype>` / `<html>` / `<head>` / `<body>` / `<script>` tags.
    - All `<a href>` URLs come from `links.json` or are inline citation URLs from the ledger.
    - No `ceo` / `standard` / `deep` strings anywhere.
    - Source-card favicons (when used) use `s2/favicons` URLs.
    - **No gradient in a card *photo* slot** unless that subject was searched on BOTH Wikimedia Commons and OG-extraction and genuinely returned nothing. Grep your file for `linear-gradient` in photo/card/tile slots and re-source any that are just unfilled — generic subjects (dishes, festivals, landmarks, animals) are exactly what Commons covers.
    - **No negative `margin` on the outer wrapper.** The layout already gives you full-bleed (`html, body { margin: 0; padding: 0; }`); patterns like `margin: -2rem -2rem 0` to "break out of gutters" pull content above the viewport and clip the top. Use `margin: 0` and lay out within the wrapper.
    - The view doesn't look like it could be the magazine layout for a different topic. It inhabits THIS topic.
12. **Report.** One line: `wrote views/<VIEW_NAME>.html (register=<your-chosen-register>, images: <N> downloaded, <M> favicons, <K> gradients)`.

## Failure modes to avoid

- **Reaching for the most familiar inspiration.** "Cocktails were magazine, so this restaurant must also be magazine." No — pick what fits *this* topic.
- **Inventing URLs not in `links.json`.** The model's tendency is to confabulate paths. Use the JSON exclusively.
- **Recreating layout chrome.** No `<!doctype>`, no back-link in the body, no `<head>` — the `_layouts/view.html` provides them.
- **Writing `ceo`/`standard`/`deep` in user-facing text.** Always translate.
- **Pulling a 50KB OG image without bounds.** Honor the 10-second timeout + filesystem checks.
- **Skipping the `links.json` write.** It's the audit trail and the URL whitelist.
- **Reaching for a gradient before trying Wikimedia Commons.** OG-extraction failing for a generic subject (a dish, a festival, an animal, a landmark) is not license to gradient — that's precisely what Commons is for. Gradients are the last fallback after both sources fail, and only ever in a photo slot if the subject is truly unfindable.
- **Breaking out of layout gutters that don't exist.** `_layouts/view.html` zeros body margin/padding — there is nothing to escape. Negative top margin on the outer wrapper clips the first ~24–32px above the viewport. This bug was recurring across multiple views; the fix is to never reach for the breakout pattern.
- **Producing template-shaped output.** If your view could be palette-swapped onto a different research topic and still make sense, you've built a template, not a commission. Pull harder for topic-specific identity.
