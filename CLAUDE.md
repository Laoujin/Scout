# Scout project rules

These rules apply to every run inside this repo.

## Output style
- Terse. No filler, no "in conclusion" paragraphs, no prose bloat.
- No emojis anywhere.
- When comparing options, use a table. Always. Never prose.
- Show only the changed/new content when editing files.

## Citations (hard rule)
Every factual claim, quote, number, or summary line MUST carry its source URL inline next to the claim. Never produce an orphan summary followed by a "References" list at the bottom.
- In markdown: `[[n]](https://url)` footnote-style inline.
- In HTML: small superscript `<sup><a href="url">[n]</a></sup>`.
- A comparison-table row synthesising three sources shows all three URLs in that row.
- If a claim has no URL, do not make the claim.

## Tools
- Do not install unexpected packages. If `npm install` or `apt-get install` feels necessary, stop and ask.
- Prefer `WebFetch` and `WebSearch` first. Fall back to `npx playwright` only for pages that return empty/JS-walled content via `WebFetch`.
