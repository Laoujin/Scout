# `install.sh` — Design

**Date:** 2026-04-22
**Status:** Approved for implementation planning

## Problem

A new Scout user today follows a five-step manual fork flow (template-fork Scout, template-fork Atlas, delete `research/`, edit `_config.yml`, fill `docker/.env`, `docker-compose up`, paste SSH deploy key into Atlas settings, authenticate `claude` in the container). Friction is high enough that the marketing site already advertises a one-liner it doesn't ship yet:

```
curl -fsSL https://raw.githubusercontent.com/Laoujin/Scout/main/install.sh | bash -s -- --config=s1.rust.v1
```

Close the gap. The one-liner must produce an installed, polling Scout runner on the user's own hardware, pushing to the user's own Atlas repo, served via GitHub Pages — with only `docker-compose up` and `claude` login left as manual final steps.

## Goals

- **Low host-dependency footprint.** Host needs only `bash`, `curl`, `docker`. No preinstalled `gh`, `git`, `jq`, or host package manager assumptions.
- **Works on headless NAS over SSH.** No browser, no X11, no `</dev/tty` acrobatics.
- **No registry dependency.** Scout does not publish an installer image; the installer image is built from a heredoc on first run.
- **No long-lived secrets on disk.** The GitHub token used to create repos is deleted at script exit.
- **Atlas is self-contained after install.** No runtime coupling to Scout; user edits `_config.yml` to switch themes.
- **Idempotent.** Re-running the script after a mid-run failure is safe.

## Non-goals

- Publishing `scout-installer` to ghcr.io.
- Automating `claude` OAuth login (interactive; left to the user).
- Running `docker-compose up -d --build` (left to the user; script prints next-steps).
- Installing Docker on the host (prereq; script prints URL and exits if missing).
- Supporting Windows without WSL.

## Architecture

```
host (Linux / macOS / DSM / WSL)
  │
  ├── curl …/install.sh | bash -s -- --config=s1.rust.v1
  │
  ├── install.sh (~60 lines, host-side)
  │   ├── Check prereqs: bash, curl, docker → abort with URL if missing
  │   ├── mktemp -d → AUTH_DIR (host tmp); trap rm -rf on EXIT
  │   ├── mktemp -d → BUILD_CTX; write two files into it:
  │   │     - Dockerfile:
  │   │         FROM alpine:3.20
  │   │         RUN apk add --no-cache github-cli git jq openssh openssh-keygen bash curl docker-cli
  │   │         COPY installer.sh manifest.json /
  │   │         RUN chmod +x /installer.sh
  │   │         ENTRYPOINT ["/installer.sh"]
  │   │     - installer.sh (the content from `scripts/installer.sh`, fetched
  │   │       via curl from raw.githubusercontent.com at the same tag as install.sh)
  │   │     - manifest.json (fetched from themes/manifest.json on the same ref)
  │   ├── docker build -t scout-installer "$BUILD_CTX"
  │   │
  │   └── docker run --rm -it \
  │         -v "$(pwd)/scout-install:/work" \
  │         -v "$AUTH_DIR:/root/.config/gh" \
  │         -v /var/run/docker.sock:/var/run/docker.sock \   # for step 9 (volume prep)
  │         scout-installer --config=s1.rust.v1
  │
  └── installer.sh (~200 lines, runs inside container)
        (see Installer Steps below)

  on exit:
    - trap fires → $AUTH_DIR removed → gh token gone
    - install.sh prints next-steps block (docker-compose up, claude auth)
```

The host script is trivial; the installer script carries all the logic.

### Why Docker-bootstrap over alternatives

| Option | Host deps | First-run cost | Code complexity |
|---|---|---|---|
| Require `gh` pre-installed | bash+curl+docker+**gh** | 0 | Low but friction at install time |
| Static-binary `gh` into `/tmp` | bash+curl+docker | ~10 MB download | Per-OS tarball selection |
| **Docker-bootstrap** (chosen) | bash+curl+docker | One image build (~30 s) | Low — container holds the mess |

Docker is already a prereq for `scout-runner`. Reusing it for install adds zero new host requirements and erases per-OS path branching inside the installer.

## Atlas seeding

New `atlas-seed/` directory in the Scout repo. A full Jekyll site with every variant co-resident:

```
atlas-seed/
  _config.yml
  _layouts/
    default.html           # selects skeleton via {% include sites/{{ site.skeleton }}.html %}
    research.html
  _includes/
    sites/{s1,s2,s3,s4,s5,s6}.html
    cards/{v1,v2,v3,v4,v5,v6,v7}.html
  assets/
    palettes/{rust,paper,cartography,midnight,minimal,fieldnotes,solarized,nord}.css
    base.css
    logo.png
    icon.png
  index.html
  README.md
```

`_config.yml` (user-editable post-install to switch themes — no reinstall needed):

```yaml
title: Atlas
description: Research compiled on demand by Scout.
baseurl: /Atlas               # installer rewrites to /<atlas-repo-name>
scout_repo: Scout             # installer rewrites to <scout-repo-name>

# Theme variables — edit any of these and push; Pages rebuilds.
skeleton: s1                  # avoids collision with Jekyll's built-in `layout`
palette:  rust
card:     v1

defaults:
  - scope: { path: research }
    values: { layout: research, type: research }

markdown: kramdown
highlighter: rouge
```

`_layouts/default.html` applies variables:

```liquid
<link rel="stylesheet" href="{{ '/assets/base.css' | relative_url }}">
<link rel="stylesheet" href="{{ '/assets/palettes/' | append: site.palette | append: '.css' | relative_url }}">
{% include sites/{{ site.skeleton }}.html %}
```

Skeleton `s6` sets `"ignores_card": true` in `themes/manifest.json` — the Liquid in `_includes/sites/s6.html` simply doesn't render cards, so the `card` variable is silently ignored for that skeleton. No special-case logic needed in the installer.

**Duplication accepted.** Scout's `themes/` directory also contains these files, serving the marketing preview in `docs/index.html`. Keeping two copies (one driving the marketing preview, one shipping into Atlas) is cheaper than introducing a build step to deduplicate; the files change rarely.

## Installer steps (`installer.sh` inside container)

1. **Auth.** `gh auth status` — if unauthed, `gh auth login --web --hostname github.com --git-protocol ssh`. Device-code flow is headless-friendly: prints `A1B2-C3D4`, user opens `github.com/login/device` on any phone/laptop to authorize. `GH_TOKEN=…` env var is honored as a non-interactive override.
2. **Parse `--config=s1.rust.v1`.** Split on `.`, validate each piece against `themes/manifest.json` (shipped into the installer image as `/manifest.json`). Abort on unknown variant.
3. **Resolve GitHub owner.** `gh api user --jq .login` → `$OWNER`.
4. **Prompt for Scout repo name.**
   - Default `<OWNER>/Scout`.
   - If repo exists (`gh repo view` returns 0), re-prompt: `That exists. Pick a different name or Ctrl-C to abort:`
   - Loop until a free name is chosen.
5. **Prompt for Atlas repo name.** Same collision loop.
6. **Create Scout fork.** `gh repo create "$OWNER/$SCOUT_NAME" --template Laoujin/Scout --public --clone --disable-issues=false` — clones into `/work/$SCOUT_NAME`.
7. **Create Atlas repo.** `gh repo create "$OWNER/$ATLAS_NAME" --public` (empty). Then inside `/tmp/atlas-stage`:
   - `git init`, copy `atlas-seed/*`
   - `sed` `_config.yml` to set `baseurl: /$ATLAS_NAME`, `scout_repo: $SCOUT_NAME`, `skeleton: $SKEL`, `palette: $PAL`, `card: $CARD`
   - `git add .`, `git commit -m "Initial Atlas seed (skeleton=$SKEL palette=$PAL card=$CARD)"`, `git remote add origin …`, `git push -u origin main`
   - `rm -rf /tmp/atlas-stage`
8. **Enable GitHub Pages.**
   `gh api -X POST "repos/$OWNER/$ATLAS_NAME/pages" -f 'source[branch]=main' -f 'source[path]=/'`
   Idempotent-check: if 409 (already enabled), continue silently.
9. **Atlas deploy key.**
   - `ssh-keygen -t ed25519 -f /tmp/atlas_deploy -C "scout-nas" -N ""`
   - `gh api -X POST "repos/$OWNER/$ATLAS_NAME/keys" -f title=scout-nas -f "key=$(cat /tmp/atlas_deploy.pub)" -F read_only=false`
   - If an existing deploy key is titled `scout-nas`, delete it first (`gh api … DELETE`) to avoid duplicates on re-run.
   - Write private key + `ssh_config` block into the `scout-runner` Docker volume. Volume name follows `docker-compose` convention: `<project>_atlas-ssh` where `<project>` defaults to `docker` (parent dir of `docker-compose.yml`), so the volume is `docker_atlas-ssh`. Installer pins this with an explicit `name:` directive to be added to `docker-compose.yml` (see "Scope-of-change" below).
   - Volume-prep helper: `docker run --rm -v scout_atlas-ssh:/dest -v /tmp:/src:ro alpine:3.20 sh -c 'cp /src/atlas_deploy{,.pub} /dest/; cat > /dest/config <<CFG\nHost github.com-atlas\n  HostName github.com\n  User git\n  IdentityFile ~/.ssh/atlas_deploy\n  IdentitiesOnly yes\n  StrictHostKeyChecking accept-new\nCFG\nchown -R 1000:1000 /dest; chmod 700 /dest; chmod 600 /dest/atlas_deploy /dest/config'`
   - The installer container has `/var/run/docker.sock` mounted for this side-car.
10. **Runner registration token.**
    - `gh api -X POST "repos/$OWNER/$SCOUT_NAME/actions/runners/registration-token" --jq .token` → `$TOKEN`
    - Write `/work/$SCOUT_NAME/docker/.env`:
      ```
      RUNNER_URL=https://github.com/$OWNER/$SCOUT_NAME
      ATLAS_REPO=git@github.com-atlas:$OWNER/$ATLAS_NAME.git
      RUNNER_TOKEN=$TOKEN
      ```
11. **Done.** Container exits 0.

## Post-install: next-steps block (printed by host `install.sh`)

```
✓ Scout installed. Two things left — you do these:

  1. cd scout-install/<SCOUT_NAME>/docker
     docker-compose up -d --build

  2. docker exec -it scout-runner runuser -u runner -- claude
     (Log in to Anthropic, then /exit. One-time.)

Open a research issue: https://github.com/<OWNER>/<SCOUT_NAME>/issues/new?template=research.yml
Atlas (may take ~1 min on first build): https://<OWNER>.github.io/<ATLAS_NAME>/
```

## Secret hygiene

`AUTH_DIR` is a host tmp dir bind-mounted into the installer as `/root/.config/gh`. It holds the gh OAuth token (scopes: `repo`, `workflow`, `admin:public_key`).

```bash
AUTH_DIR="$(mktemp -d)"
trap 'rm -rf "$AUTH_DIR"' EXIT
```

On every script exit (success, failure, Ctrl-C), the trap fires and the token is deleted. Retry after mid-run failure costs one more device-code paste (~30 s); acceptable.

The `scout_atlas-ssh` Docker volume holds the Atlas deploy private key — that one is *supposed* to persist, it's the runtime credential.

**Docker socket exposure.** The installer container bind-mounts `/var/run/docker.sock` to run the volume-prep side-car in step 9. This grants the installer root-equivalent access to the host's Docker daemon for its short lifetime. Acceptable because (a) the installer is short-lived, (b) the image is built locally from a heredoc the user can audit in `install.sh`, and (c) the alternative — writing into a Docker volume from outside a container — requires host-side `sudo`, which we're explicitly avoiding.

## Idempotency

Re-running `install.sh` after a failed prior attempt:

| State at retry | Behaviour |
|---|---|
| `scout-installer` image already built | `docker build` no-op (layer cache hit) |
| Scout fork already created | Repo-name prompt loops until a free name (or user reuses) |
| Atlas repo created but empty | Push to `main` succeeds; no further action needed |
| Atlas repo has content | Push is rejected; installer aborts with clear message |
| Deploy key `scout-nas` exists | Delete + re-create |
| Runner token in `.env` | Overwritten (tokens expire in ~1 h anyway) |
| `scout_atlas-ssh` volume exists | Contents overwritten |

Re-running against a fully-installed system is not safe for repo creation (user must pick new names) but is safe for all local file and volume operations.

## Scope-of-change in existing repo

- **NEW**: `install.sh` (repo root). Host-side bootstrap, ~60 lines. Fetches `scripts/installer.sh` and `themes/manifest.json` from `raw.githubusercontent.com/.../main/` into its build context, then `docker build`s the installer image. A `--ref=<branch|tag>` flag overrides `main` for testing a branch without publishing.
- **NEW**: `scripts/installer.sh`. Runs inside the installer container, ~200 lines. Shipped as a normal file in the repo so it's reviewable and testable independently.
- **NEW**: `atlas-seed/` directory. Full Jekyll site, all variants. `installer.sh` `git clone`s Scout into `/work/$SCOUT_NAME` in step 6, then reads `/work/$SCOUT_NAME/atlas-seed/` to populate Atlas in step 7.
- **CHANGE**: `docker/docker-compose.yml` — add `name: scout` at top and `name: scout_atlas-ssh` under the `atlas-ssh:` volume to pin volume names independently of the parent directory name. This lets installer refer to volumes by stable names.
- **CHANGE**: `docker/run-init.sh` — no change needed. The existing `if [ ! -f atlas_deploy ]` guard (lines 29-57) correctly skips key generation when the installer has pre-provisioned one.
- **CHANGE**: `README.md` — replace the manual 5-step fork flow with the `install.sh` one-liner plus the two remaining manual steps. Keep the manual flow as a "Manual setup" subsection for users who prefer it.
- **UNCHANGED**: `.github/workflows/`, `.github/ISSUE_TEMPLATE/`, `scripts/*` (except the new `installer.sh`), `skills/`, `themes/`, `docker/Dockerfile`, `docker/entrypoint.sh`, `commands/`.

## Open questions (to be resolved during implementation, not blocking design)

- Exact Alpine package name for `openssh-keygen` — may be covered by the `openssh-client` or `openssh-keygen` package; confirm at build.
- `gh repo create --template` requires the template repo to have "Template" enabled in GitHub settings — confirm `Laoujin/Scout` has this set.
- Does `gh api repos/.../pages` require the `admin:repo` scope or is `repo` sufficient? Default `gh auth login --web` prompts for `repo` + `workflow`; if Pages fails with 403, the installer should print the scope it needs and invite re-auth.

## Testing strategy

Manual end-to-end on a disposable GitHub account:
1. Fresh Linux VM / Docker-in-Docker / DSM test container with nothing but `bash curl docker`.
2. Run the one-liner.
3. Verify: both repos created, Atlas is publishing to `github.io`, runner registered, `docker-compose up` produces a running container polling issues.
4. Open a `[research]` issue — confirm the tighten-propose-confirm-research flow completes.
5. Re-run `install.sh` in various failure states (Ctrl-C mid-auth, network failure on push, Pages API rate limit) to validate idempotency.

No automated tests for `install.sh` — the surface is GitHub's real API and Docker's real daemon. Unit-testing either in isolation would not catch the failures that matter.
