# Readable, editable sharpened proposals

## Problem

The sharpened-proposal comment is hard to read and awkward to edit:

1. **Wall of text.** `sharpen.md` forces the brief into "one paragraph. No bullet
   list, no markdown headers" → a dense blob.
2. **Shown twice.** `issue-comment.sh` renders the brief as a `>` blockquote
   (display only, ignored) *and* inside a ` ```scout-topic ` code fence (the
   canonical copy that gets researched).
3. **Ugly edit target.** The fence is the copy you must edit, and GitHub code
   fences don't soft-wrap → one long horizontally-scrolling line.

The goal: one readable, in-place-editable brief (newlines + bullets) that is also
exactly what gets researched.

## Approach

Structure the brief itself, and render it as plain markdown **between the HTML
markers that already wrap the block** — dropping both the blockquote and the
code fence.

The comment already emits:

```
<!-- scout-topic-start -->
```scout-topic
…one long line…
```
<!-- scout-topic-end -->
```

Those `<!-- … -->` markers are invisible when rendered, visible when editing.
Putting the brief as normal markdown between them gives a single source that
renders nicely (bullets/bold/newlines), and the extractor switches from
"between the fences" to "between the markers" — which is *more* robust, since
HTML markers (unlike fences) aren't broken by nested code fences.

## Changes

### 1. `skills/scout/sharpen.md` — structured brief

Replace the "Output: always one paragraph, no bullets" rule with a structured
shape:

```
**<verb-led one-line deliverable>**

- Scope: …
- Compare: <axis>, <axis>, <axis>
- Constraints: <steering hints, verbatim>
- Output: <shape per depth>
```

- Lead line is a **bold** one-liner (the deliverable). It doubles as the slug
  source. No `#` headings (the comment already has its own `###` header).
- 2–5 bullets. Keep it tight — don't bloat.
- All existing rules stay (steering hints verbatim, year anchoring, depth
  scoping, profile use, no invented constraints).
- The `scout-subtopics` and `scout-series` fenced blocks are unchanged.
- Update both worked examples to the new shape.

### 2. `scripts/lib-issue-parse.sh` — shared `extract_topic` with compat shim

Add one function, used by both readers:

```bash
# Extract the sharpened topic from a bot comment body. Prefers the HTML-marker
# region (new + recent format); falls back to a bare ```scout-topic fence for
# pre-marker comments. Unwraps an old fence found *inside* the markers.
# COMPAT: the fence-unwrap branch can be removed once all pre-2026-06 sharpened
# issues are closed.
extract_topic() {
  local body="$1" region
  region="$(printf '%s' "$body" | awk '
    /<!-- scout-topic-start -->/ { in_m=1; next }
    /<!-- scout-topic-end -->/   { in_m=0; exit }
    in_m { print }
  ')"
  if [ -z "$region" ]; then            # pre-marker fallback
    region="$(printf '%s' "$body" | awk '
      /^```scout-topic[[:space:]]*$/ { in_b=1; next }
      /^```[[:space:]]*$/ && in_b { exit }
      in_b { print }
    ')"
  fi
  case "$region" in                    # old fence sitting inside the markers
    '```scout-topic'*)
      region="$(printf '%s' "$region" | awk '
        /^```scout-topic/ { f=1; next }
        /^```/            { f=0 }
        f')" ;;
  esac
  printf '%s' "$region" | _trim_blanks
}
```

### 3. `scripts/issue-comment.sh` — render markdown between markers

- Delete the blockquote (`quoted=` and its use).
- Replace the fenced block between the markers with `${TOPIC_ONLY}` directly:

  ```
  <!-- scout-topic-start -->
  ${TOPIC_ONLY}
  <!-- scout-topic-end -->
  ```

- Both branches (sub-topics present / narrow) get this treatment.
- `TOPIC_ONLY` / `SUB_TOPICS_BLOCK` / `SERIES_BLOCK` extraction is unchanged
  (still keyed on the `scout-subtopics` / `scout-series` fences).

### 4. `scripts/research-from-issue.sh` — use `extract_topic`, slug the title

- Replace the inline scout-topic awk (lines ~19–23) with
  `TOPIC="$(extract_topic "$BOT_COMMENT_BODY")"`.
- Decompose parent slug: instead of `slugify "$TOPIC"` over the whole
  (now multi-line) brief, slug the **first non-empty line**, stripped of `**`
  and a leading `- `:

  ```bash
  TITLE_LINE="$(printf '%s\n' "$TOPIC" \
    | sed -n '/[^[:space:]]/{s/^[[:space:]]*//;s/\*\*//g;s/^[-*][[:space:]]*//;p;q}')"
  PARENT_SLUG="$(slugify "$TITLE_LINE")"
  ```

  (Single-pass already renames the dir from the artifact's frontmatter title,
  so it needs no change.)

### 5. `.github/workflows/research.yml` — use `extract_topic` on re-sharpen

The `resharpen-on-comment` step already `source`s `lib-issue-parse.sh`. Replace
its inline `PREVIOUS_SHARPENED` awk (lines ~120–124) with
`PREVIOUS_SHARPENED="$(extract_topic "$PREVIOUS_BODY")"`. The
`PREVIOUS_SUB_TOPICS` / `PREVIOUS_SERIES` extractors are unchanged.

## Backward compatibility

No migration. `extract_topic` handles every historical format:

| Comment format                         | Handling                        |
|----------------------------------------|---------------------------------|
| New: markdown between markers          | Region used as-is               |
| Recent: fence inside markers           | Fence unwrapped                 |
| Old: bare fence, no markers            | Pre-marker fallback awk         |

To get an existing issue into the new bulleted format, reply to it — the
`resharpen-on-comment` job regenerates the comment in the new shape.

## Testing (TDD)

New / updated shell tests under `tests/`:

- `extract_topic`: new marker-markdown → returns brief unchanged.
- `extract_topic`: fence-inside-markers → unwrapped to inner content.
- `extract_topic`: bare fence, no markers → fallback returns content.
- `issue-comment.sh`: narrow branch → topic rendered between markers, **no**
  blockquote, **no** ` ```scout-topic ` fence; markers present.
- `issue-comment.sh`: sub-topics branch → same, plus `### Sub-topics` section.
- `research-from-issue.sh`: decompose parent slug derives from the title line,
  not the full brief.
- Update `tests/test_skip_sharpen_series_roundtrip.sh` and any test asserting
  the old fence to the marker format.

## Out of scope

- Bulk-migrating existing open issues (rejected: mutates ~25 live comments,
  can't add bullets without re-sharpening which drifts curated content).
- Changing the `scout-subtopics` / `scout-series` block formats.
