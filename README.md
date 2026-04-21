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
