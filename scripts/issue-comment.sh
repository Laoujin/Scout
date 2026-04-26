#!/usr/bin/env bash
# Post a sharpen-result comment to the triggering Issue.
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

# If the sharpener emitted a scout-subtopics fenced block, extract it for
# rendering as a markdown section. Absence ⇒ narrow mode (today's UX).
SUB_TOPICS_BLOCK="$(printf '%s' "$SHARPENED_TOPIC" | awk '
  /^```scout-subtopics[[:space:]]*$/ { in_block=1; next }
  /^```[[:space:]]*$/ && in_block { exit }
  in_block { print }
')"

# Strip the scout-subtopics fenced block (and trailing blanks) from the
# paragraph that goes into the scout-topic fenced block. This prevents
# nested fences from breaking research-from-issue.sh's bare-fence awk
# extractor.
TOPIC_ONLY="$(printf '%s' "$SHARPENED_TOPIC" | awk '
  /^```scout-subtopics[[:space:]]*$/ { in_block=1; next }
  /^```[[:space:]]*$/ && in_block { in_block=0; next }
  !in_block { print }
' | sed -e :a -e '/^[[:space:]]*$/{$d;N;ba' -e '}')"

# Blockquote each line of the topic for the human-readable section.
quoted="$(printf '%s\n' "$TOPIC_ONLY" | sed 's/^/> /')"

if [ -n "$SUB_TOPICS_BLOCK" ]; then
  body="$(cat <<EOF
### ${COMMENT_HEADER}

${quoted}

<!-- scout-topic-start -->
\`\`\`scout-topic
${TOPIC_ONLY}
\`\`\`
<!-- scout-topic-end -->

This topic has several independent angles. The list below is informational for now — Start research will run a single expedition over the whole topic. (Per-angle decomposition is being wired in a follow-up.)

### Sub-topics

${SUB_TOPICS_BLOCK}

### Go

- [ ] **Start research** — tick this to publish to Atlas (depth: \`${DEPTH_LABEL}\`, format: \`${FORMAT}\`).

Not what you wanted? Reply with feedback (e.g. "merge angles 2 and 3", "drop the routing one") and I'll propose a new sharpened version.
EOF
)"
else
  body="$(cat <<EOF
### ${COMMENT_HEADER}

${quoted}

<!-- scout-topic-start -->
\`\`\`scout-topic
${TOPIC_ONLY}
\`\`\`
<!-- scout-topic-end -->

- [ ] **Start research** — tick this to publish to Atlas (depth: \`${DEPTH_LABEL}\`, format: \`${FORMAT}\`).

Not what you wanted? Reply with feedback (e.g. "focus on open-source", "shorter, decision-only") and I'll propose a new sharpened version.
EOF
)"
fi

gh issue comment "$ISSUE_NUMBER" --repo "$GH_REPO" --body "$body"
