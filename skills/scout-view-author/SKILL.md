---
name: scout-view-author
description: Author a bespoke, one-off HTML "view" of an existing canonical research page. Takes a canonical path + a view name, produces a self-contained HTML file at <canonical-dir>/views/<view_name>.html with best-effort sourced images. Each view is its own visual world — pick or invent the register that fits THIS topic. Invoked after a research run when the user has selected which pages deserve a richer presentation.
---

# Scout View Author

You are the view-author. The canonical artifact (an `index.md` or `index.html` somewhere under `atlas/research/...`) already exists and is the source of truth. Your job is to author **one** alternate visual treatment — a "view" — of that canonical.

The canonical is unchanged. You write a new file at `<canonical-dir>/views/<view_name>.html` that the Atlas Jekyll layout will render through `_layouts/view.html`. The default page detects the new file and adds a "Read as: [Default] [Magazine]" pill row in its cover.

**This is not template-filling. It's commissioning a one-off visual treatment.** Read the canonical, decide what the topic wants to feel like, then build it.

## Inputs

```
CANONICAL_PATH:  <absolute path to the canonical's index.md or index.html>
RESEARCH_DIR:    <absolute path to the canonical's directory>
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

Real images dramatically change how a view feels. Try hard. Cap: **8 download attempts per view.**

For each image slot in your design (hero, card thumbnails, etc.):

1. **OG image extraction.** `WebFetch` strips `<head>`, so it won't surface OG tags. Use `curl` directly:
   ```bash
   curl -sL --max-time 10 -A "Mozilla/5.0" "<source-url>" | \
     grep -oiE '<meta[^>]+(property|name)="(og:image|twitter:image)"[^>]*content="[^"]+"' | \
     head -1 | grep -oE 'content="[^"]+"' | sed 's/content="//;s/"$//'
   ```
   If a URL comes back, download it:
   ```bash
   curl -L --max-time 10 -o "<RESEARCH_DIR>/views/<VIEW_NAME>/images/<slug>.jpg" "<og-url>"
   ```
   Verify: file exists, >2KB, valid image (`file <path>` returns `JPEG image data` / `PNG image data` / etc.). If valid, reference as `<img src="<VIEW_NAME>/images/<slug>.jpg" alt="...">`.

2. **Existing assets in the canonical's directory.** If `RESEARCH_DIR/cover.svg` exists, you can use it as `<img src="../cover.svg">` for hero or accent.

3. **Favicon-as-thumbnail (utility, not hero).** Source-card thumbnails inline `<img src="https://www.google.com/s2/favicons?domain=<domain>&sz=128">`. No download — the URL is stable. These work everywhere.

4. **Gradient placeholder with text overlay.** Last resort: `<div class="card-photo" style="background: linear-gradient(135deg, #...);">CARD NAME</div>`. Looks intentional, not missing.

5. **Unicode glyphs as graphic elements.** ⌥ ★ ⊠ ✎ ∞ ↑ ↓ → ← ⚖ 💬 etc. — used at large display sizes (40px+) they become typographic illustrations. Useful when no image source exists but you want graphical density.

A view with 1 OG image + 2 favicons + 3 gradient placeholders is fine. A view with 6 gradient placeholders and zero real images is a sign the topic is image-poor — consider whether the visual register should lean *typographic* (manifesto, poster) instead of *photographic* (magazine).

Place all downloads at `<RESEARCH_DIR>/views/<VIEW_NAME>/images/`. The HTML lives at `views/<VIEW_NAME>.html`, so the correct relative reference is **`<VIEW_NAME>/images/<filename>`** — NOT `images/<filename>` (that resolves to `views/images/...` and 404s).

### 5. Display labels — translate at authoring time

Atlas's chrome auto-translates depth labels at render time, but views are static HTML. Use the **display labels** directly. Never write `ceo` / `standard` / `deep` in user-facing text.

| Internal | Display |
|---|---|
| `ceo` | `recon` |
| `standard` | `survey` |
| `deep` | `expedition` |

GitHub stars: copy the `⭐ N` format from the canonical (`⭐ 52k` for ≥10k, `⭐ 1.2k` for 1–10k, `⭐ 320` raw). Don't refetch.

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
8. **Plan images.** Identify visual slots (hero / card-photos / accent images). For each, run the image strategy chain. Cap 8 download attempts.
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
    - The view doesn't look like it could be the magazine layout for a different topic. It inhabits THIS topic.
12. **Report.** One line: `wrote views/<VIEW_NAME>.html (register=<your-chosen-register>, images: <N> downloaded, <M> favicons, <K> gradients)`.

## Failure modes to avoid

- **Reaching for the most familiar inspiration.** "Cocktails were magazine, so this restaurant must also be magazine." No — pick what fits *this* topic.
- **Inventing URLs not in `links.json`.** The model's tendency is to confabulate paths. Use the JSON exclusively.
- **Recreating layout chrome.** No `<!doctype>`, no back-link in the body, no `<head>` — the `_layouts/view.html` provides them.
- **Writing `ceo`/`standard`/`deep` in user-facing text.** Always translate.
- **Pulling a 50KB OG image without bounds.** Honor the 10-second timeout + filesystem checks.
- **Skipping the `links.json` write.** It's the audit trail and the URL whitelist.
- **Treating gradient placeholders as the goal.** They're the last fallback. Try real images first when the topic is photogenic.
- **Producing template-shaped output.** If your view could be palette-swapped onto a different research topic and still make sense, you've built a template, not a commission. Pull harder for topic-specific identity.
