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

Two repos, one flow:

- <img src="docs/scout-logo.svg" alt="" width="18" align="top"> **Scout** — this repo. Self-hosted GitHub Actions runner + research workflow + skill pack. Forked to your account.
- <img src="docs/atlas-logo.svg" alt="" width="18" align="top"> **Atlas** — your publishing target. Jekyll site, themed via three config values (`skeleton` / `palette` / `card`). Built by GitHub Pages.

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

Pick your `<skeleton>.<palette>.<card>` on [the picker](https://laoujin.github.io/Scout/#your-atlas) — `s5.cartography.v1` (magazine layout, cartography palette, image-top cards) is a good starting point. You can change it any time by editing `_config.yml` in your Atlas repo.

**What it does** (disposable Alpine container, ~30–60 s):

1. Logs in to `gh` (device flow or `$GH_TOKEN`).
2. Forks Scout to your account (or `--org`), enables Actions + Issues.
3. Creates an empty Atlas repo, seeds it from `atlas-seed/` with your config.
4. Enables GitHub Pages on Atlas.
5. Generates an ed25519 deploy key, uploads it to Atlas (write access), seeds the `scout_atlas-ssh` Docker volume with it.
6. Fetches a runner-registration token and writes `docker/.env`.
7. Optionally installs `/scout` to `~/.claude/commands/`.

Then two steps you do yourself:

```bash
cd Scout/docker && docker-compose up -d --build
docker exec -it scout-runner runuser -u runner -- claude   # one-time login
```

**Flags:**

| Flag | Default | Purpose |
|------|---------|---------|
| `--config=<skeleton>.<palette>.<card>` | *required* | Atlas theme (see picker) |
| `--dir=<path>` | `$PWD/Scout` | Where the Scout clone lands |
| `--org=<org>` | — | Fork into an org instead of your user (required if you already own the upstream) |
| `--ref=<branch\|tag>` | `main` | Which Scout version to install from |
| `--upstream=<owner>/<repo>` | `Laoujin/Scout` | Template source |
| `--local=<path>` | — | Use a local Scout checkout instead of fetching from GitHub (dev) |

Don't want to pipe strangers into `bash`? See [Manual](#manual) below.

### Manual

Replicates what `install.sh` does, step by step. Takes ~10 min.

Prereqs on your always-on host: `git`, `docker` + `docker-compose`, `ssh-keygen`. `gh` is optional — you can do the GitHub bits via the web UI.

#### 1. Fork Scout

Go to [`Laoujin/Scout`](https://github.com/Laoujin/Scout) → **Use this template** → **Create a new repository** → pick name/owner. On your fork:

- **Settings → Actions → General** → enable workflows (forks have Actions disabled by default)
- **Settings → General → Features** → tick **Issues**

Clone it to your host:

```bash
git clone git@github.com:<you>/Scout.git
cd Scout
```

#### 2. Create Atlas

Create an empty repo `<you>/Atlas` on GitHub (no README, no license). Seed it from `atlas-seed/`:

```bash
cp -a atlas-seed/ /tmp/atlas-init
cd /tmp/atlas-init
rm -rf research/*              # atlas-seed ships a sample post; drop it
mkdir -p research

sed -i \
  -e 's#^baseurl:.*#baseurl: /Atlas#' \
  -e 's#^scout_repo:.*#scout_repo: <you>/Scout#' \
  -e 's#^skeleton:.*#skeleton: s5#' \
  -e 's#^palette:.*#palette: cartography#' \
  -e 's#^card:.*#card: v1#' \
  _config.yml

git init -b main
git add -A
git commit -m "Initial Atlas seed"
git remote add origin git@github.com:<you>/Atlas.git
git push -u origin main
```

If you renamed Atlas to something other than `Atlas`, set `baseurl` to `/<your-repo-name>`.

#### 3. Enable GitHub Pages

On Atlas: **Settings → Pages → Source: Deploy from a branch → `main` / `/`** → Save. First build takes ~1 min; Pages URL is `https://<you>.github.io/Atlas/`.

#### 4. Register the runner

On Scout: **Settings → Actions → Runners → New self-hosted runner → Linux x64**. Copy the registration token (expires in ~1 h — don't close the page yet).

#### 5. Atlas deploy key

Generate an ed25519 keypair for pushing to Atlas:

```bash
mkdir -p /tmp/atlas-key && cd /tmp/atlas-key
ssh-keygen -t ed25519 -f atlas_deploy -C "scout-nas" -N ""

cat > config <<'CFG'
Host github.com-atlas
  HostName github.com
  User git
  IdentityFile ~/.ssh/atlas_deploy
  IdentitiesOnly yes
  StrictHostKeyChecking accept-new
CFG
```

Copy `atlas_deploy.pub` to Atlas: **Settings → Deploy keys → Add deploy key** → title `scout-nas`, paste, **tick Allow write access**.

#### 6. Seed the `scout_atlas-ssh` volume

The runtime container expects the key and ssh config on a named Docker volume:

```bash
docker volume create scout_atlas-ssh
docker run --rm \
  -v scout_atlas-ssh:/dest \
  -v /tmp/atlas-key:/src:ro \
  alpine:3.20 sh -c '
    cp /src/atlas_deploy /src/atlas_deploy.pub /src/config /dest/
    chown -R 1000:1000 /dest
    chmod 700 /dest
    chmod 600 /dest/atlas_deploy /dest/config
    chmod 644 /dest/atlas_deploy.pub'

rm -rf /tmp/atlas-key /tmp/atlas-init
```

#### 7. Fill `docker/.env`

```bash
cd ~/Scout/docker
cp .env.example .env
chmod 600 .env
```

Set:

```bash
RUNNER_URL=https://github.com/<you>/Scout
ATLAS_REPO=git@github.com-atlas:<you>/Atlas.git    # note the -atlas host alias
RUNNER_TOKEN=<paste token from step 4>
```

#### 8. Start the runner

```bash
docker-compose up -d --build
```

Check **Settings → Actions → Runners** on Scout — `nas-scout` should appear **Idle** within ~30 s.

#### 9. Authenticate Claude (one-time)

```bash
docker exec -it scout-runner runuser -u runner -- claude
# Log in to Anthropic, then /exit
```

Done. Open a research Issue on Scout to verify the flow.

## Usage

### Open a research Issue

[Open a new Issue](https://github.com/Laoujin/Scout/issues/new?template=research.yml) using the **Research request** template. Fill in `Topic`, `Depth`, `Format`. Optional: tick **Skip sharpening** if your topic is already exactly what you want researched.

Within ~30 s Scout replies with a sharpened proposal (or your raw topic when skip is ticked) plus a `- [ ] Start research` checkbox.

- **Tick the checkbox** → research runs, publishes to Atlas, comments the link back, closes the Issue.
- **Reply with feedback** ("focus on r/homelab", "shorter, decision-only") → Scout posts a revised proposal as a new comment. Loop until happy.

Mobile UX: GitHub mobile app → Scout → New issue → pick the template → confirm via the checkbox on Scout's reply.

### `/scout` slash command

Opens an Issue from inside Claude Code via a guided picker. The installer offers to drop it in; to add it manually:

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

```
/scout Compare the top 3 static site generators in 2026
/scout                                     # prompts for topic
```

Claude asks you for Depth / Format / Skip-sharpening via `AskUserQuestion`, then creates the Issue on your Scout fork. From there it's the normal Issue flow above.

## Depth tiers

`Topic`, `Depth`, and `Format` are the three Issue inputs:

| Depth | Shape | Artifacts | Wall-clock |
|-------|-------|-----------|------------|
| `recon` | Single pass, inline cites | `index.{md,html}` | ~2–5 min |
| `survey` | Single pass + on-disk `citations.jsonl` + reflect-and-requery | `index.*`, `citations.jsonl` | ~5–10 min |
| `expedition` | Parent dispatches researcher sub-agents per sub-question (≤6 parallel), merges ledgers, runs post-write reviewer, applies one fix pass | `index.*`, `citations.jsonl`, `citations.a*.jsonl`, `outline.md` | ~15–30 min |

`Format` is `md`, `html`, or `auto` (Scout picks — `html` for comparisons and custom layouts, `md` for briefs).

See [`skills/scout/SKILL.md`](skills/scout/SKILL.md) for how these drive behaviour, [`skills/scout/deep.md`](skills/scout/deep.md) for the parallel sub-agent flow that `expedition` triggers, and [`skills/scout/sharpen.md`](skills/scout/sharpen.md) for how raw topics get sharpened into research briefs.

## Atlas configuration

### Theme variables

Three knobs in `_config.yml` in your Atlas repo — edit, push, Pages rebuilds:

| Key | Values | Effect |
|-----|--------|--------|
| `skeleton` | `s1` Hero + footer · `s2` Top bar + footer · `s3` Top bar + sidenav · `s4` Split hero · `s5` Magazine cover · `s6` Terminal frame | Overall site layout |
| `palette` | `rust` · `paper` · `cartography` · `midnight` · `minimal` · `fieldnotes` · `solarized` · `nord` | Colour scheme |
| `card` | `v1` Image-top · `v2` Horizontal · `v3` Hero overlay · `v4` Terminal · `v5` Index card · `v6` No-image · `v7` Compact row | Research card style on the index |

`s6` (Terminal frame) ignores `card` — it renders the list as terminal output.

### Change after install

```bash
cd ~/Atlas
sed -i 's#^palette:.*#palette: midnight#' _config.yml
git commit -am "theme: midnight palette"
git push
```

GitHub Pages picks it up on push; the rebuild is typically under a minute. No Scout involvement — Atlas is just a Jekyll repo you own.

### Preview locally

`atlas-seed/serve.ps1` (PowerShell, requires Docker + Python) builds every variant of one axis into its own subdir and serves the lot:

```powershell
cd atlas-seed
./serve.ps1                    # sweep skeletons (s1..s6)
./serve.ps1 -Sweep palettes    # sweep all palettes with current skeleton
./serve.ps1 -Sweep cards       # sweep all cards
```

Then browse http://localhost:4000/ to flip between previews.

For a single build on any platform:

```bash
cd atlas-seed
docker run --rm -p 4000:4000 -v "$PWD:/srv/jekyll" jekyll/jekyll:4 \
  jekyll serve --host 0.0.0.0 --baseurl ''
```

## Operate

### Update Scout

```bash
cd ~/Scout
git pull
cd docker
docker-compose build --pull
docker-compose up -d
```

Named Docker volumes preserve the Claude login, runner registration, and Atlas deploy key across rebuilds. You don't re-auth.

### Update Claude CLI

The CLI ships inside the runner image — rebuild with `--pull` to get the latest:

```bash
cd ~/Scout/docker
docker-compose build --pull && docker-compose up -d
```

### Re-authenticate Claude

If the subscription auth expires (rare):

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

Keep the `scout_atlas-ssh` and `scout_claude-auth` volumes — those are unrelated.

## Troubleshooting

- **Runner offline** → `docker logs scout-runner`; `docker-compose restart`.
- **Runner won't register** → token probably expired. See [Rotate runner token](#rotate-runner-token).
- **Push to Atlas fails** → `docker exec scout-runner runuser -u runner -- ssh -T github.com-atlas` should greet you. If not, the deploy key is wrong or missing write access. Re-do step 5 + 6 of [Manual](#manual).
- **Claude auth expired** → see [Re-authenticate Claude](#re-authenticate-claude).
- **Jekyll preview build fails** → delete `atlas-seed/_previews/` and `atlas-seed/_site/`, retry. Jekyll caches are not cross-version.
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

- ⭐ 515 [199-biotechnologies/claude-deep-research-skill](https://github.com/199-biotechnologies/claude-deep-research-skill)
