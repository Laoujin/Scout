# Manual install

Replicates what `install.sh` does, step by step. Takes ~10 min.

Prereqs on your always-on host: `git`, `docker` + `docker-compose`, `ssh-keygen`. `gh` is optional — you can do the GitHub bits via the web UI.

## 1. Fork Scout

Fork [`Laoujin/Scout`](https://github.com/Laoujin/Scout) to your account (top-right **Fork** button, or `gh repo fork Laoujin/Scout --clone=false`). On your fork:

- **Settings → Actions → General** → enable workflows (forks have Actions disabled by default)
- **Settings → General → Features** → tick **Issues**

Clone it to your host:

```bash
git clone git@github.com:<you>/Scout.git
cd Scout
```

## 2. Create Atlas

Create an empty repo `<you>/Atlas` on GitHub (no README, no license). Scaffold it with the Compass theme as a git submodule:

```bash
mkdir /tmp/atlas-init && cd /tmp/atlas-init
mkdir research

cat > _config.yml <<'YAML'
title: Atlas
description: Research compiled on demand by Scout.

baseurl: /Atlas
scout_repo: <you>/Scout

skeleton: s5
palette:  cartography
card:     v1

defaults:
  - scope:
      path: research
    values:
      layout: research
      type: research

# Compass theme (git submodule). Update with:
#   git submodule update --remote compass && git commit -am "bump compass"
layouts_dir: compass/_layouts
includes_dir: compass/_includes
assets_base: /compass/assets

exclude:
  - README.md
  - .gitignore
  - compass/_config.yml
  - compass/serve.ps1
  - compass/research
  - compass/index.html
  - compass/Gemfile
  - compass/Gemfile.lock

markdown: kramdown
highlighter: rouge
YAML

cat > index.html <<'HTML'
---
layout: default
---
HTML

cat > Gemfile <<'RUBY'
source "https://rubygems.org"
gem "jekyll", "~> 4.3"
gem "webrick", "~> 1.8"
RUBY

git init -b main
git submodule add https://github.com/Laoujin/Compass.git compass
git add -A
git commit -m "Scaffold Atlas with compass submodule"
git remote add origin git@github.com:<you>/Atlas.git
git push -u origin main
```

If you renamed Atlas to something other than `Atlas`, set `baseurl` to `/<your-repo-name>`.

To pull layout updates later: `cd Atlas && git submodule update --remote compass && git commit -am "bump compass" && git push`. GitHub Pages automatically initialises public submodules.

## 3. Enable GitHub Pages

On Atlas: **Settings → Pages → Source: Deploy from a branch → `main` / `/`** → Save. First build takes ~1 min; Pages URL is `https://<you>.github.io/Atlas/`.

## 4. Register the runner

On Scout: **Settings → Actions → Runners → New self-hosted runner → Linux x64**. Copy the registration token (expires in ~1 h — don't close the page yet).

## 5. Atlas deploy key

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

## 6. Seed the `scout_atlas-ssh` volume

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

## 7. Fill `docker/.env`

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

## 8. Create `profile.yml`

The runner bind-mounts `profile.yml` (gitignored) from your Scout fork. The file must exist before the next step — otherwise Docker creates a *directory* at the mount source instead.

From your Scout fork root:

```bash
cat > profile.yml <<'EOF'
# Scout identity profile. See profile.example.yml for fields and examples.
# Until you add fields below, sharpening behaves with no profile context.
EOF
chmod 644 profile.yml   # required: umask 077 (default on Synology, etc.) makes it 600 → unreadable by container's runner UID
```

Edit `profile.yml` to set your identity (location, languages, currency, interests), or leave it as the empty skeleton if you don't want profile injection. See `profile.example.yml` for the full field list.

## 9. Start the runner

```bash
docker-compose up -d --build
```

Check **Settings → Actions → Runners** on Scout — `nas-scout` should appear **Idle** within ~30 s.

## 10. Authenticate Claude (one-time)

```bash
docker exec -it scout-runner runuser -u runner -- claude
# Log in to Anthropic, then /exit
```

Done. Open a research Issue on Scout to verify the flow.
