<table>
  <tr>
    <td width="220" align="center">
      <img src="docs/scout-atlas-logo.png" alt="Scout + Atlas" width="200">
    </td>
    <td>
      <h1>Scout</h1>
      <h2>Personal research engine</h2>
      <p>
        Trigger <a href="https://github.com/Laoujin/Scout/actions/workflows/research.yml"><code>research.yml</code></a>
        GitHub Action to let Claude Code perform research and publish the result to
        <a href="https://github.com/Laoujin/Atlas">Atlas</a>, served via
        <a href="https://laoujin.github.io/Atlas/">GitHub Pages</a>.
      </p>
    </td>
  </tr>
</table>

### Inputs

| Field    | Values                                  | Default  |
|----------|-----------------------------------------|----------|
| `topic`  | Free text                               | —        |
| `depth`  | `recon` / `survey` / `expedition`       | `survey` |
| `format` | `md` / `html` / `auto`                  | `auto`   |

CLI flag and workflow input values remain the original internal codes: `ceo` (recon), `standard` (survey), `deep` (expedition).

See [`skills/scout/SKILL.md`](skills/scout/SKILL.md) for how these drive behaviour, [`skills/scout/deep.md`](skills/scout/deep.md) for the parallel-sub-agent flow that `depth=deep` triggers, and [`skills/scout/tighten.md`](skills/scout/tighten.md) for how raw topics get sharpened into research briefs before a run.

### Depth tiers

| Tier | Shape | Artifacts | Wall-clock |
|------|-------|-----------|------------|
| `recon` (CLI: `ceo`) | Single pass, inline cites | `index.{md,html}` | ~2–5 min |
| `survey` (CLI: `standard`) | Single pass + on-disk `citations.jsonl` + reflect-and-requery | `index.*`, `citations.jsonl` | ~5–10 min |
| `expedition` (CLI: `deep`) | Parent dispatches researcher sub-agents per sub-question (≤6 parallel), merges ledgers, runs post-write reviewer, applies one fix pass | `index.*`, `citations.jsonl`, `citations.a*.jsonl`, `outline.md` | ~15–30 min |

Only the repo OWNER's Issues / dispatches trigger the workflow (author-association gate). Forks are safe out of the box — nobody but you can spend your runner.

## Fork for your own use

Everything that needs to vary per-fork now reads from GitHub's own context (`${{ github.repository_owner }}` in the workflow, `site.github.*` in Atlas layouts) or from `docker/.env`. The "fork" is small.

1. **Scout:** click "Use this template" on this repo → `<you>/Scout`. Keep the repo name `Scout` if you want zero config; rename freely if you want — you'll just set a repo-level variable `ATLAS_REPO_NAME` below.
2. **Atlas:** click "Use this template" on [Laoujin/Atlas](https://github.com/Laoujin/Atlas) → `<you>/Atlas`. **Delete the `research/` folder** (that's my published findings, not yours). Enable Pages: Settings → Pages → Source: `Deploy from a branch` → default branch → Save.
3. **One edit in your Atlas fork:** `_config.yml` → set `baseurl` to `/<your-atlas-repo-name>` (if you renamed Atlas to something other than `Atlas`). If you renamed Scout, also set `scout_repo:` to your Scout fork's name. Push.
4. **One file to fill in for your Scout fork** — on your NAS, `docker/.env` (copied from `.env.example`): set `RUNNER_URL`, `ATLAS_REPO`, `RUNNER_TOKEN`. That's it.
5. Continue with [Setup](#setup).

Nothing in the workflow, scripts, or CSS has to be edited. If you renamed Atlas to a non-default name, set repo variable `ATLAS_REPO_NAME` at `<you>/Scout` → Settings → Secrets and variables → Actions → Variables → New repository variable.

## Setup

GitHub → [`Laoujin/Scout`](https://github.com/Laoujin/Scout/settings/actions/runners/new) → Settings → Actions → Runners → New self-hosted runner → Linux x64. Copy the token.

SSH into your always on device.

```bash
git clone git@github.com:Laoujin/Scout.git
cd Scout/docker
cp .env.example .env
# paste the token into .env as RUNNER_TOKEN=...

docker-compose up -d --build
```

### Atlas SSH deploy key

The container generates an ed25519 key on first boot and prints the public half to its log.

```bash
docker logs scout-runner 2>&1 | grep '^ssh-ed25519'
```

GitHub → [`Laoujin/Atlas`](https://github.com/Laoujin/Atlas) → Settings → Deploy keys → Add deploy key → title `scout-nas`, paste key, check **Allow write access**.

### Authenticate Claude

```bash
docker exec -it scout-runner runuser -u runner -- claude
# Login, then /exit
```

## How to research

### Default: open a research Issue

[Open a new Issue](https://github.com/Laoujin/Scout/issues/new?template=research.yml) using the **Research request** template. Fill in `Topic`, `Depth`, `Format`. Optional: tick **Skip tightening** if your topic is already exactly what you want researched.

Within ~30s Scout replies with a sharpened proposal (or your raw topic when skip is ticked) plus a `- [ ] Start research` checkbox.

- **Tick the checkbox** → research runs, publishes to Atlas, comments the link back, closes the Issue.
- **Reply with feedback** ("focus on r/homelab", "shorter, decision-only") → Scout posts a revised proposal as a new comment. Loop until happy.

Mobile UX: GitHub mobile app → Scout → New issue → pick the template → confirm via the checkbox on Scout's reply. No workflow form to fill blind.

### Power-user: dispatch the workflow directly

Skips the Issue dance — fires research with your raw topic, no tightening, no Issue created.

```bash
gh workflow run research.yml --repo Laoujin/Scout -f topic="top 3 static site generators in 2026" -f depth=ceo -f format=md
gh run watch --repo Laoujin/Scout
```

### Slash command

```bash
mkdir -p ~/.claude/commands
cp commands/research.md ~/.claude/commands/research.md
```

In Claude Code:

- `/research Compare X vs Y depth=deep format=html` — opens an Issue (default flow).
- `/research Compare X vs Y --dispatch` — runs immediately via `workflow_dispatch`.


## Troubleshooting

- **Runner offline** → `docker logs scout-runner`; `docker-compose restart`.
- **Token expired** (~1 h after issue) → new token, update `.env`, `docker-compose down && docker-compose up -d`.
- **Push fails** → `docker exec scout-runner runuser -u runner -- ssh -T github.com-atlas`; verify deploy key has write access.
- **Claude auth expired** → `docker exec -it scout-runner runuser -u runner -- claude`.
- **Update Claude CLI** → `docker-compose build --pull && docker-compose up -d`.
- **Update Scout** → `git pull` in the Scout repo, then `cd docker && docker-compose build --pull && docker-compose up -d`. Claude auth, runner registration, and the Atlas SSH key survive the rebuild (they're on named volumes).


## Alternatives

- ⭐ 515 [199-biotechnologies/claude-deep-research-skill](https://github.com/199-biotechnologies/claude-deep-research-skill)
