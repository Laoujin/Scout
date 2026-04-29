<table>
  <tr>
    <td width="220" align="center">
      <img src="docs/scout-atlas-logo.png" alt="Scout + Atlas" width="200">
    </td>
    <td>
      <h1>Scout</h1>
      <h2>Personal research engine</h2>
      <p>Open a GitHub Issue → Claude researches on your hardware → cited
      result published to your own Jekyll site via GitHub Pages.</p>
      <p>
        <a href="https://laoujin.github.io/Scout/">Landing page &amp; config picker</a>
        · <a href="https://laoujin.github.io/Atlas/">Example Atlas</a>
      </p>
    </td>
  </tr>
</table>

## What it is

Scout is a self-hosted research runner. You open a GitHub Issue → a Docker
container on your always-on machine runs Claude Code against it → the cited
result lands as a Jekyll post in your Atlas repo, served via GitHub Pages at
a URL you own.

Three repos, one flow:

- <img src="docs/scout-logo.svg" alt="" width="18" align="top"> **Scout** — this repo. Self-hosted GitHub Actions runner + research workflow + skill pack. Forked to your account.
- <img src="docs/atlas-logo.svg" alt="" width="18" align="top"> **[Atlas](https://github.com/Laoujin/Atlas)** — your publishing target. Jekyll site, themed via three config values (`skeleton` / `palette` / `card`). Built by GitHub Pages.
- <img src="docs/compass-logo.svg" alt="" width="18" align="top"> **[Compass](https://github.com/Laoujin/Compass)** — the Jekyll theme. Lives as a submodule of Atlas at `compass/`; supplies layouts, CSS, and the `skeleton` / `palette` / `card` knobs. You only touch this if you want to tune the look.

**Requires:** Claude Code subscription, Docker, a GitHub account, an always-on
Linux host (a mini-PC, NAS, or spare laptop). No API key — Scout runs inside
your Claude subscription.

Only Issues / dispatches from the repo owner or an org member trigger the workflow (author-association gate: `OWNER` or `MEMBER`). Outside users can open Issues but nothing fires — your runner is safe.

## Install

### One-liner

```bash
curl -fsSL https://raw.githubusercontent.com/Laoujin/Scout/main/install.sh \
  | bash -s -- --config=s5.cartography.v1
```

Pick your `<skeleton>.<palette>.<card>` with
[the picker](https://laoujin.github.io/Scout/#your-atlas)
or go with `s5.cartography.v1`. 
You can change it any time by editing `_config.yml` in your Atlas repo.

- `skeleton`: overall site layout (s1 -> s6)
- `palette`: Colour scheme (ex: cartography, midnight, nord, ...)
- `card`: Research card style (v1 -> v7)

**What the installer does**:

- Logs in to `gh` (device flow or `$GH_TOKEN`).
- Forks Scout to your account.
- Creates the Atlas repo:
  - scaffolds a minimal `_config.yml` + empty `research/` and adds [Compass](https://github.com/Laoujin/Compass) (the Jekyll theme) as a git submodule at `compass/`.
  - Enables GitHub Pages.
  - Generates an ed25519 deploy key and uploads it to Atlas with write access then seeds the `scout_atlas-ssh` Docker volume with it.
- Fetches a runner-registration token and writes `docker/.env`.

Then two manual steps:

```bash
# Start the GitHub action workflow runner
cd Scout/docker && docker-compose up -d --build

# one-time login with your Claude Code subscription
docker exec -it scout-runner runuser -u runner -- claude
```

**Flags:**

| Flag                                   | Default         | Purpose                             |
|----------------------------------------|-----------------|-------------------------------------|
| `--config=<skeleton>.<palette>.<card>` | *required*      | Atlas theme (see picker)            |
| `--dir=<path>`                         | `$PWD/Scout`    | Where the Scout clone lands         |
| `--ref=<branch\|tag>`                  | `main`          | Which Scout version to install from |
| `--upstream=<owner>/<repo>`            | `Laoujin/Scout` | Template source                     |

Don't want to pipe strangers into `bash`? See [INSTALL.md](INSTALL.md) for the manual step-by-step.

## Usage

### Open a research Issue

[Open a new Issue](https://github.com/Laoujin/Scout/issues/new?template=research.yml) using the **Research request** template. Fill in `Topic`, `Depth`, `Format`. Optional: tick **Skip sharpening** if your topic is already exactly what you want researched.

Scout replies with a sharpened proposal (or your raw topic when skip is ticked) plus a `- [ ] Start research` checkbox.

- **Tick the checkbox** → research runs, publishes to Atlas, comments the link back, closes the Issue.
- **Reply with feedback** ("focus on r/homelab", "shorter, decision-only") → Scout posts a revised proposal as a new comment. Loop until happy.

### `/scout` slash command

Open an Issue from inside Claude Code (via gh CLI):

```bash
mkdir -p ~/.claude/commands
cp commands/scout.md ~/.claude/commands/scout.md

# Replace the two placeholders with your repo and Atlas URL:
sed -i \
  -e 's#{{SCOUT_REPO}}#<you>/Scout#g' \
  -e 's#{{ATLAS_URL}}#https://<you>.github.io/Atlas/#g' \
  ~/.claude/commands/scout.md
```

Usage in Claude Code:

```txt
/scout Compare the top 3 static site generators in 2026
```

## Depth tiers

`Topic`, `Depth`, and `Format` are the three Issue inputs:

| Depth        | Shape | Artifacts | Wall-clock |
|--------------|-------|-----------|------------|
| `recon`      | Single pass, inline cites | `index.{md,html}` | ~2–5 min |
| `survey`     | Single pass + on-disk `citations.jsonl` + reflect-and-requery | `index.*`, `citations.jsonl` | ~5–10 min |
| `expedition` | Parent dispatches researcher sub-agents per sub-question (≤6 parallel), merges ledgers, runs post-write reviewer, applies one fix pass | `index.*`, `citations.jsonl`, `citations.a*.jsonl`, `outline.md` | ~15–30 min |

See [`skills/scout/SKILL.md`](skills/scout/SKILL.md) for how these drive behaviour, [`skills/scout/deep.md`](skills/scout/deep.md) for the parallel sub-agent flow that `expedition` triggers, and [`skills/scout/sharpen.md`](skills/scout/sharpen.md) for how raw topics get sharpened into research briefs.

## Theme Tinkering

If you want to tune your Atlas theme/layout:


### Preview theme changes locally

The theme lives in [Compass](https://github.com/Laoujin/Compass). Clone it and use its `serve.ps1` (PowerShell, Docker, Python), which builds every variant of one axis into its own subdir and [serves the lot](http://localhost:4000/):

```powershell
git clone https://github.com/Laoujin/Compass.git
cd Compass
./serve.ps1                    # sweep skeletons (s1..s6)
./serve.ps1 -Sweep palettes    # sweep all palettes with current skeleton
./serve.ps1 -Sweep cards       # sweep all cards
```

For a single build on any platform:

```bash
cd Compass
docker run --rm -p 4000:4000 -v "$PWD:/srv/jekyll" jekyll/jekyll:4 jekyll serve --host 0.0.0.0 --baseurl '/'
```

To use new compass changes in your Atlas: `cd Atlas && git submodule update --remote compass && git commit -am "bump compass" && git push`.

## Operate

### Update Scout, Claude

```bash
cd ~/Scout
git pull
cd docker
docker-compose build --pull
docker-compose up -d
```

Named Docker volumes preserve the Claude login, runner registration, and Atlas deploy key across rebuilds. You don't re-auth.

### Re-authenticate Claude

If the subscription auth expires:

```bash
docker exec -it scout-runner runuser -u runner -- claude
# log in, /exit
```

### Rotate runner token

Runner-registration tokens expire ~1 h after issue. If you need to re-register:

```bash
# 1. Get a new token from Settings → Actions → Runners → New self-hosted runner
# 2. Update .env
sed -i "s#^RUNNER_TOKEN=.*#RUNNER_TOKEN=<new>#" ~/Scout/docker/.env
# 3. Force re-registration
cd ~/Scout/docker
docker-compose down
docker volume rm scout_runner-config   # discard old registration state
docker-compose up -d
```


## Troubleshooting

- **Runner offline** → `docker logs scout-runner`; `docker-compose restart`.
- **Runner won't register** → token probably expired. See [Rotate runner token](#rotate-runner-token).
- **Push to Atlas fails** → `docker exec scout-runner runuser -u runner -- ssh -T github.com-atlas` should greet you. If not, the deploy key is wrong or missing write access. Re-do step 5 + 6 of [INSTALL.md](INSTALL.md).
- **Claude auth expired** → see [Re-authenticate Claude](#re-authenticate-claude).
- **Jekyll preview build fails** → delete `compass/_previews/` and `compass/_site/`, retry. Jekyll caches are not cross-version.
- **`.env` permission denied inside container** → the host file must be readable by UID 1000 (the runner). `chmod 600` + `chown <you>:<you>` usually fixes it.

## Security

Scout runs Claude with `--dangerously-skip-permissions` in a container with unrestricted network access. **It is not sandboxed.** A malicious page reached during research could, in principle, instruct Claude to misuse credentials on the runner or scan your LAN.

What's on the runner:

- `GITHUB_TOKEN` — scoped to `issues:write` + `contents:read` on Scout only. Can spam/close Issues on Scout, cannot push anywhere.
- Atlas SSH deploy key — push access to your Atlas repo. Worst case: attacker publishes anything they like at your `github.io` URL.
- Claude Code auth — your subscription. Attacker runs Claude on your bill.
- Network position on your LAN — can scan routers, NAS, Home Assistant, etc.

Egress allow-listing, capability drops, and a seccomp profile are on the roadmap. Until then: keep the runner on a network you trust and don't point Scout at topics likely to pull in hostile content. More context in the [landing-page FAQ](https://laoujin.github.io/Scout/#faq).

## Alternatives

Full head-to-head benchmark on the same topic in [`comparison/COMPARISON.md`](https://github.com/Laoujin/Scout-Atlas/blob/main/comparison/COMPARISON.md).

| Stars | Repo                                                | How it works                                                                              |
|------:|-----------------------------------------------------|-------------------------------------------------------------------------------------------|
|   520 | [199-biotechnologies/claude-deep-research-skill][1] | Fire-and-forget — `deep research: <topic>` in a fresh `claude` session                    |
|   503 | [weizhena/Deep-Research-skills][2]                  | Slash commands — `/research` → `/research-deep` → `/research-report`, human gates between |
| 26.6k | [assafelovic/gpt-researcher][3]                     | Python CLI / Docker, OpenAI-default (Claude swap needs API key)                           |
| 11.2k | [langchain-ai/open_deep_research][4]                | LangGraph runner                                                                          |
| 28.1k | [stanford-oval/storm][5]                            | Wikipedia-style article generator                                                         |

[1]: https://github.com/199-biotechnologies/claude-deep-research-skill
[2]: https://github.com/weizhena/Deep-Research-skills
[3]: https://github.com/assafelovic/gpt-researcher
[4]: https://github.com/langchain-ai/open_deep_research
[5]: https://github.com/stanford-oval/storm

**SaaS:**

| Product                     | How it works                                                       |
|-----------------------------|--------------------------------------------------------------------|
| Perplexity + Pages          | Mobile Deep Research → "Create Page" → `perplexity.ai/page/<slug>` |
| ChatGPT Deep Research       | Mobile Deep Research → Share link (read-only thread)               |
| Google Gemini Deep Research | Mobile Deep Research → Export to Google Doc                        |
