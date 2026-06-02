#!/bin/bash
# Runs as root on container start. Fixes volume-mount ownership (named
# volumes start root-owned) then drops to the `runner` user.
set -euo pipefail

for d in /home/runner/.claude /home/runner/.ssh /home/runner/actions-runner; do
  mkdir -p "$d"
  # .ssh is read-only and already owned, so its chown is expected to fail — don't let set -e abort on it.
  chown -R runner:runner "$d" 2>/dev/null || true
done

exec runuser -u runner -- /home/runner/run-init.sh
