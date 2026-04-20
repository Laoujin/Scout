#!/bin/bash
# Runs as root on container start. Fixes volume-mount ownership (named
# volumes start root-owned) then drops to the `runner` user.
set -euo pipefail

for d in /home/runner/.claude /home/runner/.ssh /home/runner/actions-runner; do
  mkdir -p "$d"
  chown -R runner:runner "$d"
done

exec runuser -u runner -- /home/runner/run-init.sh
