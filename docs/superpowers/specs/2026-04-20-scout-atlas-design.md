# Scout + Atlas — Design

**Date:** 2026-04-20
**Status:** Approved for implementation planning

## Problem

Need a personal research tool that can be triggered from a Claude Code session or a mobile device, performs web research on a topic with configurable depth, and publishes the result to a browsable, shareable location. Runs unattended (no permission prompts). Must use the existing Claude Max subscription — no API billing.

Prior ad-hoc researches (Ghent restaurants, NAS replacement options, AI-driven dev talk prep) validate the value but were one-off, not reusable or retrievable.

## Names

- **Scout** — the engine (private? no, also public). Performs the research.
- **Atlas** — the public GitHub Pages site. Collection of published research.

## Architecture

Two public GitHub repos.

### `scout` (engine, public)
- `.github/workflows/research.yml` — `workflow_dispatch` with typed inputs
- `skills/scout/SKILL.md` — the research playbook
- `CLAUDE.md` — project-wide defaults (terse, no emojis, inline URLs)
- `scripts/run.sh` — invokes `claude --dangerously-skip-permissions` with the skill loaded
- `scripts/publish.sh` — clones Atlas, drops artifact in, regenerates index, commits, pushes
- `README.md` — Synology setup instructions (see "Setup" section)
- Secret: `ATLAS_DEPLOY_KEY` (SSH deploy key for Atlas repo)

### `atlas` (output site, GitHub Pages)
- `research/YYYY-MM-DD-<slug>/index.{html,md}` — one folder per research
- `index.html` — auto-generated listing, newest first
- `assets/base.css` — minimal shared styling, mobile-readable
- No static site generator (no Jekyll). Pure static files; Pages serves as-is.
- Per-research pages can be fully bespoke HTML when format is `html`.

## Runtime

### Host
Synology NAS, always-on, internet-accessible. Claude already installed via `npm install -g`. OAuth creds in `~/.claude/`.

### Scout user (isolation)
Dedicated unprivileged `scout` Linux user. Owns:
- `/home/scout/` — workspace, git checkouts, Claude OAuth
- Own `~/.claude/` — authenticated once via interactive login
- Member of `docker` group (future-proofing; not used at MVP)

Blast radius if Claude misbehaves with `--dangerously-skip-permissions`: `/home/scout/`.

### Tooling inside scout user's environment
- `claude` CLI (npm global)
- `node` (Claude runtime + npx for playwright)
- `git`
- `gh` (GitHub CLI)
- `playwright` + chromium (fallback for JS-walled pages; not default path)

**Not installed:** python, pandoc, database clients, ffmpeg, dev toolchains. Research doesn't need them. (HolyClaude was evaluated — overkill for pure research.)

### GH Actions runner
Self-hosted runner registered against the `scout` repo, runs as `scout` user, configured as a system service. Polls GitHub outbound — no inbound ports required.

## Workflow inputs

| Field | Type | Values | Default |
|---|---|---|---|
| `topic` | string (required) | Free text; may include steering hints ("emphasis on r/homelab") | — |
| `depth` | choice | `ceo` / `standard` / `deep` | `standard` |
| `format` | choice | `md` / `html` / `auto` | `auto` |

`obsidian_tag` is **v2 backlog**, not in MVP.

## Trigger paths

- **Mobile:** GitHub mobile app → Scout repo → Actions → Run workflow → fill form → Run
- **Desktop (Claude Code session):** `gh workflow run research.yml -f topic="..." -f depth=deep`, or a local `/research` slash command that wraps this
- **Future (v2):** Claude.ai remote trigger via the `schedule` skill — deferred until MVP proves out

## Scout skill contract

### Source selection — automatic, topic-aware

Skill ships a rubric; the model picks per topic:

- **Baseline (always):** Google web, Wikipedia, official vendor/docs sites
- **Software/tools:** + Reddit, HN, GitHub, YouTube
- **Hardware:** + Reddit (r/homelab, r/selfhosted), YouTube reviews, vendor specs
- **Restaurants/local:** + Michelin, TripAdvisor, Yelp, local blogs
- **Talks/SOTA topics:** + recent blogs, Twitter/X threads, arXiv, conference sites
- **Consumer products:** + Wirecutter, review aggregators

No explicit source checkboxes. Steering hints live inside `topic` ("focus on academic sources").

### Depth behaviors

| Depth | Length | Content |
|---|---|---|
| `ceo` | ~400 words, 1 page | Decision framework, 1 comparison table max, 5-8 citations. Exec-ready. |
| `standard` | 2-4 pages | Full tables, trade-offs, caveats, 15-30 citations. |
| `deep` | as-needed | All angles, minority views, edge cases, 40+ citations. Structured sections. |

### Hard output rules

1. **Inline citations.** Every factual claim, quote, number, or summary line carries source URL(s) inline — `[[n]](url)` footnote-style in MD, small superscript links in HTML. No trailing "References" section. If a comparison table row synthesizes three sources, all three URLs appear in that row.
2. **Comparisons → tables.** Always. No prose equivalents.
3. **Terse.** No filler, no "in conclusion" paragraphs, no prose bloat.
4. **No emojis.**
5. **Opinions labeled** by source: "r/homelab consensus:", "Wirecutter top pick:", "arXiv paper (2025):". Don't present opinions as facts.
6. **If a claim has no URL, don't make the claim.**

### Format resolution

- `format=md` → markdown
- `format=html` → bespoke HTML tailored to topic (restaurant cards, hardware comparison grids, talk timelines)
- `format=auto` → Scout picks. HTML for comparison-heavy or visual topics; MD for text-heavy analyses.

### Per-research metadata (for index generation)

Each research file starts with a metadata block:
- **HTML:** `<script type="application/json" id="scout-meta">{...}</script>` in `<head>`
- **MD:** YAML frontmatter

Schema: `{title, date, depth, topic, tags[], summary}`. `summary` is a single sentence shown on the Atlas index.

### Procedure per run

1. Parse topic; extract steering hints; select source rubric
2. Research: WebSearch + WebFetch; Playwright fallback for pages returning empty/JS-walled content
3. Draft output with inline citations throughout
4. Self-check: every claim has ≥1 URL; tables used where comparisons exist; terse; no trailing references section
5. Write to `atlas/research/YYYY-MM-DD-<slug>/index.{html,md}`. Slug = topic lowercased, non-alphanumerics replaced with `-`, collapsed dashes, truncated to 50 chars, trailing dash stripped. If slug collides with an existing folder, append `-2`, `-3`, etc.
6. Regenerate `atlas/index.html` by scanning all research folders' metadata blocks
7. `git add . && git commit && git push` to Atlas

## Atlas site

- **Index page** (`index.html`): title, date, depth badge, 1-line summary, tags, link to research. Newest first. Static list at MVP; client-side tag filter (vanilla JS, no framework) added in v1.1 once there are enough entries to warrant filtering.
- **Per-research page**: bespoke HTML or rendered MD. Back-link to Atlas index. Uses `assets/base.css`; per-research inline `<style>` allowed when the topic benefits from it.
- **Mobile-readable**: readable line lengths, tables scroll horizontally on narrow screens, base font ≥16px.
- **No build step on GitHub's side** — Pages serves static files. Scout regenerates the index on each push.

## Synology setup README (first-class deliverable)

The Scout repo's `README.md` must include a section titled "Synology setup" covering:

1. **Prereqs** — DSM version tested; Container Manager / Package Center notes
2. **Create scout user** — `synouser`/`useradd`, home dir, `docker` group
3. **Install dependencies** as scout — node, `npm i -g @anthropic-ai/claude-code`, `git`, `gh`, `npx playwright install chromium`
4. **Authenticate Claude** — one-time interactive OAuth login as scout; creds land in `~/.claude/`
5. **Register GH Actions self-hosted runner** — download, register, run as service (systemd unit or DSM Task Scheduler, whichever DSM version supports)
6. **Atlas deploy key** — generate SSH key, add as deploy key on `atlas` repo with write access, SSH config
7. **First research** — trigger test workflow, verify publish, troubleshooting tips

Keep it operator-focused, terse, with copy-pasteable commands.

## Future backlog (not MVP)

- **Obsidian cross-reference** — after research completes, clone user's private Obsidian repo, filter by tag, diff findings against existing notes, append "gaps/overlaps" section
- **Remote trigger via `schedule` skill** — Claude.ai-native trigger path (no GH Actions); explore once MVP is stable
- **Playwright-heavy research** — swap to full Docker container (HolyClaude-style) for research needs like JS-heavy SPA scraping
- **Private research** — move Atlas behind auth (paid GH Pages or self-hosted) once a sensitive topic appears
- **Planned test researches**:
  - Does a good "Research agent" or skill already exist? (meta!)
  - NAS replacement options (the one that motivated all of this)
  - State of the art in AI-Driven Development (for the technical session)

## Non-goals

- General coding assistance — Scout is research-only
- Real-time/streaming output — batch publish is fine
- Multi-user / collaborative features
- Authentication, access control — Atlas is public by design

## Success criteria

1. Trigger a research from mobile GitHub app → the workflow completes end-to-end without manual intervention and a URL lands in Atlas with the finished report
2. Output follows hard rules: inline citations, terse, tables for comparisons
3. Three planned test researches produce useful, shareable artifacts
4. Zero API billing — runs entirely on the Max subscription
5. Scout user isolation: a misbehaving run cannot touch files outside `/home/scout/`
