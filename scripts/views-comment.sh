#!/usr/bin/env bash
# Render and post the candidacy comment from <RESEARCH_DIR>/.view-candidacy.json.
#
# Required env: ISSUE_NUMBER, GH_TOKEN, GH_REPO, RESEARCH_DIR.
# Required file: $RESEARCH_DIR/.view-candidacy.json (exits 0 silently if missing).

set -euo pipefail

: "${ISSUE_NUMBER:?ISSUE_NUMBER is required}"
: "${GH_TOKEN:?GH_TOKEN is required}"
: "${GH_REPO:?GH_REPO is required}"
: "${RESEARCH_DIR:?RESEARCH_DIR is required}"

CANDIDACY="$RESEARCH_DIR/.view-candidacy.json"
if [ ! -f "$CANDIDACY" ]; then
  echo "[views-comment] no candidacy file at $CANDIDACY; skipping" >&2
  exit 0
fi

# Strip should_offer_view + title from each item before embedding the JSON in the
# comment; only what dispatch needs is preserved.
EMBEDDED_JSON="$(jq -c '{items: (.items | map({row,slug,path,view_name,title_suffix,vibe_hint}))}' "$CANDIDACY")"

# Build the display rows.
build_row() {
  local row="$1" slug="$2" title="$3" should_offer="$4" view_name="$5"
  local checkbox label hint=""
  if [ "$row" = "parent" ]; then
    checkbox="[x]"
    label="**${title}**"
  else
    label="$slug"
    if [ "$should_offer" = "true" ]; then checkbox="[x]"; else checkbox="[ ]"; fi
  fi
  if [ "$should_offer" = "true" ] && [ -n "$view_name" ] && [ "$view_name" != "null" ]; then
    hint=" — register: ${view_name}"
  fi
  printf -- '- %s %s%s <!-- slug:%s -->\n' "$checkbox" "$label" "$hint" "$slug"
}

ROWS=""
N=$(jq '.items | length' "$CANDIDACY")
i=0
while [ "$i" -lt "$N" ]; do
  row=$(jq -r ".items[$i].row" "$CANDIDACY")
  slug=$(jq -r ".items[$i].slug" "$CANDIDACY")
  title=$(jq -r ".items[$i].title // \"\"" "$CANDIDACY")
  should_offer=$(jq -r ".items[$i].should_offer_view" "$CANDIDACY")
  view_name=$(jq -r ".items[$i].view_name // \"\"" "$CANDIDACY")
  ROWS+="$(build_row "$row" "$slug" "$title" "$should_offer" "$view_name")"$'\n'
  i=$((i + 1))
done
ROWS="${ROWS%$'\n'}"

# Singular vs plural prompt.
if [ "$N" -eq 1 ]; then
  TICK_PROMPT="Tick the box if you want this enriched, then check the final box to start."
else
  TICK_PROMPT="Tick the boxes you want enriched, then check the final box to start."
fi

BODY="$(cat <<EOF
### HTML view candidates

Want a nice HTML alternative view over the boring MD?

${ROWS}

${TICK_PROMPT}

- [ ] **Start creating the HTML pages**

<!-- scout-view-targets-start -->
\`\`\`scout-view-targets
${EMBEDDED_JSON}
\`\`\`
<!-- scout-view-targets-end -->
EOF
)"

gh issue comment "$ISSUE_NUMBER" --repo "$GH_REPO" --body "$BODY
"
