#!/usr/bin/env bash
# Post a tighten-result comment to the triggering Issue.
# Comment shape: human-readable blockquote + machine-parseable scout-topic fenced
# block + a [ ] Start research checkbox the user ticks to publish to Atlas.
#
# Required env: ISSUE_NUMBER, SHARPENED_TOPIC, DEPTH, FORMAT, GH_TOKEN, GH_REPO.
# Optional env: COMMENT_HEADER (defaults to "Sharpened proposal").

set -euo pipefail

: "${ISSUE_NUMBER:?ISSUE_NUMBER is required}"
: "${SHARPENED_TOPIC:?SHARPENED_TOPIC is required}"
: "${DEPTH:=standard}"
: "${FORMAT:=auto}"
: "${DEPTH_LABEL:=$DEPTH}"
: "${GH_TOKEN:?GH_TOKEN is required}"
: "${GH_REPO:?GH_REPO is required (e.g. owner/repo)}"
: "${COMMENT_HEADER:=Sharpened proposal}"

# Blockquote each line of the sharpened topic for the human-readable section.
quoted="$(printf '%s\n' "$SHARPENED_TOPIC" | sed 's/^/> /')"

body="$(cat <<EOF
### ${COMMENT_HEADER}

${quoted}

<!-- scout-topic-start -->
\`\`\`scout-topic
${SHARPENED_TOPIC}
\`\`\`
<!-- scout-topic-end -->

- [ ] **Start research** — tick this to publish to Atlas (depth: \`${DEPTH_LABEL}\`, format: \`${FORMAT}\`).

Not what you wanted? Reply with feedback (e.g. "focus on open-source", "shorter, decision-only") and I'll propose a new sharpened version.
EOF
)"

gh issue comment "$ISSUE_NUMBER" --repo "$GH_REPO" --body "$body"
