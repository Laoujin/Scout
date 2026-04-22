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
#   --dir=<path>                            Full path to clone Scout into.
#                                           Default: $PWD/Scout (prompted when
#                                           not passed).
#   --org=<org>                             Fork + create Atlas under this org
#                                           instead of the authenticated user
#                                           (required when the user already owns
#                                           the upstream, e.g. Laoujin forking
#                                           Laoujin/Scout).
set -euo pipefail

# Make Ctrl-C reliably abort. Without this, SIGINT during `read` inside a
# while-true loop just fails the read and keeps going — set -e doesn't fire
# inside loops.
trap 'echo; echo "Aborted."; exit 130' INT

# When invoked via `curl … | bash`, bash reads *this script* from stdin line by
# line. We can't just `exec </dev/tty` — that would make bash read subsequent
# script lines from the keyboard. Instead, re-download to a temp file and
# re-exec with /dev/tty as stdin, so the new bash reads the script from a file
# and interactive prompts work.
if [ -z "${SCOUT_INSTALL_REEXEC:-}" ] && [ ! -t 0 ]; then
  if [ ! -c /dev/tty ]; then
    echo "Error: no TTY available. Run install.sh from an interactive shell." >&2
    exit 1
  fi
  _tmp=$(mktemp)
  _url="${SCOUT_INSTALL_URL:-https://raw.githubusercontent.com/Laoujin/Scout/main/install.sh}"
  if ! curl -fsSL "$_url" -o "$_tmp"; then
    echo "Error: failed to download $_url" >&2
    rm -f "$_tmp"
    exit 1
  fi
  export SCOUT_INSTALL_REEXEC=1
  export SCOUT_INSTALL_TMPFILE="$_tmp"
  # shellcheck disable=SC2093
  exec bash "$_tmp" "$@" </dev/tty
fi

CONFIG=""
REF="main"
UPSTREAM="Laoujin/Scout"
CLONE_PATH=""
LOCAL_SCOUT=""
ORG=""

for arg in "$@"; do
  case "$arg" in
    --config=*)   CONFIG="${arg#*=}" ;;
    --ref=*)      REF="${arg#*=}" ;;
    --upstream=*) UPSTREAM="${arg#*=}" ;;
    --dir=*)      CLONE_PATH="${arg#*=}" ;;
    --local=*)    LOCAL_SCOUT="${arg#*=}" ;;   # use local checkout instead of fetching from GitHub
    --org=*)      ORG="${arg#*=}" ;;           # fork + create Atlas under this org instead of authed user
    -h|--help)    sed -n '3,20p' "$0" 2>/dev/null || grep '^#' "$0" | head -20; exit 0 ;;
    *) echo "Unknown argument: $arg" >&2; exit 2 ;;
  esac
done

# Ask where Scout should land when not passed via --dir. Default puts it at
# $PWD/Scout directly — no extra scout-install/ wrapper.
if [[ -z "$CLONE_PATH" ]]; then
  default_clone="$PWD/Scout"
  read -rp "Install Scout to [$default_clone]: " CLONE_PATH
  CLONE_PATH="${CLONE_PATH:-$default_clone}"
fi

INSTALL_DIR="$(dirname "$CLONE_PATH")"
SCOUT_NAME_DEFAULT="$(basename "$CLONE_PATH")"

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

mkdir -p "$INSTALL_DIR"
# Place the bind-mounted temp dirs inside $INSTALL_DIR rather than /tmp.
# Docker Desktop on WSL2 can't always see WSL /tmp, but $INSTALL_DIR is
# under $PWD which is always exposed.
AUTH_DIR="$(TMPDIR="$INSTALL_DIR" mktemp -d)"
BUILD_CTX="$(TMPDIR="$INSTALL_DIR" mktemp -d)"
trap 'rm -rf "$AUTH_DIR" "$BUILD_CTX" "${SCOUT_INSTALL_TMPFILE:-}"' EXIT

if [[ -n "$LOCAL_SCOUT" ]]; then
  echo "→ Using local checkout: $LOCAL_SCOUT"
  [[ -f "$LOCAL_SCOUT/scripts/installer.sh" && -f "$LOCAL_SCOUT/scripts/manifest.json" ]] || {
    echo "Error: --local=$LOCAL_SCOUT missing scripts/installer.sh or scripts/manifest.json" >&2
    exit 1
  }
  cp "$LOCAL_SCOUT/scripts/installer.sh" "$BUILD_CTX/installer.sh"
  cp "$LOCAL_SCOUT/scripts/manifest.json" "$BUILD_CTX/manifest.json"
else
  RAW="https://raw.githubusercontent.com/${UPSTREAM}/${REF}"
  echo "→ Fetching installer components from ${UPSTREAM}@${REF}..."
  curl -fsSL "$RAW/scripts/installer.sh"    -o "$BUILD_CTX/installer.sh"
  curl -fsSL "$RAW/scripts/manifest.json"   -o "$BUILD_CTX/manifest.json"
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

echo "→ Running installer..."
docker run --rm -it \
  -v "$INSTALL_DIR:/work" \
  -v "$AUTH_DIR:/root/.config/gh" \
  -v /var/run/docker.sock:/var/run/docker.sock \
  -e SCOUT_CONFIG="$CONFIG" \
  -e SCOUT_UPSTREAM="$UPSTREAM" \
  -e SCOUT_REF="$REF" \
  -e SCOUT_ORG="$ORG" \
  -e SCOUT_HOST_WORK="$INSTALL_DIR" \
  -e SCOUT_NAME_DEFAULT="$SCOUT_NAME_DEFAULT" \
  -e HOST_UID="$(id -u)" \
  -e HOST_GID="$(id -g)" \
  -e GH_TOKEN \
  -e GITHUB_TOKEN \
  scout-installer

# Post-install next steps — installer wrote SCOUT_OWNER/NAME + ATLAS_OWNER/NAME to /work/.next
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

  Open a research issue: https://github.com/$SCOUT_OWNER/$SCOUT_NAME/issues/new?template=research.yml
  Atlas (first build ~1 min): https://$ATLAS_OWNER.github.io/$ATLAS_NAME/
────────────────────────────────────────────────────────────────────────

EOF

  # Optional: install the /research Claude Code slash command, baked to
  # this user's Scout repo so /research targets the right issue tracker.
  read -rp "Install /research slash command to ~/.claude/commands/? [y/N]: " _ans
  if [[ "${_ans,,}" =~ ^(y|yes)$ ]]; then
    _target="$HOME/.claude/commands/research.md"
    mkdir -p "$(dirname "$_target")"
    _tpl="$BUILD_CTX/research.md.template"
    if [[ -n "$LOCAL_SCOUT" ]]; then
      [[ -f "$LOCAL_SCOUT/commands/research.md" ]] \
        && cp "$LOCAL_SCOUT/commands/research.md" "$_tpl" \
        || { echo "  skipped: $LOCAL_SCOUT/commands/research.md missing" >&2; _tpl=""; }
    else
      curl -fsSL "https://raw.githubusercontent.com/${UPSTREAM}/${REF}/commands/research.md" -o "$_tpl" \
        || { echo "  skipped: could not fetch template" >&2; _tpl=""; }
    fi
    if [[ -n "$_tpl" ]]; then
      _atlas_url="https://${ATLAS_OWNER}.github.io/${ATLAS_NAME}/"
      sed -e "s|{{SCOUT_REPO}}|$SCOUT_OWNER/$SCOUT_NAME|g" \
          -e "s|{{ATLAS_URL}}|$_atlas_url|g" \
          "$_tpl" > "$_target"
      echo "  installed: $_target → $SCOUT_OWNER/$SCOUT_NAME"
    fi
  fi

  rm -f "$INSTALL_DIR/.next"
fi
