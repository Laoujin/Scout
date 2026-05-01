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
