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

echo "→ Config: skeleton=$SKEL palette=$PAL card=$CARD"

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

# ---------- Step 3: Resolve owner ----------
OWNER=$(gh api user --jq .login)
echo "→ Authenticated as: $OWNER"

# ---------- Steps 4 + 5: Repo-name prompts ----------
prompt_repo() {
  local label="$1" default="$2" outvar="$3" name
  while true; do
    read -rp "  $label as $OWNER/[${default}]: " name
    name="${name:-$default}"
    if gh repo view "$OWNER/$name" >/dev/null 2>&1; then
      echo "  ! $OWNER/$name already exists. Pick another name (or Ctrl-C to abort)."
    else
      printf -v "$outvar" '%s' "$name"
      return
    fi
  done
}

prompt_repo "Create Scout fork" "Scout" SCOUT_NAME
prompt_repo "Create Atlas repo" "Atlas" ATLAS_NAME

# ---------- Step 6: Create Scout from template, clone into /work ----------
echo "→ Creating $OWNER/$SCOUT_NAME from template $SCOUT_UPSTREAM..."
gh repo create "$OWNER/$SCOUT_NAME" --template "$SCOUT_UPSTREAM" --public >/dev/null

SCOUT_DIR="/work/$SCOUT_NAME"
rm -rf "$SCOUT_DIR"
# Small propagation delay + retries — fresh template repos can 404 briefly
for attempt in 1 2 3 4 5; do
  if gh repo clone "$OWNER/$SCOUT_NAME" "$SCOUT_DIR" -- -q 2>/dev/null; then break; fi
  sleep 2
done
[[ -d "$SCOUT_DIR/.git" ]] || { echo "Error: failed to clone $OWNER/$SCOUT_NAME" >&2; exit 1; }

# ---------- Step 7: Create Atlas, seed from atlas-seed/, push ----------
echo "→ Creating $OWNER/$ATLAS_NAME (empty)..."
gh repo create "$OWNER/$ATLAS_NAME" --public >/dev/null

[[ -d "$SCOUT_DIR/atlas-seed" ]] || {
  echo "Error: $SCOUT_DIR/atlas-seed/ missing in template $SCOUT_UPSTREAM@$SCOUT_REF" >&2
  exit 1
}

STAGE=$(mktemp -d)
cp -a "$SCOUT_DIR/atlas-seed/." "$STAGE/"

sed -i \
  -e "s#^baseurl:.*#baseurl: /$ATLAS_NAME#" \
  -e "s#^scout_repo:.*#scout_repo: $SCOUT_NAME#" \
  -e "s#^skeleton:.*#skeleton: $SKEL#" \
  -e "s#^palette:.*#palette: $PAL#" \
  -e "s#^card:.*#card: $CARD#" \
  "$STAGE/_config.yml"

(
  cd "$STAGE"
  git init -q -b main
  git add -A
  git -c user.name="$OWNER" -c user.email="${OWNER}@users.noreply.github.com" \
      commit -qm "Initial Atlas seed (skeleton=$SKEL palette=$PAL card=$CARD)"
  git remote add origin "https://github.com/$OWNER/$ATLAS_NAME.git"
  # Retry push briefly — empty repo occasionally 404s right after create
  for attempt in 1 2 3 4 5; do
    if git push -q -u origin main 2>/dev/null; then break; fi
    sleep 2
  done
)
rm -rf "$STAGE"

# ---------- Step 8: Enable GitHub Pages ----------
echo "→ Enabling Pages on $OWNER/$ATLAS_NAME..."
if ! gh api -X POST "repos/$OWNER/$ATLAS_NAME/pages" \
       -f "source[branch]=main" -f "source[path]=/" >/dev/null 2>&1; then
  # 409 Conflict = already enabled (safe on re-run); anything else is a real error
  code=$(gh api -X POST "repos/$OWNER/$ATLAS_NAME/pages" \
           -f "source[branch]=main" -f "source[path]=/" 2>&1 | tail -1 | grep -oE '[0-9]{3}' | head -1 || true)
  [[ "$code" == "409" ]] || echo "  ! Pages API returned non-409 error; check https://github.com/$OWNER/$ATLAS_NAME/settings/pages"
fi

# ---------- Step 9: Atlas deploy key ----------
echo "→ Generating + uploading Atlas deploy key..."
KEYDIR=$(mktemp -d)
ssh-keygen -t ed25519 -f "$KEYDIR/atlas_deploy" -C "scout-nas" -N "" -q

# Remove any prior scout-nas key so re-runs don't duplicate
gh api "repos/$OWNER/$ATLAS_NAME/keys" --jq '.[] | select(.title=="scout-nas") | .id' | while read -r kid; do
  [[ -n "$kid" ]] && gh api -X DELETE "repos/$OWNER/$ATLAS_NAME/keys/$kid" >/dev/null
done

gh api -X POST "repos/$OWNER/$ATLAS_NAME/keys" \
  -f title=scout-nas \
  -f "key=$(cat "$KEYDIR/atlas_deploy.pub")" \
  -F read_only=false >/dev/null

cat > "$KEYDIR/config" <<'CFG'
Host github.com-atlas
  HostName github.com
  User git
  IdentityFile ~/.ssh/atlas_deploy
  IdentitiesOnly yes
  StrictHostKeyChecking accept-new
CFG

# Seed the runtime container's named volume via a throwaway side-car
echo "→ Seeding scout_atlas-ssh volume..."
docker volume create scout_atlas-ssh >/dev/null
docker run --rm \
  -v scout_atlas-ssh:/dest \
  -v "$KEYDIR:/src:ro" \
  alpine:3.20 sh -c '
    cp /src/atlas_deploy /src/atlas_deploy.pub /src/config /dest/
    chown -R 1000:1000 /dest
    chmod 700 /dest
    chmod 600 /dest/atlas_deploy /dest/config
    chmod 644 /dest/atlas_deploy.pub
  ' >/dev/null
rm -rf "$KEYDIR"

# ---------- Step 10: Runner registration token + docker/.env ----------
echo "→ Fetching runner-registration token..."
RUNNER_TOKEN=$(gh api -X POST "repos/$OWNER/$SCOUT_NAME/actions/runners/registration-token" --jq .token)

cat > "$SCOUT_DIR/docker/.env" <<EOF
# Generated by Scout installer on $(date -u +%Y-%m-%dT%H:%M:%SZ)
RUNNER_URL=https://github.com/$OWNER/$SCOUT_NAME
ATLAS_REPO=git@github.com-atlas:$OWNER/$ATLAS_NAME.git
RUNNER_TOKEN=$RUNNER_TOKEN
EOF
chmod 600 "$SCOUT_DIR/docker/.env"

# ---------- Step 11: Hand off post-install summary to host install.sh ----------
cat > /work/.next <<EOF
SCOUT_NAME=$SCOUT_NAME
ATLAS_NAME=$ATLAS_NAME
OWNER=$OWNER
EOF

echo "✓ Container work done."
