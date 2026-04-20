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

## Handoff — what the user still needs to do

All local scaffolding is committed on this branch. The remaining steps require owner credentials or NAS access and must be done by you:

1. **Push Scout and create Atlas on GitHub:**
   ```bash
   # From Scout (this repo):
   git push origin master

   # From the sibling atlas directory (../atlas):
   gh repo create Laoujin/atlas --public --source=. --push
   gh api -X POST repos/Laoujin/atlas/pages -f source[branch]=main -f source[path]=/
   ```
   Atlas Pages will live at https://laoujin.github.io/atlas/ within ~1 minute.

2. **Synology setup** — follow the "Synology setup" section below on the NAS.

3. **First research (smoke test):**
   ```bash
   gh workflow run research.yml --repo Laoujin/Scout \
     -f topic="test: top 3 static site generators in 2026 for a personal notes site" \
     -f depth=ceo -f format=md
   gh run watch --repo Laoujin/Scout
   ```
   Confirm the artifact appears on Atlas. If any output rule is violated, tune `skills/scout/SKILL.md`, commit, push, and re-run.

## Synology setup

These steps set up a dedicated `scout` user on a Synology NAS (DSM 7.2+) with Container Manager installed. Adapt for your DSM version; edit this section to capture anything that differed on your machine.

### 1. Create the `scout` user

Via DSM Control Panel → User → Create → `scout`, or via SSH as root:

```bash
synouser --add scout 'temporary-password' 'Scout runner' 0 '' 0
# Put scout into the docker group (future-proofing; MVP does not use docker)
synogroup --member docker scout 2>/dev/null || true
```

Set a real password, then SSH in as `scout` for the rest.

### 2. Install runtime dependencies as `scout`

```bash
# Node.js via nvm (inside scout's home)
curl -o- https://raw.githubusercontent.com/nvm-sh/nvm/v0.40.1/install.sh | bash
exec bash          # reload shell so nvm is on PATH
nvm install 22
nvm use 22
node --version     # should print v22.x

# git is pre-installed on DSM; if not: install via Entware.

# gh (GitHub CLI) — download the Linux tarball from
# https://github.com/cli/cli/releases, extract gh to ~/bin/, add ~/bin to PATH.

# Claude Code
npm install -g @anthropic-ai/claude-code
claude --version

# Playwright (fallback path only)
npm install -g playwright
npx playwright install chromium
```

### 3. Authenticate Claude once (interactive)

```bash
claude                    # interactive OAuth flow
# Follow the prompts; credentials land in ~/.claude/. Exit with /exit.
ls -la ~/.claude/
claude --print "hello" 2>&1 | head -5
```

### 4. Authenticate gh

```bash
gh auth login             # GitHub.com, HTTPS, login with web browser (paste device code)
```

### 5. Atlas SSH deploy key

```bash
ssh-keygen -t ed25519 -f ~/.ssh/atlas_deploy -C "scout-atlas-deploy" -N ""
cat ~/.ssh/atlas_deploy.pub
```

Copy the printed key. On GitHub → `Laoujin/atlas` → Settings → Deploy keys → Add deploy key → title `scout-nas`, paste public key, check **Allow write access**, Save.

Append to `~/.ssh/config`:

```
Host github.com-atlas
  HostName github.com
  User git
  IdentityFile ~/.ssh/atlas_deploy
  IdentitiesOnly yes
```

Verify:

```bash
ssh -T github.com-atlas 2>&1
# Expected: "Hi Laoujin/atlas! You've successfully authenticated…"
```

### 6. Register the GitHub Actions self-hosted runner

From GitHub → `Laoujin/Scout` → Settings → Actions → Runners → New self-hosted runner → Linux x64.

Follow the on-screen download/config. Example (values will differ):

```bash
cd ~
mkdir actions-runner && cd actions-runner
curl -o actions-runner-linux-x64.tar.gz -L \
  https://github.com/actions/runner/releases/download/v2.321.0/actions-runner-linux-x64-2.321.0.tar.gz
tar xzf ./actions-runner-linux-x64.tar.gz

./config.sh \
  --url https://github.com/Laoujin/Scout \
  --token <token-from-github> \
  --labels scout \
  --name nas-scout \
  --unattended
```

Install as a service:

```bash
sudo ./svc.sh install scout
sudo ./svc.sh start
sudo ./svc.sh status
```

If DSM doesn't allow `sudo`, run under `systemd --user` or DSM Task Scheduler (trigger at boot, command: `/volume1/homes/scout/actions-runner/run.sh`).

Configure the Atlas SSH alias for the runner:

Append to `~/actions-runner/.env`:

```
ATLAS_REPO=git@github.com-atlas:Laoujin/atlas.git
```

Restart the service: `sudo ./svc.sh stop && sudo ./svc.sh start`.

### 7. First research (smoke test)

From any machine:

```bash
gh workflow run research.yml --repo Laoujin/Scout \
  -f topic="test: top 3 static site generators in 2026" \
  -f depth=ceo -f format=md
gh run watch --repo Laoujin/Scout
```

Expected: run finishes green; https://laoujin.github.io/atlas/ shows a new entry within a minute of the workflow turning green.

### Troubleshooting

- **Runner offline** → `sudo ./svc.sh status`; check `~/actions-runner/_diag/` logs.
- **Push fails** → `ssh -T github.com-atlas` to re-verify; check deploy key has write access.
- **Claude auth expired** → SSH in as scout, run `claude`, re-auth, exit.
- **`--skill` flag error** → your Claude Code CLI version may use a different flag (`--skill` is version-dependent). Run `claude --help` and adjust `scripts/run.sh` accordingly. Common alternatives: place `skills/scout/SKILL.md` at `~/.claude/skills/scout/SKILL.md` (symlink works) and let Claude auto-discover; then drop the `--skill` flag.

## Slash command (`/research`)

```bash
mkdir -p ~/.claude/commands
cp commands/research.md ~/.claude/commands/research.md
```

From any Claude Code session:

```
/research Compare X vs Y for my Z use case depth=deep format=html
```

## Development

```bash
npm test          # runs slug + build_index tests
npm run test:slug
npm run test:index
```

Requires [bats](https://bats-core.readthedocs.io/) for the slug tests: `apt-get install bats` / `brew install bats-core`.

## License

MIT. See LICENSE.
