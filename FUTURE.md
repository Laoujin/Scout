# Scout — Next Arc

Scout-the-artifact-pipeline is mature. The next level is Scout-the-system-you-live-in. Three axes, each weak today, each compounding when stronger.

## The triangle

- **Corpus** — Atlas as a knowledge graph, not a flat list of cards.
- **Capture** — sub-10s path from "I have a question" to Scout is running.
- **Active** — Scout runs without being asked.

Each axis amplifies the others:
- Capture without Corpus = more islands.
- Corpus without Capture = a pretty graveyard.
- Active without either = noise.

## Corpus

Today: flat list of `research/<date>-<slug>/` cards. Every run is an island.

- Full-text search across Atlas (Lunr / Pagefind, static-site friendly).
- Tag pages: `/tags/<tag>/` aggregating runs.
- `related:` frontmatter — pre-write pass greps prior runs by tag/topic, links 1–3 most relevant.
- RSS feed of new research.
- Graph view (long-term): nodes = runs, edges = shared tags / shared citations.

## Capture

Today: only path is browser → github.com → New Issue → fill template. Desk-only, ~60s. Most questions arrive on a phone.

| Surface                | Trigger                               | Notes                                                                                     |
|------------------------|---------------------------------------|-------------------------------------------------------------------------------------------|
| iOS share-sheet        | Share URL/text from any app           | Highest leverage. iOS Shortcut → GitHub API.                                              |
| Email-to-Issue         | Forward to `scout@<domain>`           | Subject = topic, body = steering. Cloudflare Email Routing → webhook → `gh issue create`. |
| Voice / Siri           | Spoken topic                          | Same plumbing as share-sheet, dictation input.                                            |
| Telegram/Slack bot     | DM a topic                            | Reuse Slack remote-control plumbing.                                                      |
| Backlog drain          | `scout-backlog.md` or `backlog` label | Decouples having an idea from running it. Scout pulls when idle.                          |
| Bookmarklet            | One click on any page                 | Desk-version of share-sheet.                                                              |
| Atlas follow-up button | Bottom of every artifact              | Pre-fills `extends: <prior-artifact>`.                                                    |

Every surface ends in `gh issue create --template research.yml`. Build share-sheet first; rest are variations.

Second-order effects:
- Capture without friction is a usage-pattern flip. Runs become opportunistic, not deliberate. Volume goes up 5–10×.
- Cheap capture changes *what* gets researched — small curiosities now worth queuing.

## Active

Today: pure on-demand. Scout never runs unless you ask.

| Flavor        | Trigger                               | Cost                    | Example                                                                       |
|---------------|---------------------------------------|-------------------------|-------------------------------------------------------------------------------|
| **Watch**     | Cron over published artifact's ledger | Cheap (ledger-only)     | Re-fetch each cited URL, diff against stored `quote`, comment if drift.       |
| **Drain**     | Idle-time backlog pull                | Cheap                   | Overnight: Scout works through queued curiosities.                            |
| **React**     | External event hook                   | Per-integration         | New repo release / arXiv paper / RSS item → Scout opens its own Issue.        |
| **Subscribe** | Cron over standing topic              | Expensive (full re-run) | Weekly "best self-hosted LLM router" — only publish if conclusions shifted.   |
| **Curate**    | Self-reflective cron over Atlas       | Medium                  | "Run #12 and #34 disagree on X — reconcile?" or "8 dead URLs across 23 runs." |

Distinctions:
- Watch ≠ Subscribe. Watch checks if *sources* moved. Subscribe checks if *the answer* moved.
- React ≠ Drain. React is exogenous (world changed). Drain is endogenous (you queued earlier).
- Curate only becomes interesting once Atlas has 30+ entries.

## Build order

1. **Capture: iOS share-sheet** — biggest UX delta per hour spent.
2. **Corpus: search + `related:` cross-links** — turns Atlas from list into graph.
3. **Active: Watch** — cheapest active flavor, catches link rot and quote drift everywhere.
4. **Capture: email + backlog drain** — closes the queue loop.
5. **Corpus: tags + RSS** — discoverability and ambient awareness.
6. **Active: React** — per-source integration, build as needed.
7. **Active: Subscribe + Curate** — long-tail; only worth it once corpus is rich.

## Out of scope here

Tracked elsewhere or deferred:

- Rigor bolt-ons (multi-persona critique, MCP search backend, claim-level quote verification) — real, but second-order vs the triangle. See survey: `atlas/research/2026-04-21-survey-of-research-agents-...`.
- Security hardening (egress allowlist, read-only root, output validator) — see `TODO.md`.
- Multimodal output (charts, maps, timelines in body) — orthogonal axis.
- Operational hardening (budget caps, cancellation, retries, cost dashboard) — surfaces once capture lifts volume.


## Security

Claude has access the GH token & the Claude Subscription.

| Effort | Mitigation                                                                                                 | Stops      |
|--------|------------------------------------------------------------------------------------------------------------|------------|
| Low    | Docker network without route to LAN (network_mode: bridge + firewall rule dropping RFC1918 egress)         | #1         |
| Low    | GH_TOKEN minimum scope — already contents: read, issues: write, which is good; double-check no broader PAT | limits #2  |
| Low    | Never mount ~/.claude/ read-write; read-only bind if at all                                                | limits #2  |
| Low    | Read-only root filesystem, writable tmpfs for scratch                                                      | #3         |
| Medium | Require human approval before Scout commits & pushes to Atlas (manual gh pr merge or workflow_dispatch)    | #3, #4     |
| Medium | Output validator: reject published content containing `<script>`, off-topic URLs, secrets-like strings     | #4         |
| Medium | Egress allowlist (only anthropic.com, github.com, approved search domains) via squid/envoy sidecar         | #1, #2     |
| High   | Seccomp + AppArmor profile, drop all caps, non-root user                                                   | #6         |
