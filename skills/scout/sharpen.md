---
name: sharpen
description: Sharpen a raw research topic into a precise, verb-led brief that the Scout research playbook can act on. Invoked by scripts/sharpen.sh before research begins.
---

# Sharpen a raw research topic

You receive a vague or under-specified topic and rewrite it as a precise research brief. The result becomes the prompt that drives an actual Scout research run, so it must be unambiguous, scoped, and faithful to what the user asked.

## Inputs

```
Raw topic: <free text from the user>
Depth: <ceo | standard | deep>
Format: <md | html | auto>
```

Optional, present on a re-sharpen:

```
Previous sharpened proposal: <last sharpened version>
User feedback to incorporate: <user's reply asking for changes>
```

## Rules

1. **Reframe as a verb-led research deliverable.** "Survey of …", "Compare …", "Build a list of …", "Decision framework for …". Not a noun phrase.

2. **Add the current year if the topic is temporal.** State-of-the-art, "best in 2026", recent comparisons, evolving ecosystems — anchor with the year. If the topic is timeless (e.g. "explain CAP theorem"), don't.

3. **Surface implicit criteria.** What axes is the user likely to want compared? Common ones:
   - For tools/products: production-ready vs experimental, OSS vs commercial, recency, cost, maturity.
   - For hardware: price/perf, power draw, ecosystem, vendor lock-in.
   - For talks/SOTA: what's contested, what's consensus, what's bleeding edge.
   - For local/restaurants: price band, vibe, occasion fit.
   Add 1-3 such axes inline. Don't bloat — pick the ones most likely to matter.

4. **Preserve every steering hint in the raw topic verbatim.** If the user wrote "focus on r/homelab" or "academic sources only" or "must include a table", that text appears in the sharpened version word-for-word. Steering hints are sacred — never paraphrase them.

5. **Match scope to depth.** `ceo` → one-page decision. `standard` → 2-4 pages with comparison tables. `deep` → all angles. The sharpened brief should mention the expected output shape if that helps Scout (e.g. "produce a comparison table of N candidates" for `standard`).

6. **Don't invent constraints.** If the user didn't say "open-source only", don't add "focus on open-source". If unsure, leave out.

7. **On a re-sharpen:** treat `User feedback to incorporate` as a hard constraint. Take the previous sharpened proposal, apply the feedback as a delta, output the revised version. Don't drift away from the user's original intent.

## Output

One paragraph. No preamble ("Here is..."), no quotes, no bullet list, no markdown headers, no explanation of what you changed. Just the sharpened topic, ready to be passed verbatim to the research playbook.

## Example

Input:
```
Raw topic: Agents that could be used for doing research for Scout
Depth: standard
Format: auto
```

Output:
```
Survey of research agents and deep-research tools available in 2026 that could serve a role like Scout (a custom Claude-Code-based research engine that publishes cited artifacts to a Jekyll site). Compare the main options across production-readiness, openness, citation quality, and cost. Note what's experimental versus shipping, and flag any ideas worth stealing for Scout's own playbook.
```
