# Inspirations — eight case studies

Eight bold one-off treatments. **Don't use these as templates.** Use them as breadth examples — the vocabulary of "what registers are possible." When you author a new view, ask: which of these (or something else entirely) fits *this* topic?

Each entry: the wireframe path, the topic it was built for, the register chosen, why it worked, and what's transferable.

---

## 01 · Magazine spread — `atlas/html-wireframes/01-cocktail-magazine.html`

**Topic it served:** five cocktail bars in Ghent — drinks-first venues with a clear hero (Jigger's) and supporting cast.

**Register:** *editorial print magazine.* Masthead at top, oversized serif headline, kicker tags, hero spread (1 dominant venue with pull-quote and tags), supporting card grid, optional "plan the night" itinerary section, colophon-style footer. Warm cream-and-rust palette. Fraunces serif at 128px for the cover headline.

**Why it worked:** restaurants are *places*. They want photographs. They benefit from editorial hierarchy — there's always a recommended pick and supporting picks. The print-magazine register signals "considered, curated" rather than "exhaustive list." The reader sees the hero before they see anything else.

**Transferable to:** any curated list of 4-7 things where one is the headline. Restaurants, hotels, products, books, events. Not transferable when the canonical is comparison-dense (use a different register) or when there's no clear hero.

**Risk profile:** highest image-dependency. Without 3+ real photos this register collapses to "headlines over gradients." Try harder on image extraction here.

---

## 02 · KPI dashboard — `atlas/html-wireframes/02-dining-dashboard.html`

**Topic it served:** the parent expedition for Ghent dining — synthesis of seven angles, ★4 Michelin, a 2024-2026 timeline of openings/closures, a "consensus pin" that recurred across angles.

**Register:** *Bloomberg-terminal-meets-magazine.* Sticky topbar with breadcrumb + monospace pill stats. Dark panels with gold accents. KPI boxes (huge numbers + tiny labels). A featured "pin" panel for the consensus pick, with the watermark name in 200px type behind. A timeline as colored dots on a horizontal line. Child-tile grid below.

**Why it worked:** the parent's job is to *map the territory* across multiple sub-topics. The dashboard register privileges navigation and high-level pattern over narrative. KPIs and timeline use real estate that prose never could. Zero image dependence — gradients carry the whole thing.

**Transferable to:** any expedition synthesis with strong numeric or chronological structure. Survey roundups. State-of-the-X reports. Annual reviews. Not transferable when the canonical is single-topic — there's no children to tile.

**Risk profile:** safe. Zero image downloads. Failure mode is "looks too corporate for the topic" — counter by leaning into typographic flair (the giant gold serif numbers) rather than full Bloomberg sterility.

---

## 03 · Brutalist stat poster — `atlas/html-wireframes/03-ai-security-stat-poster.html`

**Topic it served:** the AI-security talk reframe. The synthesis recommended grafting in four 2026 angles backed by punchy numbers (54% phishing click rate, $40B fraud, $893M FBI losses, 440K NCMEC reports).

**Register:** *Stefan Sagmeister manifesto.* Yellow-red-blue-black palette. Archivo Black slab type at 200px. Each statistic gets its own full-width band — different background color, the number giant, the source caption tiny. Vertical scroll like a printed broadside. Closing band: defenses. Final band in red: the open question.

**Why it worked:** when the canonical's *point* is "these numbers should make you uncomfortable," the visual register should be uncomfortable too. A KPI dashboard makes scary numbers look corporate. A brutalist poster makes them feel like wall graffiti. The register reinforces the canonical's argument.

**Transferable to:** topics where statistics ARE the argument — security risks, public-health numbers, electoral findings, accessibility audits, "things people don't realize are this bad" content. Talk-prep where the deliverable is the slides.

**Risk profile:** medium. The visual register is loud — wrong topic and it reads as melodrama. Right topic and it's the most memorable view in the repo. Don't reach for this for "10 nice cookbooks."

---

## 04 · Talk storyboard — `atlas/html-wireframes/04-ai-security-storyboard.html`

**Topic it served:** the AI-security talk reframe (alternate angle on the same canonical as 03). Six attention chunks, each one story → mental model → escalation → pivot → contradict → close.

**Register:** *film storyboard / pitch deck.* Dark backdrop. Horizontal scrollable reel of 6 panels. Each panel: SCENE slate top (like a clapper), gradient-and-emoji frame, beat callouts, key stat, suggested visual. Bottom ribbon: 6 keep/cut/graft decision cards from the talk's existing-deck triage.

**Why it worked:** talk prep is *sequential* — slide order matters, narrative arc matters. The reel format makes the sequence the dominant visual axis. Each panel is a "scene" the speaker can rehearse. The keep/cut/graft ribbon makes the strategic-edit decisions concrete.

**Transferable to:** anything narrative or sequenced. Workshop curricula. Pitch flows. Multi-step product demos. User-journey maps. Not transferable when the canonical is unordered comparisons.

**Risk profile:** medium. Each panel needs a plausible visual mock — gradient + glyph for v1, custom SVG illustrations for v2. Six bespoke panels is more authoring effort than other registers.

---

## 05 · GitHub-flavored card grid — `atlas/html-wireframes/05-research-agents-grid.html`

**Topic it served:** survey of 14 deep-research tools and Claude Code skills with multiple comparable axes (license, kind, citation rigor, scout-fit).

**Register:** *GitHub repo browser meets dashboard.* Dark theme. Each card: favicon-as-logo, title, org, ⭐ stars badge top-right. Color-coded fit indicator on top edge (green/amber/red). Kind and license as small monospace pills. Two-up "specs" mini-grid. Scout-fit pill ("HIGH" / "MEDIUM" / "LOW") with one-line rationale. "Steal" highlight for cross-cutting takeaways. Cards sorted by fit DESC then stars DESC.

**Why it worked:** a tools survey is comparison-shaped at its core. The GitHub-card register feels native to the audience (developers) and uses well-understood primitives (stars, favicons, license badges). The fit-color border lets the eye scan in seconds.

**Transferable to:** any technical-tool comparison, library roundup, framework survey. Hardware-product comparisons (with product photos instead of favicons). Less appropriate for non-technical audiences.

**Risk profile:** low for technical topics. Favicons always work, stars copy from canonical. Can render with zero downloads. If the canonical lacks a clear fit-axis ("which to use for X"), the color borders feel arbitrary — pick a different register.

---

## 06 · Polaroid corkboard — `atlas/html-wireframes/06-birthday-gifts-polaroid.html`

**Topic it served:** the one-page girlfriend birthday gift brief — 7 candidates with price/lead-time/relationship-fit.

**Register:** *physical corkboard with handwritten notes.* Tiled cork background. A title-note tilted -2°. A yellow sticky-note in the corner with the decision rules in handwritten Caveat font. Each gift as a Polaroid: white frame with off-center tape, gradient "photo" with the gift name in marker font, masking-tape price/lead-time stamps, a red sticker tagging the relationship-fit. A torn-edge yellow page at the bottom for the decision ladder. A red push-pin in the top-center of every Polaroid.

**Why it worked:** the topic is *intimate* — picking a gift for a partner, a small private decision. The corkboard register matches the register of the topic. A spreadsheet view of 7 gifts feels clinical; a magazine view feels gift-shop-glossy; a corkboard view feels like the way you'd actually plan this — pinning ideas, ranking, sticky-noting reasons. **Register matches subject matter.**

**Transferable to:** intimate / personal / small-decision content. Mood boards. Kid-related lists. Travel-trip planning. Anything where "spreadsheet rigor" would feel cold. Not for technical or comparison-heavy topics.

**Risk profile:** medium. Hard to pull off with limited graphic assets — the visual identity *is* the typographic playfulness (Caveat handwriting, Permanent Marker stamps, photo gradients). Half-committed it looks cheesy; fully committed it's the most-shared view in the repo.

---

## 07 · Glossy catalog — `atlas/html-wireframes/07-gift-expedition-catalog.html`

**Topic it served:** the Flanders gift expedition synthesis — 5 angles, top-pick combo recommendation (a commissioned object + a private experience), decision-axis chart.

**Register:** *high-end gift catalog.* Cream paper palette. Cover with serif title left and a 2×2 stack of "gift frames" right (each frame: gradient image + name + lead-time). A boxed top-pick block: serif headline ("commissioned X *and* a Y") with two numbered cards side-by-side. Five angle tiles below. Dark scatter chart for the decision axes. Tension callout in cream.

**Why it worked:** the canonical's deliverable is a recommendation pair — one tangible thing, one experiential. The catalog register matches that "browse-and-pick" reading mode. The 2×2 cover stack hints at "more options" without committing the cover to one image. The decision-axis scatter chart externalizes the canonical's tradeoff into a visual.

**Transferable to:** curated recommendation lists with hierarchy and a top pick. Wedding-vendor selection. Holiday gift guides. Travel itinerary picks. Anything that lives between magazine (single hero) and corkboard (intimate) in register.

**Risk profile:** medium. The 2×2 cover stack and scatter chart are bespoke pieces. Worth the effort when the canonical has the structure (top pick + axes); skip when it doesn't.

---

## 08 · Subtopic navigation rail — `atlas/html-wireframes/08-subtopic-navigation.html`

**Topic it served:** UX exploration for how a sub-topic page should link back to its parent and siblings.

**Register:** *3-column reading layout with explicit navigation.* Sticky parent breadcrumb with thumb at top. Left rail: numbered sibling cards with the current page highlighted. Center: article. Right rail: in-page TOC + reading progress + top sources. Footer: prev/next pager + back-to-expedition card.

**Why it worked:** this isn't a *content* view — it's a *navigation* view. The register matches reading-room software (Notion, Substack, Medium). It's a reference for what the canonical chrome should DO, not what a creative one-off should look like.

**Transferable to:** mostly already absorbed into Atlas's chrome itself (sibling rail in TOC, prev/next pager, etc.). Less useful as a one-off view register, more useful as a UX standard.

**Risk profile:** N/A — this isn't a view-author target so much as a chrome reference.

---

## What to do with this list

When VIBE_HINT is empty (the common case), don't go through this list and pick. Instead:

1. **Read the canonical first.** What does it want to feel like?
2. **Hold this list in peripheral vision** to know what's possible.
3. **Choose or invent.** If 06's corkboard fits, use it. If 03's brutalism fits, use it. If none fit, invent something — a Vogue-style fashion editorial, a folded paper map, a Polaroid-by-Sagmeister hybrid, an Atlas of stat-tiles, a weather-forecast strip. The goal is "this view inhabits this topic," not "this view picked from a menu."

The wireframes 01-08 are the breadth you've seen. The view you author next probably *isn't on this list*. Good.

## Anti-pattern: the safe pick

If a topic is hard to read for register, the temptation is to default to one of the safe registers (dashboard, GitHub-grid). Resist when you can. A surprising register is better than a mediocre safe one. If you're confident the topic genuinely is dashboard-shaped or grid-shaped, fine. If you're picking dashboard *because you don't know what else to pick*, push harder.

Common pitfalls:
- Restaurants → magazine (so far so good) → ALSO restaurants → magazine. After two, ask whether the third deserves something different — Vogue-style? A menu-card replica? A guidebook-page treatment?
- Tools → grid → ALSO tools → grid. Same trap. Twelfth tool grid is a snooze.
- Anything sad/serious → poster (3). Anything fun/personal → corkboard (6). Anything else → dashboard. This three-way fork is too coarse. Look harder.
