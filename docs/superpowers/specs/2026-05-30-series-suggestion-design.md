# Series suggestion in the sharpen flow — design

**Date:** 2026-05-30
**Repo:** Scout (changes land in the Scout repo; Atlas only receives the `series.yml` edit at publish time)

## Problem

Atlas groups related research into *series* via a hand-maintained manifest, `atlas/_data/series.yml`
(e.g. `michelin-weekends`, grouped by country). Scout has **zero** awareness of series today: when a
new research entry would belong to an existing series, a human has to remember to edit `series.yml`
by hand. That step gets forgotten, so series drift out of date.

We want the flow to **suggest** adding a new entry to an existing series, surfaced where the user is
already making go/no-go decisions: the sharpened proposal. The suggestion is a checkbox, **ticked by
default**. If it is still ticked when the user hits **Start research**, the publish step adds the
entry to `series.yml` as part of the same commit.

Scope is *existing* series only — Scout never invents a new series (that stays a human decision).

## Key constraint: slug isn't final at sharpen time

`run.sh` renames the research directory from the artifact's frontmatter `title:` *after* the artifact
is written (the "Title-based slug rename" block). Series entries in `series.yml` are keyed by the
directory name `<date>-<slug>`. Therefore the sharpen-time checkbox can only carry **intent** (which
series, which group) — the actual YAML line, which needs the final slug, must be written at **publish
time**.

## Flow

Rides the existing `scout-subtopics` pattern end-to-end.

```
sharpen-on-open / resharpen-on-comment        research (Start research ticked)
┌───────────────────────────────┐             ┌──────────────────────────────────┐
│ fetch Atlas _data/series.yml   │             │ research-from-issue.sh            │
│ sharpen.sh → sharpen.md judges │             │   parse_series → SERIES_SLUG,     │
│ emits scout-series block       │             │                  SERIES_GROUP     │
│ issue-comment.sh renders       │  ── Start ─▶ │ run.sh (writes + renames slug)    │
│   ### Series  - [x] …          │   research   │ add-to-series.sh edits series.yml │
└───────────────────────────────┘             │ publish.sh commits both           │
                                               └──────────────────────────────────┘
```

### 1. Sharpen time

**`sharpen.sh`** gains an optional `SERIES_MANIFEST` input. The sharpen jobs fetch the current
manifest from the public Atlas repo (raw URL / `gh api`; best-effort — on failure the variable is
empty and no series block is emitted). When non-empty it is appended to the prompt as an
`Existing series:` block.

**`sharpen.md`** gains a rule + output section:
- Given `Existing series:` (a list of `slug — title — blurb` plus group labels per series), judge
  whether the sharpened topic **confidently** belongs to exactly one existing series. Conservative:
  no confident match → emit nothing.
- At most one series (a topic belongs to ≤1 series — multi-series is out of scope, YAGNI).
- If matched, append a fenced `scout-series` block, ticked by default:

  ````
  ```scout-series
  - [x] **<series-slug>** › <group-label> — <one-line rationale>
  ```
  ````
- `› <group-label>` is **optional** — present only for grouped series (e.g. `michelin-weekends`),
  omitted for flat series (e.g. `sessions-and-workshops`). The skill picks the group from the
  manifest's group labels.

### 2. Comment rendering — `issue-comment.sh`

Extract the `scout-series` block (same awk extractor shape as `scout-subtopics`). When present,
render a `### Series` markdown section above `### Go` / the Start checkbox:

```
### Series

- [x] **michelin-weekends** › Germany — Munich weekend anchored on a Michelin dinner
```

The block is stripped from the `scout-topic` fenced block (same treatment as `scout-subtopics`) so
nested fences don't break the bare-fence extractor in `research-from-issue.sh`.

### 3. Re-sharpen preservation — `resharpen-on-comment` + `sharpen.sh`

Mirror `PREVIOUS_SUB_TOPICS`: the resharpen job extracts the prior `### Series` section from the last
bot comment and passes it to `sharpen.sh` as `PREVIOUS_SERIES`. The skill preserves/adjusts it as a
delta (user can untick, or feedback like "not a series" drops the block).

### 4. Parse at research time — `lib-issue-parse.sh::parse_series`

New function, same leniency as `parse_sub_topics`:
- Reads the `### Series` section from the bot comment body.
- Matches `- [x] **<slug>** [› <group>] [— rationale]`. Em-dash/hyphen separator and `›`/`/`
  group separator both tolerated; leading whitespace and `-`/`*` bullets tolerated.
- Only a **ticked** (`[x]`/`[X]`) entry counts. Unticked → no series.
- Exports `SERIES_SLUG` and `SERIES_GROUP` (empty when absent/unticked).

`research-from-issue.sh` calls `parse_series "$BOT_COMMENT_BODY"` alongside `parse_start_choice` /
`parse_sub_topics`, and exports `SERIES_SLUG` / `SERIES_GROUP` into the run env. Only the single-pass
`run.sh` path acts on them in v1 (see Out of scope); exporting them on the decompose path too is
harmless and leaves the wiring ready for the follow-up.

### 5. YAML edit — `scripts/add-to-series.sh`

New script. Args / env: Atlas checkout dir, entry slug (`<date>-<final-slug>`), `SERIES_SLUG`,
`SERIES_GROUP`. Behaviour:
- **Comment-preserving text insert** via awk: locate the `- slug: <SERIES_SLUG>` block; within it
  locate the target group (`label: <SERIES_GROUP>`) or the flat `entries:` list; append
  `        - <entry-slug>` as the last line of that group's `entries:`.
- **Idempotent**: if `<entry-slug>` already appears anywhere in the file, no-op.
- **Fail-soft**: series slug not found, group label not found, or file missing → write a line to
  `SOFT_FAIL_LOG` and exit 0. Never blocks publish. Never creates a new series or group.

Called from `run.sh` after the title-based slug rename and before `publish.sh`, guarded on
`SERIES_SLUG` being non-empty and not a decompose child re-entry. The edit lands in the Atlas working
tree, so `publish.sh`'s existing `git add .` sweeps it into the same research commit.

## Out of scope

- Creating new series (human-only).
- A single entry in multiple series.
- `workflow_dispatch` runs (no bot comment / sharpen step → no series suggestion).
- Back-filling series for already-published entries.
- **Decompose / expedition runs** (`run-decompose.sh`). Its parent folder is slugged up-front (no
  title-rename) and published via a per-child + final-sweep machine — a different insertion point.
  Series so far are all single-pass (`standard` depth), so v1 ships single-pass only. `parse_series`
  still exports the vars on this path, so the follow-up is just an `add-to-series.sh` call in the
  parent's publish step.

## Testing (TDD)

| Test file                              | Asserts                                                              |
|----------------------------------------|---------------------------------------------------------------------|
| `test_lib_issue_parse_series.sh`       | `parse_series`: ticked w/ group, ticked flat, unticked, absent, lenient separators |
| `test_add_to_series.sh`                | insert under group; insert flat; idempotent no-op; missing series soft-skips; comment header preserved |
| `test_issue_comment_series_render.sh`  | `### Series` section rendered when block present; absent otherwise; block stripped from `scout-topic` |
| `test_sharpen_snapshots.sh` (extend)   | `Existing series:` injected when `SERIES_MANIFEST` set; omitted when empty |

## Open risks

- **Fetch auth**: assumes Atlas is public (it is — served via GitHub Pages). If Atlas were private,
  the sharpen job's repo-scoped `GITHUB_TOKEN` couldn't read it; suggestion silently degrades to off.
  Acceptable given fail-soft design.
- **awk fragility**: the insert relies on `series.yml`'s 2-space-per-level indentation. Tests pin the
  current format; a structural reformat of `series.yml` would need the awk updated.
