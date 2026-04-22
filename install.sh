#!/usr/bin/env bash
# Scout one-liner installer. Bootstraps a disposable Docker container that
# creates your Scout + Atlas repos, enables Pages, wires secrets, and seeds
# the runtime's atlas-ssh volume.
#
# Usage:
#   curl -fsSL https://raw.githubusercontent.com/Laoujin/Scout/main/install.sh \
#     | bash -s -- --config=s1.rust.v1
#
# Flags:
#   --config=<skeleton>.<palette>.<card>   Required. e.g. s1.rust.v1
#   --ref=<branch|tag>                      Default: main
#   --upstream=<owner>/<repo>               Default: Laoujin/Scout
#   --dir=<path>                            Default: $PWD/scout-install
set -euo pipefail

# When invoked via `curl … | bash`, stdin is the pipe. Re-attach to the TTY so
# interactive prompts (gh auth, repo-name read) and `docker run -it` work.
if [ ! -t 0 ] && [ -c /dev/tty ]; then
  exec </dev/tty
fi
if [ ! -t 0 ]; then
  echo "Error: no TTY available. Run install.sh from an interactive shell, or set GH_TOKEN= and retry." >&2
  exit 1
fi

CONFIG=""
REF="main"
UPSTREAM="Laoujin/Scout"
INSTALL_DIR="$PWD/scout-install"
LOCAL_SCOUT=""

for arg in "$@"; do
  case "$arg" in
    --config=*)   CONFIG="${arg#*=}" ;;
    --ref=*)      REF="${arg#*=}" ;;
    --upstream=*) UPSTREAM="${arg#*=}" ;;
    --dir=*)      INSTALL_DIR="${arg#*=}" ;;
    --local=*)    LOCAL_SCOUT="${arg#*=}" ;;   # use local checkout instead of fetching from GitHub
    -h|--help)    sed -n '3,16p' "$0" 2>/dev/null || grep '^#' "$0" | head -16; exit 0 ;;
    *) echo "Unknown argument: $arg" >&2; exit 2 ;;
  esac
done

[[ -n "$CONFIG" ]] || { echo "Error: --config=<skeleton>.<palette>.<card> is required" >&2; exit 2; }

missing=()
for cmd in bash curl docker; do
  command -v "$cmd" >/dev/null 2>&1 || missing+=("$cmd")
done
if [[ ${#missing[@]} -gt 0 ]]; then
  echo "Missing prerequisites: ${missing[*]}" >&2
  case " ${missing[*]} " in
    *" docker "*) echo "Install Docker: https://docs.docker.com/engine/install/" >&2 ;;
  esac
  exit 1
fi

docker info >/dev/null 2>&1 || { echo "Docker daemon is not reachable. Start Docker and retry." >&2; exit 1; }

AUTH_DIR="$(mktemp -d)"
BUILD_CTX="$(mktemp -d)"
trap 'rm -rf "$AUTH_DIR" "$BUILD_CTX"' EXIT

if [[ -n "$LOCAL_SCOUT" ]]; then
  echo "→ Using local checkout: $LOCAL_SCOUT"
  [[ -f "$LOCAL_SCOUT/scripts/installer.sh" && -f "$LOCAL_SCOUT/themes/manifest.json" ]] || {
    echo "Error: --local=$LOCAL_SCOUT missing scripts/installer.sh or themes/manifest.json" >&2
    exit 1
  }
  cp "$LOCAL_SCOUT/scripts/installer.sh" "$BUILD_CTX/installer.sh"
  cp "$LOCAL_SCOUT/themes/manifest.json" "$BUILD_CTX/manifest.json"
else
  RAW="https://raw.githubusercontent.com/${UPSTREAM}/${REF}"
  echo "→ Fetching installer components from ${UPSTREAM}@${REF}..."
  curl -fsSL "$RAW/scripts/installer.sh"   -o "$BUILD_CTX/installer.sh"
  curl -fsSL "$RAW/themes/manifest.json"   -o "$BUILD_CTX/manifest.json"
fi

cat > "$BUILD_CTX/Dockerfile" <<'DOCKERFILE'
FROM alpine:3.20
RUN apk add --no-cache bash curl git jq openssh-keygen openssh-client \
                       github-cli docker-cli ca-certificates
COPY installer.sh manifest.json /
RUN chmod +x /installer.sh
ENTRYPOINT ["/installer.sh"]
DOCKERFILE

echo "→ Building scout-installer image..."
docker build -q -t scout-installer "$BUILD_CTX" >/dev/null

mkdir -p "$INSTALL_DIR"

echo "→ Running installer..."
docker run --rm -it \
  -v "$INSTALL_DIR:/work" \
  -v "$AUTH_DIR:/root/.config/gh" \
  -v /var/run/docker.sock:/var/run/docker.sock \
  -e SCOUT_CONFIG="$CONFIG" \
  -e SCOUT_UPSTREAM="$UPSTREAM" \
  -e SCOUT_REF="$REF" \
  scout-installer

# Post-install next steps — installer wrote SCOUT_NAME + ATLAS_NAME + OWNER to /work/.next
if [[ -f "$INSTALL_DIR/.next" ]]; then
  # shellcheck disable=SC1091
  source "$INSTALL_DIR/.next"
  cat <<EOF

────────────────────────────────────────────────────────────────────────
  Scout installed. Two things left — you do these:

    cd "$INSTALL_DIR/$SCOUT_NAME/docker"
    docker-compose up -d --build

    docker exec -it scout-runner runuser -u runner -- claude
      (Log in to Anthropic, then /exit. One-time.)

  Open a research issue: https://github.com/$OWNER/$SCOUT_NAME/issues/new?template=research.yml
  Atlas (first build ~1 min): https://$OWNER.github.io/$ATLAS_NAME/
────────────────────────────────────────────────────────────────────────

EOF
  rm -f "$INSTALL_DIR/.next"
fi
