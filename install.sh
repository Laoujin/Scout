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

# Warm-rust banner — accent #c2410c matches docs/index.html.
if [[ -t 1 ]]; then
  _C=$'\033[38;2;194;65;12m'; _D=$'\033[2m'; _G=$'\033[90m'; _B=$'\033[94m'; _R=$'\033[0m'
else
  _C=''; _D=''; _G=''; _B=''; _R=''
fi
cat <<BANNER

${_C}   ███████   ██████   ██████  ██    ██ ████████${_R}
${_C}   ██       ██       ██    ██ ██    ██    ██   ${_R}
${_C}    ██████  ██       ██    ██ ██    ██    ██   ${_R}
${_C}         ██ ██       ██    ██ ██    ██    ██   ${_R}
${_C}   ███████   ██████   ██████   ██████     ██   ${_R}

   ${_D}Personal research engine — on your own hardware${_R}
   ${_D}Scout researches. Atlas remembers.${_R}

BANNER

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

# Create the identity profile skeleton next to profile.example.yml (idempotent — never overwrites).
# The runner bind-mounts this file read-only into the container.
if [ ! -f "$CLONE_PATH/profile.yml" ]; then
  cat > "$CLONE_PATH/profile.yml" <<'EOF'
# Scout identity profile. See profile.example.yml for fields and examples.
# Until you add fields below, sharpening behaves with no profile context.
EOF
  chmod 644 "$CLONE_PATH/profile.yml"   # umask on some hosts (Synology) defaults to 077 → unreadable inside container
  echo "Created $CLONE_PATH/profile.yml — edit it to set your identity, or leave empty to disable."
fi

# Post-install next steps — installer wrote SCOUT_OWNER/NAME + ATLAS_OWNER/NAME to /work/.next
if [[ -f "$INSTALL_DIR/.next" ]]; then
  # shellcheck disable=SC1091
  source "$INSTALL_DIR/.next"
  cat <<EOF

────────────────────────────────────────────────────────────────────────
  Scout installed. How the pieces fit:

    You open an Issue on $SCOUT_OWNER/$SCOUT_NAME  →  GitHub Actions
    fires the research workflow  →  the workflow runs on a self-hosted
    runner (the Docker container below, on your hardware)  →  it uses
    Claude Code to research the topic and pushes the artifact to
    $ATLAS_OWNER/$ATLAS_NAME  →  GitHub Pages rebuilds Atlas.

  Two things left — you do these on this host:

    1) Start the runner container. It registers with GitHub and polls
       for jobs. Must stay running for Scout to respond to issues.

         ${_G}cd "$INSTALL_DIR/$SCOUT_NAME/docker"${_R}
         ${_G}docker-compose up -d --build${_R}

    2) Authenticate Claude inside the runner. One-time; your login is
       stored on a named volume and survives rebuilds.

         ${_G}docker exec -it scout-runner runuser -u runner -- claude${_R}
         ${_G}# log in, then /exit${_R}

  Open a research issue:
    ${_B}https://github.com/$SCOUT_OWNER/$SCOUT_NAME/issues/new?template=research.yml${_R}
  Your Atlas (first Pages build takes ~1 min):
    ${_B}https://$ATLAS_OWNER.github.io/$ATLAS_NAME/${_R}
────────────────────────────────────────────────────────────────────────

EOF

  # Optional: install the Scout slash commands. /scout-async is copied with the
  # repo slug substituted; /scout is symlinked to the local checkout so it
  # self-locates and auto-updates on `git pull`. ~/.scout/dir records the path.
  read -rp "Install Scout slash commands (/scout, /scout-async) to ~/.claude/commands/? [y/N]: " _ans
  if [[ "${_ans,,}" =~ ^(y|yes)$ ]]; then
    _cmddir="$HOME/.claude/commands"
    mkdir -p "$_cmddir"
    _scout_local="$CLONE_PATH"   # local Scout checkout created by this installer
    _atlas_url="https://${ATLAS_OWNER}.github.io/${ATLAS_NAME}/"

    # /scout-async — copy + substitute (needs the repo slug, can't be a symlink).
    _async_src="$_scout_local/.claude/commands/scout-async.md"
    if [[ -f "$_async_src" ]]; then
      sed -e "s|{{SCOUT_REPO}}|$SCOUT_OWNER/$SCOUT_NAME|g" \
          -e "s|{{ATLAS_URL}}|$_atlas_url|g" \
          "$_async_src" > "$_cmddir/scout-async.md"
      echo "  installed: $_cmddir/scout-async.md → $SCOUT_OWNER/$SCOUT_NAME"
    else
      echo "  skipped scout-async: $_async_src missing" >&2
    fi

    # /scout — symlink (self-locating); record the checkout path.
    mkdir -p "$HOME/.scout"
    printf '%s\n' "$_scout_local" > "$HOME/.scout/dir"
    _inter_src="$_scout_local/.claude/commands/scout.md"
    if [[ -f "$_inter_src" ]]; then
      if ln -sf "$_inter_src" "$_cmddir/scout.md" 2>/dev/null; then
        echo "  linked:    $_cmddir/scout.md → $_inter_src"
      else
        cp "$_inter_src" "$_cmddir/scout.md"   # filesystems without symlinks
        echo "  copied:    $_cmddir/scout.md (symlink unavailable; re-run install after updates)"
      fi
    else
      echo "  skipped scout: $_inter_src missing" >&2
    fi
  fi

  rm -f "$INSTALL_DIR/.next"
fi
