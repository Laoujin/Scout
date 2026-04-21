<table>
  <tr>
    <td width="220" align="center">
      <img src="scout-atlas-logo.png" alt="Scout + Atlas" width="200">
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

| Field    | Values                      | Default    |
|----------|-----------------------------|------------|
| `topic`  | Free text                   | —          |
| `depth`  | `ceo` / `standard` / `deep` | `standard` |
| `format` | `md` / `html` / `auto`      | `auto`     |

See [`skills/scout/SKILL.md`](skills/scout/SKILL.md) for how these drive behaviour.

## Fork for your own use

You want your own Scout (engine) and your own Atlas (site). Five steps:

1. **Scout:** click "Use this template" on this repo (or fork) → `<you>/<scout-name>`.
2. **Atlas:** do the same on [Laoujin/Atlas](https://github.com/Laoujin/Atlas) → `<you>/<atlas-name>`. Enable Pages: Settings → Pages → Source: `Deploy from a branch` → your default branch → Save.
3. **Rewrite references in your Scout fork** — replace `Laoujin` → `<you>` and `Atlas` → `<atlas-name>` in:
    - `.github/workflows/research.yml` (`ATLAS_REPO`)
    - `docker/docker-compose.yml` (`RUNNER_URL`, `ATLAS_REPO`)
    - `docker/run-init.sh` (deploy-key instruction URL)
    - `commands/research.md` (`gh workflow run --repo …`)
    - `scripts/publish.sh` (the "Published:" echo URL)
    - `README.md` (badges / links — cosmetic)
4. **Rewrite references in your Atlas fork:**
    - `_config.yml` — `baseurl: /<atlas-name>`
    - `_layouts/default.html` — the two `hero-links` URLs point back to your Scout and Atlas repos
5. Continue with [Setup](#setup) below to wire everything to your NAS.

One-liner sanity check from your Scout fork's root:

```bash
grep -rn --include='*.yml' --include='*.sh' --include='*.md' --include='_layouts/*' -e Laoujin -e '/Atlas' .
```

Anything it turns up (outside the README's cosmetic links and this section itself) is still pointing at the original — fix it before your first run.

## Setup

GitHub → [`Laoujin/Scout`](https://github.com/Laoujin/Scout/settings/actions/runners/new) → Settings → Actions → Runners → New self-hosted runner → Linux x64. Copy the token.

SSH into your NAS.

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

Trigger [`research.yml`](https://github.com/Laoujin/Scout/actions/workflows/research.yml) in Github.

```bash
gh workflow run research.yml --repo Laoujin/Scout -f topic="test: top 3 static site generators in 2026" -f depth=ceo -f format=md
gh run watch --repo Laoujin/Scout
```

### Slash command

```bash
mkdir -p ~/.claude/commands
cp commands/research.md ~/.claude/commands/research.md
```

In Claude Code: `/research Compare X vs Y depth=deep format=html`


## Troubleshooting

- **Runner offline** → `docker logs scout-runner`; `docker compose restart`.
- **Token expired** (~1 h after issue) → new token, update `.env`, `docker compose down && docker compose up -d`.
- **Push fails** → `docker exec scout-runner runuser -u runner -- ssh -T github.com-atlas`; verify deploy key has write access.
- **Claude auth expired** → `docker exec -it scout-runner runuser -u runner -- claude`.
- **Update Claude CLI** → `docker compose build --pull && docker compose up -d`.
