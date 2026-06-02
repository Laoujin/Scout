# Interactive `/scout` — research on your subscription

## Problem

After 2026-06-15, headless `claude -p` bills as API even on a Max subscription.
Every Scout research path uses `claude -p` (`run.sh`, `run-decompose.sh`,
`sharpen.sh`), so all automated runs become API-billed — including the NAS
runner. The only execution context that stays on the subscription is an
**interactive** Claude Code session, which exists only when the user is driving
it at their laptop.

Goal: a `/scout` slash command that runs a full research — including
**parallel multi-angle expeditions** — entirely inside the interactive session
(the session itself is the model), reusing Scout's existing research playbooks
and publish plumbing, with **no `claude -p`**.

## Naming

The existing issue→runner command is renamed; the interactive one takes the
short name:

| Command | File | Billing | Use |
|---------|------|---------|-----|
| `/scout` (new) | `.claude/commands/scout.md` | Subscription | At the desk; interactive |
| `/scout-async` (renamed) | `.claude/commands/scout-async.md` | API (headless) | Hands-off, fire-from-phone, durable |

## Distribution — project-scoped, self-locating, auto-renaming

Both commands ship as **project-scoped** files in the Scout repo under
`.claude/commands/` (same mechanism the repo already uses for
`.claude/agents/`). Consequences:

- A `git pull` makes the rename **appear automatically** when working in Scout —
  no installer re-run.
- The installer **symlinks** the global `~/.claude/commands/scout.md` and
  `scout-async.md` to the repo copies (copy fallback where symlinks are
  unavailable), so the from-anywhere global install also auto-updates on pull.
  One source of truth.
- Commands **self-locate** — no `{{SCOUT_DIR}}`/`{{ATLAS_REPO}}` substitution.
  `local-setup.sh` resolves `SCOUT_DIR` (config `~/.scout/dir` if present, else
  walk up from its own path / cwd to the repo containing `skills/scout/SKILL.md`)
  and `ATLAS_REPO` (env → `$SCOUT_DIR/docker/.env` → error with a clear "set
  ATLAS_REPO" message), and prints both for the session to use.

`scout-async.md` keeps its `{{SCOUT_REPO}}`/`{{ATLAS_URL}}` substitution (it only
needs `gh` + repo slug), installed the same way it is today.

## Architecture

The interactive command is a prompt that makes the session the orchestrator,
reusing every existing Scout asset and adding only a thin setup helper:

| Asset | Role | Reuse |
|-------|------|-------|
| `skills/scout/sharpen.md` | sharpen + decompose into sub-topics | followed in-chat |
| `skills/scout/SKILL.md` | research playbook → writes a page | child subagents follow it |
| `skills/scout/synthesis.md` | parent expedition overview | followed by the session |
| `.claude/agents/scout-illustrator.md` | cover SVG | dispatched as-is |
| `scripts/slug.sh` | slugify | sourced |
| `scripts/publish.sh` | commit + push to Atlas | called as-is |
| Atlas `expedition`/`research` layouts (compass) | render pages + `children:` grid | small cost-badge edit |
| `scripts/local-setup.sh` | **new** — resolve dirs, clone Atlas, make dirs | created |

`run.sh` and `run-decompose.sh` are **not touched** — the interactive path runs
parallel to them, not as a refactor.

## Flow

`.claude/commands/scout.md` instructs the session to:

1. **Topic + options.** Use `$ARGUMENTS` as topic or ask in chat. Call
   `AskUserQuestion` once for **Depth** (`recon`/`survey`/`expedition`) and
   **Format** (`auto`/`md`/`html`). Format flows into the research prompt exactly
   as `run.sh` passes it (`format=md|html|auto`).

2. **Sharpen + decompose, in chat.** Follow `sharpen.md` to produce the
   structured brief and — for a multi-angled `expedition` — a `scout-subtopics`
   list. Show it; the user edits/approves in chat (replaces the issue-comment
   round-trip). The approved sub-topic set (title + depth each) selects mode:
   - **sub-topics present & kept → expedition mode** (steps 4–6)
   - **none → single-pass mode** (step 4')

3. **Setup + start timing.** `bash scripts/local-setup.sh "<brief-title>"`
   (passing `SUB_TOPICS_TSV` for expeditions). It resolves `SCOUT_DIR`/
   `ATLAS_REPO`, clones Atlas fresh to `atlas-checkout/`, computes a unique
   `<DATE>-<slug>`, creates `PARENT_DIR` (+ each `PARENT_DIR/<child-slug>/`), and
   prints `SCOUT_DIR=`, `DATE=`, `PARENT_DIR=`, `START_TS=` (a `date +%s` taken
   now, *after* the interactive sharpen, so interactions are excluded from
   `duration_sec`), and one `CHILD=<slug>\t<dir>` line per sub-topic.

4. **Expedition — parallel children.** Dispatch one subagent **per sub-topic in
   a single batch** (concurrent, subscription-billed). Each subagent's brief: the
   `SKILL.md` procedure, its `SUB_TOPIC` title, `DEPTH`, `FORMAT`, and its
   `RESEARCH_DIR=<child_dir>`; it researches and writes
   `<child_dir>/index.{md,html}` with full `SKILL.md` frontmatter, and returns
   its path + one-line summary + a child `start`/`end` timestamp. Children are
   single-pass (a `deep` child is one deep page; subagents cannot nest dispatch).

   **4'. Single-pass mode.** No children: the session researches per `SKILL.md`
   and writes `PARENT_DIR/index.{md,html}`. Then cover (5a) + publish (6).

5. **Cover + synthesize (expedition).** Follow `synthesis.md`:
   a. Dispatch `scout-illustrator` (`subagent_type="scout-illustrator"`) with
      `TOPIC`, the final `TAGS`, `RESEARCH_DIR=PARENT_DIR`. Record `wrote
      cover.svg` vs `skipped:`. **(Cover is required per your decision — always
      dispatch it.)**
   b. Write `PARENT_DIR/manifest.json` — the array of
      `{slug,title,depth,status,start,end}` per child (parity with async; gives
      per-child timing).
   c. Read each child's frontmatter (`summary`, `citations`,
      `reading_time_min`), write `PARENT_DIR/index.md` with `layout: expedition`,
      the `children:` frontmatter list, `cover: cover.svg` (if written),
      `duration_sec` (now − `START_TS`), `cost_usd: "sub"`, and 200–600 words of
      cross-cutting synthesis prose with inline citations. The session computes
      `citations`/`reading_time_min` per child (frontmatter, else count
      `citations*.jsonl`). If <2 children succeeded, `synthesis: false` per
      `synthesis.md`.

   Single-pass mode writes the same `duration_sec` + `cost_usd: "sub"` into the
   single artifact's frontmatter.

6. **Publish.** `bash scripts/publish.sh` once, pushing the whole `PARENT_DIR`
   (parent + children + manifest + cover) to Atlas `main`. Print the Atlas URL.

## Frontmatter additions (local runs)

- `duration_sec`: integer, wall-clock of research+synthesis only (excludes the
  interactive sharpen — timed from `START_TS`). Real and accurate.
- `cost_usd: "sub"`: sentinel string. Subscription runs have no per-token dollar
  charge, and interactive `Agent` subagents don't expose token usage, so a real
  figure is unavailable. The compass layouts render the sentinel as
  "on subscription" (below).

## compass theme change (separate submodule repo)

`Atlas/compass` is a git submodule. In both `_layouts/research.html` (≈line 165)
and `_layouts/expedition.html` (≈line 113), replace:
```liquid
{% if page.cost_usd %}<div class="pcell"><div class="lbl">Cost</div><div class="val">${{ page.cost_usd }}</div></div>{% endif %}
```
with:
```liquid
{% if page.cost_usd == "sub" %}<div class="pcell"><div class="lbl">Cost</div><div class="val">on subscription</div></div>
{% elsif page.cost_usd %}<div class="pcell"><div class="lbl">Cost</div><div class="val">${{ page.cost_usd }}</div></div>{% endif %}
```
Commit to `compass`, then bump the submodule pointer in `Atlas`.

## Error handling

Interactive, so no async robustness machinery. If a child subagent returns
`blocked`/partial or writes nothing, the session surfaces it in chat and the
user decides: re-dispatch that one subagent, drop the angle, or proceed. **No
failure-placeholder pages** are written (unlike `run-decompose.sh`). The child's
`manifest.json` status reflects the final state (`success`/`failed`/dropped).
Synthesis proceeds over whatever succeeded; with <2 successes it says so in the
parent prose (mirrors `synthesis.md`'s gap-honesty rule).

## Components

### `.claude/commands/scout-async.md` (renamed from `commands/scout.md`)
Today's `commands/scout.md` content **minus the local Format edit** (revert it —
the issue path forces `FORMAT=auto`, guarded by `test_format_removed.sh`).
`description:` → `Open a Scout research Issue (async runner).` Keeps
`{{SCOUT_REPO}}`/`{{ATLAS_URL}}` substitution. (Today's file is at
`commands/`; it moves under `.claude/commands/` so both commands live together
and are project-scoped.)

### `.claude/commands/scout.md` (new, interactive)
```yaml
---
description: Run a Scout research now on your subscription (no API).
argument-hint: "[topic]"
allowed-tools: AskUserQuestion, Agent, Bash, Read, Write, WebSearch, WebFetch
---
```
Body: the Flow above as step-by-step instructions. References skill files under
the `SCOUT_DIR` that `local-setup.sh` prints, so the session reads live
playbooks regardless of cwd.

### `scripts/local-setup.sh` (new, ~35 lines)
```
Args:  $1 = brief title (slug source)
Env:   SUB_TOPICS_TSV (optional; "title<TAB>depth" per line), ATLAS_REPO (optional override), DATE (optional)
Resolve: SCOUT_DIR  = ~/.scout/dir if present, else walk up from $0/cwd to the dir containing skills/scout/SKILL.md
         ATLAS_REPO = $ATLAS_REPO, else grep from $SCOUT_DIR/docker/.env, else error
Do:    cd "$SCOUT_DIR"; rm -rf atlas-checkout; git clone --depth=1 --filter=blob:none "$ATLAS_REPO" atlas-checkout
       source slug.sh; SLUG = unique under atlas-checkout/research/<DATE>-<slug> (append -2,-3 on collision)
       mkdir PARENT_DIR; for each SUB_TOPICS_TSV line: mkdir PARENT_DIR/<child-slug>
Print: SCOUT_DIR=…  DATE=…  PARENT_DIR=…  START_TS=<date +%s>  and one CHILD=<slug>\t<dir> per sub-topic
```
Reuses `slug.sh` (no slug logic duplicated); clone+slug mirror `run.sh`.

### `scripts/installer.sh` + `install.sh` (command install)
Install **both** commands. For the interactive one, **symlink**
`~/.claude/commands/scout.md` → `$SCOUT_DIR/.claude/commands/scout.md` (copy
fallback), and likewise `scout-async.md`; write `~/.scout/dir` = `$SCOUT_DIR`.
`scout-async.md` still gets `{{SCOUT_REPO}}`/`{{ATLAS_URL}}` substitution; since
a symlink can't be substituted in place, the async command is **copied** (not
symlinked) with substitution, while the self-locating interactive command is
symlinked. (Net: async = copy+substitute as today; interactive = symlink.)

### compass + Atlas
The cost-badge edit above (compass commit + Atlas submodule bump).

### Docs
`README.md` + `docs/OPERATE.md`: `/scout` (interactive, subscription) vs
`/scout-async` (runner, API), the June-15 rationale, and the `~/.scout/dir`
pointer.

## Testing (TDD)

- `tests/test_local_setup.sh` (new): with a fixture Atlas (`git init` + commit in
  a tmp dir) as `ATLAS_REPO` and a `SUB_TOPICS_TSV`, assert it clones, prints
  `SCOUT_DIR`/`DATE`/`PARENT_DIR`/`START_TS`, creates each child dir under
  `research/<DATE>-<slug>/`, the slug is unique (second run → `-2`), and that a
  missing `ATLAS_REPO` (no env, no `docker/.env`) exits non-zero with the "set
  ATLAS_REPO" message.
- `tests/test_commands_present.sh` (new): `.claude/commands/scout-async.md`
  exists, contains no `Format`/`format` question; `.claude/commands/scout.md`
  exists with the interactive frontmatter (`Agent` in allowed-tools).
- `test_format_removed.sh`: unchanged, stays green.
- `publish.sh`: covered by `test_publish.sh` (reused untouched).

The command prompt (markdown) and the Liquid template aren't unit-tested; their
bash dependency (`local-setup.sh`) and reused `publish.sh` are, and the compass
edit is verified by a local Jekyll render of one expedition.

## Cross-repo sequencing

1. **compass**: cost-badge conditional → commit.
2. **Atlas**: bump compass submodule pointer.
3. **Scout**: commands, `local-setup.sh`, installer, docs, tests.

Scout work is independent of 1–2 except that a `cost_usd: "sub"` page renders
`$sub` until compass is updated — so land compass first (or same session).

## Backward compatibility / migration

- Project-scoped commands mean a `git pull` in Scout yields the rename with no
  action. Existing **global** installs get it on the next installer run (which
  switches them to symlinks); a one-line OPERATE note covers users who installed
  globally before this shipped.
- No data migration: local expeditions use the same `expedition` layout +
  `children:` + `manifest.json` contract as async, so old and new are
  indistinguishable on Atlas.

## Out of scope

- Recursive expedition children (a `deep` child fanning out further) — children
  are single-pass; the async runner remains the tool for nested decomposition.
- Failure-placeholder pages, per-child incremental push, resumability, rerun
  hooks — unattended-robustness the interactive session doesn't need. (`run.sh`/
  `run-decompose.sh` retain all of it for the async path.)
- A real numeric `cost_usd` for local runs (unmeasurable on subscription).
- Re-introducing user-facing format on the async/issue path.
