# Scout project rules

These rules apply to every research run inside this repo.

## Output style

- Terse. No filler, no "in conclusion" paragraphs, no prose bloat.
- When comparing options, use a table. Always. Never prose.
- No emojis.

## Citations (hard rule)

Every factual claim, quote, number, or summary line MUST carry its source URL inline next to the claim. Never produce an orphan summary followed by a "References" list at the bottom.
- In markdown: `[[n]](https://url)` footnote-style inline.
- In HTML: small superscript `<sup><a href="url">[n]</a></sup>`.
- A comparison-table row synthesising three sources shows all three URLs in that row.
- If a claim has no URL, do not make the claim.

## Tools

- Prefer `WebFetch` and `WebSearch` first. Fall back to `npx playwright chromium` only for pages that return empty/JS-walled content.
- Do NOT install packages. Runs are headless — there is no one to ask for permission. If a task truly needs a dependency that isn't in the container, abort the run and print a single clear line naming the missing dependency (`scout: missing dependency: <name>`) so it can be baked into the Docker image later.
