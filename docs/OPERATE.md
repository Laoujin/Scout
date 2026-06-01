# Operate

Day-to-day maintenance of a running Scout install. For first-time install, see the [README](../README.md).

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
