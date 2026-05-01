# Scout project rules

These rules apply to every research run inside this repo.

## Output style

- Terse. No filler, no "in conclusion" paragraphs, no prose bloat.
- Prefer tables for comparisons over measurable axes (specs, numbers, features). When a comparison is about philosophy or fit-for-context rather than attributes, short labeled sections per option are fine — just keep it scannable.
- Markdown tables: pad cells so columns line up in monospace. Use reference-style links **only inside tables** (`[label][0]` with `[0]: url` definitions placed *immediately below that table*, not at the bottom of the file). Outside tables, always use inline links `[label](url)`.

## Citations (hard rule)

Every factual claim, quote, number, or summary line MUST carry its source URL inline next to the claim. Never produce an orphan summary followed by a "References" list at the bottom.
- In markdown: `[[n]](https://url)` footnote-style inline.
- In HTML: small superscript `<sup><a href="url">[n]</a></sup>`.
- A comparison-table row synthesising three sources shows all three URLs in that row.
- If a claim has no URL, do not make the claim.

## Tools

- Prefer `WebFetch` and `WebSearch` first. Fall back to `npx playwright chromium` only for pages that return empty/JS-walled content.
- Install what you need — runs are headless and `--dangerously-skip-permissions` is set. User-level installs work as the `runner` user: `npm install -g`, `pip install --user`, `npx …`. System packages (`apt-get`) need root which you don't have; if one is genuinely required, note it in a single footer line of your output (e.g. `scout: wants apt pkg: pandoc`) and carry on with the best workaround you can find — a later rebuild can bake it into the Dockerfile.
