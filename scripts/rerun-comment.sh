#!/usr/bin/env bash
# Post a "re-run failed sub-topics" checkbox comment on the issue when a
# decomposed expedition finished with one or more failed children. Ticking the
# checkbox triggers the `rerun` workflow job, which resumes the expedition and
# re-runs only the failed sub-topics (the successful pages are kept) before
# re-synthesizing. Silent (exit 0) when there is no manifest or nothing failed.
#
# Required env: ISSUE_NUMBER, GH_TOKEN, GH_REPO, PARENT_DIR.

set -euo pipefail

: "${ISSUE_NUMBER:?ISSUE_NUMBER is required}"
: "${GH_TOKEN:?GH_TOKEN is required}"
: "${GH_REPO:?GH_REPO is required}"
: "${PARENT_DIR:?PARENT_DIR is required}"

MANIFEST="$PARENT_DIR/manifest.json"
if [ ! -f "$MANIFEST" ]; then
  echo "[rerun-comment] no manifest at $MANIFEST; skipping" >&2
  exit 0
fi

# A child counts as failed (and thus re-runnable) when its run produced no
# usable artifact: hard failures and timeout skips. error_with_content children
# kept real research, so they are left alone.
FAILED_RE='^(failed|failed_hard_timeout|skipped_soft_timeout)$'
mapfile -t FAILED_SLUGS < <(jq -r --arg re "$FAILED_RE" \
  '.[] | select(.status | test($re)) | .slug' "$MANIFEST")

if [ "${#FAILED_SLUGS[@]}" -eq 0 ]; then
  echo "[rerun-comment] no failed children; skipping" >&2
  exit 0
fi

TOTAL="$(jq 'length' "$MANIFEST")"
EXPEDITION="$(basename "$PARENT_DIR")"

ROWS=""
for slug in "${FAILED_SLUGS[@]}"; do
  reason=""
  cidx="$PARENT_DIR/$slug/index.md"
  if [ -f "$cidx" ]; then
    reason="$(awk -F'failure_reason:' '/^failure_reason:/{print $2; exit}' "$cidx" \
      | sed -E 's/^[[:space:]]*//; s/^"//; s/"[[:space:]]*$//')"
  fi
  ROWS+="$(printf -- '- `%s`%s' "$slug" "${reason:+ — $reason}")"$'\n'
done
ROWS="${ROWS%$'\n'}"

BODY="$(cat <<EOF
### Some sub-topics failed

${#FAILED_SLUGS[@]} of ${TOTAL} sub-topics didn't complete. The successful pages are published and kept — tick below to re-run **only** the failed ones and re-synthesize.

${ROWS}

- [ ] **Re-run failed sub-topics**

<!-- scout-rerun: ${EXPEDITION} -->
EOF
)"

gh issue comment "$ISSUE_NUMBER" --repo "$GH_REPO" --body "$BODY"$'\n'
