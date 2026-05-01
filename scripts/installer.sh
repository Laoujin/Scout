#!/usr/bin/env bash
# Runs inside the disposable scout-installer Alpine container, orchestrated by
# the host-side install.sh. Creates both GitHub repos, enables Pages, generates
# + uploads the Atlas deploy key, seeds the scout_atlas-ssh Docker volume, and
# writes docker/.env with a fresh runner-registration token.
#
# Expects these env vars (passed via `docker run -e`):
#   SCOUT_CONFIG    <skeleton>.<palette>.<card>   e.g. s1.rust.v1
#   SCOUT_UPSTREAM  <owner>/<repo>                template for the Scout fork
#   SCOUT_REF       branch or tag for upstream    (informational)
#
# Mounts expected:
#   /work                        ← host's $INSTALL_DIR (Scout fork lands here)
#   /root/.config/gh             ← ephemeral gh auth cache (host tmpdir)
#   /var/run/docker.sock         ← host docker daemon (used for volume seed)
#
# On success writes /work/.next so install.sh can print the post-install summary.

set -euo pipefail

# SIGINT during `read` inside the prompt_repo while-true loop would otherwise
# just fail the read and keep looping (set -e doesn't fire inside loops).
trap 'echo; echo "Aborted."; exit 130' INT

# tty-aware color helpers
if [[ -t 1 ]]; then
  C_STEP=$'\033[0m' C_OK=$'\033[1;32m' C_WARN=$'\033[1;33m' C_OFF=$'\033[0m'
else
  C_STEP='' C_OK='' C_WARN='' C_OFF=''
fi
# step prints "→ msg" WITHOUT newline. Bare `ok` appends " ✓\n" to that line.
# `ok "msg"` is a standalone line (no preceding step).
step() { printf '%s→%s %s' "$C_STEP" "$C_OFF" "$*"; }
ok() {
  if [[ $# -eq 0 ]]; then
    printf ' %s✓%s\n' "$C_OK" "$C_OFF"
  else
    printf '%s✓%s %s\n' "$C_OK" "$C_OFF" "$*"
  fi
}
warn() { printf '%s!%s %s\n' "$C_WARN" "$C_OFF" "$*"; }

: "${SCOUT_CONFIG:?SCOUT_CONFIG is required (bug in host install.sh)}"
: "${SCOUT_UPSTREAM:=Laoujin/Scout}"
: "${SCOUT_REF:=main}"

# ---------- Parse + validate --config ----------
IFS='.' read -r SKEL PAL CARD <<<"$SCOUT_CONFIG"
[[ -n "${SKEL:-}" && -n "${PAL:-}" && -n "${CARD:-}" ]] || {
  echo "Error: --config must be <skeleton>.<palette>.<card>, got: $SCOUT_CONFIG" >&2
  exit 2
}

validate() {
  local kind="$1" value="$2" path="$3" valid
  valid=$(jq -r "$path | keys[]" /manifest.json)
  grep -Fxq "$value" <<<"$valid" || {
    echo "Error: unknown $kind '$value'. Valid: $(tr '\n' ' ' <<<"$valid")" >&2
    exit 2
  }
}
validate skeleton "$SKEL" '.sites'
validate palette  "$PAL"  '.palettes'
validate card     "$CARD" '.cards'

ok "Config: skeleton=$SKEL palette=$PAL card=$CARD"

# ---------- Step 1: gh auth ----------
if ! gh auth status >/dev/null 2>&1; then
  if [[ -n "${GH_TOKEN:-}" ]]; then
    printf '%s\n' "$GH_TOKEN" | gh auth login --hostname github.com --with-token
  else
    echo "→ GitHub login required. The device-code flow prints a code — open"
    echo "   https://github.com/login/device on any browser (phone, laptop) to paste it."
    gh auth login --hostname github.com --web --git-protocol https \
                  -s repo -s workflow -s admin:public_key
  fi
fi

# Git credential helper for push/clone over HTTPS
gh auth setup-git >/dev/null

# ---------- Step 3: Resolve default owner ----------
AUTHED_USER=$(gh api user --jq .login)
ok "Authenticated as $AUTHED_USER"

# Default owner for the prompts. --org on the host overrides, and the user
# can still type owner/name at the prompt to pick a different one per repo.
DEFAULT_OWNER="${SCOUT_ORG:-$AUTHED_USER}"

# ---------- Steps 4 + 5: Repo prompts (accept owner/name or name) ----------
# Sets ${prefix}_OWNER and ${prefix}_NAME.
prompt_repo() {
  local label="$1" def_owner="$2" def_name="$3" prefix="$4"
  local input owner name
  while true; do
    read -rp "  $label [${def_owner}/${def_name}]: " input
    input="${input:-$def_owner/$def_name}"
    if [[ "$input" == */* ]]; then
      owner="${input%%/*}"
      name="${input#*/}"
    else
      owner="$def_owner"
      name="$input"
    fi
    if [[ -z "$owner" || -z "$name" || "$name" == */* ]]; then
      echo "  ! Invalid: expected <owner>/<name> or <name>. Try again."
      continue
    fi
    if gh repo view "$owner/$name" >/dev/null 2>&1; then
      echo "  ! $owner/$name already exists. Pick another (or Ctrl-C to abort)."
    else
      printf -v "${prefix}_OWNER" '%s' "$owner"
      printf -v "${prefix}_NAME"  '%s' "$name"
      return
    fi
  done
}

prompt_repo "Fork Scout as"        "$DEFAULT_OWNER" "${SCOUT_NAME_DEFAULT:-Scout}" SCOUT
prompt_repo "Create Atlas repo as" "$DEFAULT_OWNER" "Atlas" ATLAS

# ---------- Step 6: Fork Scout, enable Actions + Issues, clone into /work ----------
step "Forking $SCOUT_UPSTREAM as $SCOUT_OWNER/$SCOUT_NAME..."
fork_args=(--fork-name "$SCOUT_NAME" --clone=false --default-branch-only)
[[ "$SCOUT_OWNER" != "$AUTHED_USER" ]] && fork_args+=(--org "$SCOUT_OWNER")
gh repo fork "$SCOUT_UPSTREAM" "${fork_args[@]}" >/dev/null
ok

step "Enabling Actions..."
gh api -X PUT "repos/$SCOUT_OWNER/$SCOUT_NAME/actions/permissions" \
  -F enabled=true -f allowed_actions=all >/dev/null
ok

step "Enabling Issues..."
gh repo edit "$SCOUT_OWNER/$SCOUT_NAME" --enable-issues >/dev/null
ok

step "Creating scout-research label..."
gh label create scout-research \
  --color c2410c \
  --description "Scout research request" \
  --repo "$SCOUT_OWNER/$SCOUT_NAME" >/dev/null 2>&1 || true
ok

SCOUT_DIR="/work/$SCOUT_NAME"
rm -rf "$SCOUT_DIR"
step "Cloning into $SCOUT_DIR..."
for attempt in 1 2 3 4 5; do
  if gh repo clone "$SCOUT_OWNER/$SCOUT_NAME" "$SCOUT_DIR" -- -q 2>/dev/null; then break; fi
  sleep 2
done
[[ -d "$SCOUT_DIR/.git" ]] || { echo "Error: failed to clone $SCOUT_OWNER/$SCOUT_NAME" >&2; exit 1; }
ok

# ---------- Step 7: Create Atlas, scaffold with compass submodule, push ----------
step "Creating $ATLAS_OWNER/$ATLAS_NAME (empty)..."
gh repo create "$ATLAS_OWNER/$ATLAS_NAME" --public >/dev/null
ok

STAGE=$(mktemp -d)
mkdir -p "$STAGE/research"

cat > "$STAGE/_config.yml" <<EOF
title: Atlas
description: Research compiled on demand by Scout.

# baseurl must match your Atlas repo name for project Pages
# (e.g. /$ATLAS_NAME serves at https://$ATLAS_OWNER.github.io/$ATLAS_NAME/).
baseurl: /$ATLAS_NAME
scout_repo: $SCOUT_OWNER/$SCOUT_NAME

# --- Theme variables (edit any of these, push, GitHub Pages rebuilds) ---
# Skeletons:  s1 s2 s3 s4 s5 s6   (site layout)
# Palettes:   rust paper cartography midnight minimal fieldnotes solarized nord
# Cards:      v1 v2 v3 v4 v5 v6 v7
skeleton: $SKEL
palette:  $PAL
card:     $CARD

# Research folders under /research/ get layout=research + type=research automatically.
defaults:
  - scope:
      path: research
    values:
      layout: research
      type: research

# Compass theme (git submodule at compass/). Update with:
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
EOF

cat > "$STAGE/index.html" <<'EOF'
---
layout: default
---
EOF

cat > "$STAGE/Gemfile" <<'EOF'
source "https://rubygems.org"

gem "jekyll", "~> 4.3"
gem "webrick", "~> 1.8"
EOF

cat > "$STAGE/.gitignore" <<'EOF'
.DS_Store
*.swp
node_modules/
_previews
_site
.jekyll-cache
Gemfile.lock
EOF

step "Scaffolding Atlas (skeleton=$SKEL palette=$PAL card=$CARD) with compass submodule..."
(
  cd "$STAGE"
  git init -q -b main
  git submodule add -q https://github.com/Laoujin/Compass.git compass
  git add -A
  git -c user.name="$AUTHED_USER" -c user.email="${AUTHED_USER}@users.noreply.github.com" \
      commit -qm "Scaffold Atlas with compass submodule (skeleton=$SKEL palette=$PAL card=$CARD)"
  git remote add origin "https://github.com/$ATLAS_OWNER/$ATLAS_NAME.git"
  for attempt in 1 2 3 4 5; do
    if git push -q -u origin main 2>/dev/null; then break; fi
    sleep 2
  done
)
rm -rf "$STAGE"
ok

# ---------- Step 8: Enable GitHub Pages + set repo website ----------
PAGES_URL="https://${ATLAS_OWNER}.github.io/${ATLAS_NAME}/"

step "Enabling Pages ($PAGES_URL)..."
if ! gh api -X POST "repos/$ATLAS_OWNER/$ATLAS_NAME/pages" \
       -f "source[branch]=main" -f "source[path]=/" >/dev/null 2>&1; then
  code=$(gh api -X POST "repos/$ATLAS_OWNER/$ATLAS_NAME/pages" \
           -f "source[branch]=main" -f "source[path]=/" 2>&1 | tail -1 | grep -oE '[0-9]{3}' | head -1 || true)
  [[ "$code" == "409" ]] || warn "Pages API returned non-409 error; check https://github.com/$ATLAS_OWNER/$ATLAS_NAME/settings/pages"
fi
ok

step "Setting repo homepage..."
gh api -X PATCH "repos/$ATLAS_OWNER/$ATLAS_NAME" \
  -f "homepage=$PAGES_URL" >/dev/null
ok

# ---------- Step 9: Atlas deploy key ----------
step "Generating + uploading Atlas deploy key..."
# Put the keys under /work (= $SCOUT_HOST_WORK on host) so the side-car
# docker run — which talks to the HOST daemon via the socket — can mount
# them by their host path. Container-local /tmp is invisible to the host.
KEYDIR=/work/.scout-keys
rm -rf "$KEYDIR" && mkdir -p "$KEYDIR"
ssh-keygen -t ed25519 -f "$KEYDIR/atlas_deploy" -C "scout-nas" -N "" -q

# Remove any prior scout-nas key so re-runs don't duplicate
gh api "repos/$ATLAS_OWNER/$ATLAS_NAME/keys" --jq '.[] | select(.title=="scout-nas") | .id' | while read -r kid; do
  [[ -n "$kid" ]] && gh api -X DELETE "repos/$ATLAS_OWNER/$ATLAS_NAME/keys/$kid" >/dev/null
done

gh api -X POST "repos/$ATLAS_OWNER/$ATLAS_NAME/keys" \
  -f title=scout-nas \
  -f "key=$(cat "$KEYDIR/atlas_deploy.pub")" \
  -F read_only=false >/dev/null
ok

cat > "$KEYDIR/config" <<'CFG'
Host github.com-atlas
  HostName github.com
  User git
  IdentityFile ~/.ssh/atlas_deploy
  IdentitiesOnly yes
  StrictHostKeyChecking accept-new
CFG

# Seed the runtime container's named volume via a throwaway side-car.
# Translate /work/... to its real host path so the daemon can find it.
: "${SCOUT_HOST_WORK:?SCOUT_HOST_WORK is required (bug in host install.sh)}"
HOST_KEYDIR="${KEYDIR/#\/work/$SCOUT_HOST_WORK}"

step "Seeding scout_atlas-ssh volume..."
docker volume create scout_atlas-ssh >/dev/null
docker run --rm \
  -v scout_atlas-ssh:/dest \
  -v "$HOST_KEYDIR:/src:ro" \
  alpine:3.20 sh -c '
    cp /src/atlas_deploy /src/atlas_deploy.pub /src/config /dest/
    chown -R 1000:1000 /dest
    chmod 700 /dest
    chmod 600 /dest/atlas_deploy /dest/config
    chmod 644 /dest/atlas_deploy.pub
  ' >/dev/null
rm -rf "$KEYDIR"
ok

# ---------- Step 10: Runner registration token + docker/.env ----------
step "Fetching runner token + writing docker/.env..."
RUNNER_TOKEN=$(gh api -X POST "repos/$SCOUT_OWNER/$SCOUT_NAME/actions/runners/registration-token" --jq .token)
ok

cat > "$SCOUT_DIR/docker/.env" <<EOF
# Generated by Scout installer on $(date -u +%Y-%m-%dT%H:%M:%SZ)
COMPOSE_PROJECT_NAME=scout
RUNNER_URL=https://github.com/$SCOUT_OWNER/$SCOUT_NAME
ATLAS_REPO=git@github.com-atlas:$ATLAS_OWNER/$ATLAS_NAME.git
RUNNER_TOKEN=$RUNNER_TOKEN
EOF
chmod 600 "$SCOUT_DIR/docker/.env"

# Tell the Scout workflow where Atlas lives, when it isn't at the default
# (<scout-owner>/Atlas). Without these the workflow constructs the wrong URL.
step "Setting workflow vars on $SCOUT_OWNER/$SCOUT_NAME..."
if [[ "$ATLAS_OWNER" != "$SCOUT_OWNER" ]]; then
  gh variable set ATLAS_REPO_OWNER --body "$ATLAS_OWNER" -R "$SCOUT_OWNER/$SCOUT_NAME" >/dev/null
fi
if [[ "$ATLAS_NAME" != "Atlas" ]]; then
  gh variable set ATLAS_REPO_NAME --body "$ATLAS_NAME" -R "$SCOUT_OWNER/$SCOUT_NAME" >/dev/null
fi
ok

# ---------- Step 11: Hand off post-install summary to host install.sh ----------
cat > /work/.next <<EOF
SCOUT_OWNER=$SCOUT_OWNER
SCOUT_NAME=$SCOUT_NAME
ATLAS_OWNER=$ATLAS_OWNER
ATLAS_NAME=$ATLAS_NAME
EOF

# Chown the Scout clone (and handoff file) back to the host user — the installer
# ran as root inside the container, so on the bind-mounted host they'd otherwise
# be root-owned and docker-compose etc. can't read docker/.env (chmod 600).
if [[ -n "${HOST_UID:-}" && -n "${HOST_GID:-}" ]]; then
  chown -R "$HOST_UID:$HOST_GID" "$SCOUT_DIR" /work/.next 2>/dev/null || true
fi

ok "Container work done."
