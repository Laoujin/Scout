# Operate

Day-to-day maintenance of a running Scout install. For first-time install, see the [README](../README.md).

## Two ways to run research

| Command | Where | Billing | Use |
|--------------|--------------------------|-------------------------|---------------------------------------------|
| `/scout`       | interactive Claude Code  | your subscription       | at the desk; runs in-session, incl. parallel expeditions |
| `/scout-async` | GitHub issue → NAS runner | API (headless `claude -p`) | hands-off, fire-from-phone, durable, rerun machinery |

After 2026-06-15 headless `claude -p` is API-billed, so `/scout-async` always costs API; `/scout` stays on your subscription because the interactive session (and its subagents) are the model.

`/scout` self-locates the Scout checkout via `~/.scout/dir` (written by the installer) and reads `ATLAS_REPO` from `docker/.env`. It's symlinked into `~/.claude/commands/`, so `git pull` in Scout updates it automatically.

**Upgrading an existing install:** re-run `bash commands/install-scout-command.sh <you>/Scout <atlas-url>` (or the installer's slash-command step). This switches `/scout` to the interactive command and adds `/scout-async`. Manual equivalent: symlink `~/.claude/commands/scout.md` → `<scout>/.claude/commands/scout.md`, copy+substitute `scout-async.md`, and write `<scout>` to `~/.scout/dir`.

## Update Scout, Claude

```bash
cd ~/Scout
git pull
cd docker
docker-compose build --pull
docker-compose up -d
```

Named Docker volumes preserve the Claude login, runner registration, and Atlas deploy key across rebuilds. You don't re-auth.

## Re-authenticate Claude

If the auth expires (subscription tokens age out, API keys can be rotated):

```bash
docker exec -it scout-runner runuser -u runner -- claude
# log in, /exit
```

## Rotate runner token

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

## Tune model cost

Since 15 June 2026 headless Claude Code runs bill a separate monthly credit at API rates (Pro $20, Max 5× $100, Max 20× $200) rather than your interactive subscription quota. Scout picks a model per research depth to keep that credit going further:

| Depth        | Tier var            | Default  |
|--------------|---------------------|----------|
| `recon`      | `SCOUT_MODEL_CHEAP` | `haiku`  |
| `survey`     | `SCOUT_MODEL_BASE`  | `sonnet` |
| `expedition` | `SCOUT_MODEL_DEEP`  | `opus`   |

`SCOUT_MODEL_BASE` also drives sharpening, view authoring, and parent synthesis; `SCOUT_MODEL_CHEAP` drives view-candidacy.

Defaults live in [`scripts/lib-models.sh`](../scripts/lib-models.sh). Override without touching code by setting repo **Variables** (Settings → Secrets and variables → Actions → Variables):

```bash
gh variable set SCOUT_MODEL_BASE --body opus    # bump the default research tier
gh variable set SCOUT_MODEL      --body sonnet  # month-end clamp: force every tier cheap
gh variable delete SCOUT_MODEL                  # back to the per-depth defaults
```

Unset Variables fall through to the `lib-models.sh` defaults. `SCOUT_MODEL` (if set) overrides all three tiers at once.
