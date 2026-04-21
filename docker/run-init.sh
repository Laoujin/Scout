#!/bin/bash
# Runs as the `runner` user. Populates the actions-runner dir on first boot,
# registers with GitHub if needed, generates an Atlas deploy key if needed,
# then execs the runner's polling loop.
set -euo pipefail

RUNNER_DIR=/home/runner/actions-runner
RUNNER_BASE=/home/runner/runner-base
SSH_DIR=/home/runner/.ssh

if [ ! -x "$RUNNER_DIR/run.sh" ]; then
  cp -a "$RUNNER_BASE/." "$RUNNER_DIR/"
fi

cd "$RUNNER_DIR"

if [ ! -f .runner ]; then
  : "${RUNNER_URL:?RUNNER_URL required}"
  : "${RUNNER_TOKEN:?RUNNER_TOKEN required (from GitHub -> Scout -> Settings -> Actions -> Runners -> New)}"
  ./config.sh \
    --url "$RUNNER_URL" \
    --token "$RUNNER_TOKEN" \
    --labels "${RUNNER_LABELS:-scout}" \
    --name "${RUNNER_NAME:-nas-scout}" \
    --unattended \
    --replace
fi

if [ ! -f "$SSH_DIR/atlas_deploy" ]; then
  chmod 700 "$SSH_DIR"
  ssh-keygen -t ed25519 -f "$SSH_DIR/atlas_deploy" -C "scout-atlas" -N "" >/dev/null
  cat > "$SSH_DIR/config" <<'CFG'
Host github.com-atlas
  HostName github.com
  User git
  IdentityFile ~/.ssh/atlas_deploy
  IdentitiesOnly yes
  StrictHostKeyChecking accept-new
CFG
  chmod 600 "$SSH_DIR/config" "$SSH_DIR/atlas_deploy"
  chmod 644 "$SSH_DIR/atlas_deploy.pub"

  # Derive the "Add deploy key" URL from ATLAS_REPO for clarity in the log message.
  # ATLAS_REPO looks like: git@github.com-atlas:<owner>/<repo>.git
  atlas_slug="${ATLAS_REPO#*:}"; atlas_slug="${atlas_slug%.git}"
  echo
  echo "===================================================================="
  echo " First boot: Atlas deploy key generated."
  echo " Add the PUBLIC key below at:"
  echo "   https://github.com/${atlas_slug}/settings/keys/new"
  echo "   title:  scout-nas"
  echo "   Allow write access:  YES"
  echo "===================================================================="
  cat "$SSH_DIR/atlas_deploy.pub"
  echo "===================================================================="
  echo
fi

exec ./run.sh
