<p align="center"><img src="scout-atlas-logo.png" alt="Scout + Atlas" width="200"></p>

# Scout

## Personal research engine

Trigger [`research.yml`](https://github.com/Laoujin/Scout/actions/workflows/research.yml)
GitHub Action to let Claude Code perform research and publish the result to
[Atlas](https://github.com/Laoujin/Atlas), served via [GitHub Pages](https://laoujin.github.io/Atlas/).

## Inputs

| Field    | Values                      | Default    |
|----------|-----------------------------|------------|
| `topic`  | Free text                   | —          |
| `depth`  | `ceo` / `standard` / `deep` | `standard` |
| `format` | `md` / `html` / `auto`      | `auto`     |

See [`skills/scout/SKILL.md`](skills/scout/SKILL.md) for how these drive behaviour.

## Setup (Synology NAS, DSM 7.2+)

Do each step in order, as the `scout` user unless noted.

### 1. Create the `scout` user (as root)

```bash
synouser --add scout 'temp-password' 'Scout runner' 0 '' 0
```

Set a real password, then SSH in as `scout`.

### 2. Install dependencies

```bash
curl -o- https://raw.githubusercontent.com/nvm-sh/nvm/v0.40.1/install.sh | bash
exec bash
nvm install 22 && nvm use 22

npm install -g @anthropic-ai/claude-code playwright
npx playwright install chromium

# gh: download Linux tarball from https://github.com/cli/cli/releases,
# extract gh into ~/bin/, then: export PATH="$HOME/bin:$PATH"
```

### 3. Authenticate

```bash
claude         # OAuth; exit with /exit after login
gh auth login  # GitHub.com, HTTPS, web browser
```

### 4. Atlas SSH deploy key

```bash
ssh-keygen -t ed25519 -f ~/.ssh/atlas_deploy -C scout-atlas -N ""
cat ~/.ssh/atlas_deploy.pub
```

GitHub → [`Laoujin/Atlas`](https://github.com/Laoujin/Atlas) → Settings → Deploy keys → Add deploy key → title `scout-nas`, paste key, check **Allow write access**.

Append to `~/.ssh/config`:

```
Host github.com-atlas
  HostName github.com
  User git
  IdentityFile ~/.ssh/atlas_deploy
  IdentitiesOnly yes
```

Verify: `ssh -T github.com-atlas` → "Hi Laoujin/Atlas!…"

### 5. Register the self-hosted runner

GitHub → [`Laoujin/Scout`](https://github.com/Laoujin/Scout) → Settings → Actions → Runners → New self-hosted runner → Linux x64. Copy the token.

```bash
mkdir ~/actions-runner && cd ~/actions-runner
curl -fsSL -O https://github.com/actions/runner/releases/download/v2.321.0/actions-runner-linux-x64-2.321.0.tar.gz
tar xzf actions-runner-linux-x64-2.321.0.tar.gz
./config.sh --url https://github.com/Laoujin/Scout --token <TOKEN> --labels scout --name nas-scout --unattended

echo "ATLAS_REPO=git@github.com-atlas:Laoujin/Atlas.git" >> .env

sudo ./svc.sh install scout
sudo ./svc.sh start
```

No `sudo`? Run `./run.sh` in a DSM Task Scheduler boot-up task instead.

### 6. First research

```bash
gh workflow run research.yml --repo Laoujin/Scout \
  -f topic="test: top 3 static site generators in 2026" \
  -f depth=ceo -f format=md
gh run watch --repo Laoujin/Scout
```

Result appears at https://laoujin.github.io/Atlas/ within ~1 min of the workflow going green.

## Troubleshooting

- **Runner offline** → `sudo ~/actions-runner/svc.sh status`; check `~/actions-runner/_diag/`.
- **Push fails** → `ssh -T github.com-atlas`; verify deploy key has write access.
- **Claude auth expired** → re-run `claude` as scout.
- **`--skill` flag error** → CLI version may differ. Symlink `~/.claude/skills/scout` → `~/scout-checkout/skills/scout` and drop `--skill` from `scripts/run.sh`.

## Slash command

```bash
mkdir -p ~/.claude/commands
cp commands/research.md ~/.claude/commands/research.md
```

Then in any Claude Code session: `/research Compare X vs Y depth=deep format=html`

## Development

```bash
npm test
```

Requires [bats](https://bats-core.readthedocs.io/) for slug tests: `apt-get install bats`.

## License

MIT.
