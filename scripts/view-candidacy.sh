#!/usr/bin/env bash
# Run the LLM judgement step over a research dir. Writes <RESEARCH_DIR>/.view-candidacy.json.
#
# Required env: RESEARCH_DIR
#               SCOUT_NO_VIEW_CANDIDACY=1 to skip entirely (test hook)
#               SCOUT_DIR (defaults to script's parent)

set -euo pipefail

: "${RESEARCH_DIR:?RESEARCH_DIR is required}"

if [ "${SCOUT_NO_VIEW_CANDIDACY:-0}" = "1" ]; then
  echo "[view-candidacy] SCOUT_NO_VIEW_CANDIDACY=1, skipping" >&2
  exit 0
fi

SCOUT_DIR="${SCOUT_DIR:-$(cd "$(dirname "$0")/.." && pwd)}"

# Decide RUN_KIND. Decompose runs have a manifest.json beside the parent index.
RUN_KIND="single"
PARENT_PATH=""
MANIFEST="$RESEARCH_DIR/manifest.json"
if [ -f "$MANIFEST" ]; then
  RUN_KIND="decompose"
  PARENT_PATH="$(realpath --relative-to="$(realpath "$RESEARCH_DIR/../..")" "$RESEARCH_DIR" 2>/dev/null \
                 || basename "$(dirname "$RESEARCH_DIR")")/$(basename "$RESEARCH_DIR")"
fi

# Frontmatter helper.
_fm() {
  local file="$1" field="$2"
  awk -v f="$field" '
    /^---[[:space:]]*$/ {
      if (++fm_count == 2) exit
      in_fm = 1
      next
    }
    in_fm && $0 ~ "^"f":" { sub("^"f":[[:space:]]*", ""); print; exit }
  ' "$file" 2>/dev/null
}

# Pick the canonical artifact for a directory.
_artifact() {
  local dir="$1"
  if [ -f "$dir/index.md" ] && [ "$(_fm "$dir/index.md" status)" != "failed" ]; then
    echo "$dir/index.md"
  elif [ -f "$dir/index.html" ]; then
    echo "$dir/index.html"
  fi
}

# Build PAGES JSON array.
PAGES_JSON='['
first=1
add_page() {
  local row="$1" dir="$2" path_rel="$3"
  local file
  file="$(_artifact "$dir")"
  [ -n "$file" ] || return 0
  local title summary depth citations format
  title="$(_fm "$file" title)"
  summary="$(_fm "$file" summary)"
  depth="$(_fm "$file" depth)"
  citations="$(_fm "$file" citations)"
  citations="${citations%%[^0-9]*}"
  [ -z "$citations" ] && citations=0
  case "$file" in *.html) format=html ;; *) format=md ;; esac
  local slug
  slug="$(basename "$dir")"
  [ "$first" -eq 1 ] && first=0 || PAGES_JSON+=","
  PAGES_JSON+="$(jq -n \
    --arg row "$row" --arg slug "$slug" --arg path "$path_rel" \
    --arg title "$title" --arg summary "$summary" --arg depth "$depth" \
    --argjson citations "${citations:-0}" --arg format "$format" \
    '{row:$row,slug:$slug,path:$path,title:$title,summary:$summary,depth:$depth,citations:$citations,format:$format}')"
}

if [ "$RUN_KIND" = "decompose" ]; then
  # Parent first, then children from manifest order.
  parent_rel="research/$(basename "$RESEARCH_DIR")"
  add_page "parent" "$RESEARCH_DIR" "$parent_rel"
  while IFS= read -r child_slug; do
    [ -n "$child_slug" ] || continue
    add_page "leaf" "$RESEARCH_DIR/$child_slug" "$parent_rel/$child_slug"
  done < <(jq -r '.[].slug' "$MANIFEST")
else
  parent_rel="research/$(basename "$RESEARCH_DIR")"
  add_page "parent" "$RESEARCH_DIR" "$parent_rel"
fi
PAGES_JSON+=']'

# Compose prompt.
SKILL_CONTENT="$(cat "$SCOUT_DIR/skills/scout/view-candidacy.md")"
PROMPT="$(cat <<EOF
RUN_KIND: ${RUN_KIND}
PARENT_PATH: ${PARENT_PATH}
PAGES: ${PAGES_JSON}

Use the view-candidacy skill. Output strict JSON.
EOF
)"

OUT="$RESEARCH_DIR/.view-candidacy.json"
RESULT_JSON="$RESEARCH_DIR/.view-candidacy-result.json"

claude --dangerously-skip-permissions \
       --print \
       --output-format json \
       --append-system-prompt "$SKILL_CONTENT" \
       "$PROMPT" > "$RESULT_JSON" || {
  echo "[view-candidacy] claude invocation failed; writing empty candidacy" >&2
  echo '{"items":[]}' > "$OUT"
  exit 0
}

# Extract the JSON content from the result wrapper. claude with --output-format json
# returns {"result": "<model output>", ...}. Strip whitespace + leading code fences if any.
RAW="$(jq -r '.result // ""' "$RESULT_JSON")"
# Strip optional ```json ... ``` fences.
CLEANED="$(printf '%s' "$RAW" | sed -e 's/^```json[[:space:]]*//; s/^```[[:space:]]*//; s/[[:space:]]*```$//')"
# Validate it parses; fallback to empty items on failure.
if printf '%s' "$CLEANED" | jq -e '.items' >/dev/null 2>&1; then
  printf '%s\n' "$CLEANED" > "$OUT"
else
  echo "[view-candidacy] model output not valid JSON; writing empty candidacy" >&2
  echo '{"items":[]}' > "$OUT"
fi

# Apply parent-override rule: row=parent always has should_offer_view=true.
TMP="$(mktemp)"
jq '.items |= map(if .row == "parent" then .should_offer_view = true else . end)' "$OUT" > "$TMP"
mv "$TMP" "$OUT"

echo "[view-candidacy] wrote $OUT" >&2
