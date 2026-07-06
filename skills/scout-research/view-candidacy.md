---
name: view-candidacy
description: Decide which research pages of a freshly-published Scout run deserve a bespoke HTML "view" alternative, and pick a register for each. Invoked once per run with the manifest of pages plus their frontmatter excerpts. Outputs strict JSON.
---

# View candidacy — judge whether each page wants a custom HTML view

You are the judge. A research run just finished and produced one or more canonical pages. Your job: for each page, decide whether it would benefit from a bespoke HTML "view" alternative, and if yes, suggest a register and view-slug.

The default rendering is the canonical's MD. A "view" is an additional, hand-styled HTML treatment that lives at `<canonical-dir>/views/<view_name>.html`. Views are expensive to author — only suggest them when the topic genuinely benefits.

## Inputs (parsed from the prompt)

```
RUN_KIND: <single | decompose>
PARENT_PATH: <path to parent dir under atlas/research/, or empty for single-pass>
PAGES: <JSON array; see schema below>
```

`PAGES` is an array of:

```json
{
  "row": "parent" | "leaf",
  "slug": "<dir basename>",
  "path": "research/<date>-<slug>",
  "title": "<canonical title from frontmatter>",
  "summary": "<canonical summary from frontmatter, possibly empty>",
  "depth": "ceo" | "standard" | "deep",
  "citations": <int>,
  "format": "md" | "html"
}
```

## Output (strict JSON)

```json
{
  "items": [
    {
      "row": "parent" | "leaf",
      "slug": "<same as input>",
      "path": "<same as input>",
      "title": "<same as input>",
      "should_offer_view": true | false,
      "view_name": "<slug, lowercase, hyphenated; e.g. \"masthead\" | \"bookshelf\" | \"calendar\">" | null,
      "title_suffix": "<short human-readable register name; e.g. \"Masthead\" | \"Bookshelf\">" | null,
      "vibe_hint": "<one short sentence describing the visual register; e.g. \"print-newsletter masthead, broadsheet typography\">" | null
    }
  ]
}
```

`should_offer_view: false` ⇒ all of `view_name`, `title_suffix`, `vibe_hint` are `null`.
Output ONLY the JSON object. No prose, no fenced code blocks. The first character of your output must be `{`.

## Qualitative criteria

A page is "visually worth a custom view" when at least one of these applies:

1. **Photogenic subject.** Restaurants, hardware, products, events, places — anything that has real-world OG images worth foregrounding.
2. **Comparison-shaped data.** Specs across multiple options, feature matrices, benchmark tables — registers like "dashboard", "scoreboard", "spec sheet" exploit this.
3. **Strong emotional register.** A topic where typography and layout add meaning (manifestos, retrospectives, eulogies, anniversary roundups) — a custom register makes the canonical feel intentional rather than generic.
4. **Register match with an inspiration.** The page's content shape lines up with one of the view-author inspirations (`skills/scout-view-author/inspirations.md` — currently 8 case studies). E.g. a list of YouTube channels → storyboard register; a list of newsletters → masthead.

Pages that DO NOT benefit and should get `should_offer_view: false`:

- Recon notes / decision pages — text-heavy with single conclusion.
- Tech-review essays where the prose carries the meaning.
- Pages with very few citations (≤ 2) — not enough source material to populate a rich view.
- Pages whose canonical is already `format: html` (the canonical IS the bespoke HTML; a separate view is redundant).

## Override rules

- The orchestrator forces `should_offer_view: true` for `row: "parent"` regardless of your output. Still pick a sensible `view_name` / `title_suffix` / `vibe_hint` for parents — the orchestrator uses your suggestion when displaying the row.
- Never propose `view_name: "default"` (reserved by the renderer).
- `view_name` MUST be unique within the same parent's children — if you pick `magazine` for one leaf, pick a different register for sibling leaves even if they're similar.

## Register vocabulary

Pick from existing inspirations or invent one that fits. Common choices:

| view_name | Register |
|---|---|
| `magazine` | print-magazine layout, drop caps, columns |
| `masthead` | newsletter masthead, broadsheet typography |
| `bookshelf` | rare-book dealer's spine catalogue |
| `dashboard` | live-data console, KPI tiles |
| `storyboard` | shot-list / film-storyboard register |
| `calendar` | chronogram / firing-pattern grid |
| `corkboard` | pinned-card collage |
| `manifesto` | poster-text, oversized typography |
| `catalog` | ecommerce / product-catalog grid |

Don't be a slave to this list — invent if the topic earns it.

## Examples

(Decompose run, expedition with 4 children:)

Input PAGES:
```json
[
  {"row":"parent","slug":"high-signal-ai","path":"...","title":"High-signal AI software creators","summary":"Curated list of bloggers, YouTubers, X accounts…","depth":"deep","citations":42,"format":"md"},
  {"row":"leaf","slug":"long-form-bloggers","path":"...","title":"Long-form bloggers & newsletter authors","summary":"…","depth":"standard","citations":12,"format":"md"},
  {"row":"leaf","slug":"youtube-channels","path":"...","title":"YouTube channels","summary":"…","depth":"standard","citations":8,"format":"md"},
  {"row":"leaf","slug":"x-twitter-accounts","path":"...","title":"X / Twitter accounts","summary":"…","depth":"standard","citations":15,"format":"md"},
  {"row":"leaf","slug":"podcasts","path":"...","title":"Podcasts","summary":"Mostly text descriptions, few thumbnails available","depth":"standard","citations":6,"format":"md"}
]
```

Expected output:
```json
{"items":[
  {"row":"parent","slug":"high-signal-ai","path":"...","title":"High-signal AI software creators","should_offer_view":true,"view_name":"masthead","title_suffix":"Masthead","vibe_hint":"print-newsletter masthead, broadsheet typography across the four sub-channels"},
  {"row":"leaf","slug":"long-form-bloggers","path":"...","title":"Long-form bloggers & newsletter authors","should_offer_view":true,"view_name":"bookshelf","title_suffix":"Bookshelf","vibe_hint":"rare-book dealer's spine catalogue"},
  {"row":"leaf","slug":"youtube-channels","path":"...","title":"YouTube channels","should_offer_view":true,"view_name":"storyboard","title_suffix":"Storyboard","vibe_hint":"shot-list storyboard with thumbnails"},
  {"row":"leaf","slug":"x-twitter-accounts","path":"...","title":"X / Twitter accounts","should_offer_view":false,"view_name":null,"title_suffix":null,"vibe_hint":null},
  {"row":"leaf","slug":"podcasts","path":"...","title":"Podcasts","should_offer_view":false,"view_name":null,"title_suffix":null,"vibe_hint":null}
]}
```
