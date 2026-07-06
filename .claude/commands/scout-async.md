---
description: Open a Scout research Issue (async runner).
argument-hint: "[topic]"
allowed-tools: AskUserQuestion, Bash, Read
---

`$ARGUMENTS` is the research topic (free text, may be empty).

## Step 0 — Resolve your Scout fork + Atlas URL

The issue must be opened on **your** Scout fork, and the published artifact lands on
**your** Atlas site. Derive both from your already-registered Atlas checkout — nothing
is baked into this command.

1. Resolve `SCOUT_DIR` (holds `scripts/`): if the text `${CLAUDE_PLUGIN_ROOT}` on this
   line reads as an absolute path (installed plugin), use it; else if `~/.scout/dir`
   exists use `$(cat ~/.scout/dir)`; else use the checkout that contains this file.
2. Run `bash $SCOUT_DIR/scripts/atlas-config.sh resolve-atlas`.
   - **Exit 0** → `ATLAS_DIR=<printed path>`. Then:
     - `SCOUT_REPO` = the `scout_repo:` value in `$ATLAS_DIR/_config.yml`.
     - `ATLAS_URL` = derive from `git -C "$ATLAS_DIR" remote get-url origin`: for
       `…github.com[:/]<owner>/<repo>(.git)`, it is `https://<owner>.github.io/<repo>/`.
   - **Non-zero** (no Atlas registered yet) → ask the user in chat for their Scout fork
     slug (`<owner>/Scout`) and Atlas URL, and use those. Suggest they run `/scout:scout`
     once to register their Atlas checkout so this is automatic next time.

Use the resolved `SCOUT_REPO` and `ATLAS_URL` in Step 3.

## Step 1 — Topic

If `$ARGUMENTS` is non-empty, use it verbatim as the topic. Otherwise ask the user for one in chat (plain message, not `AskUserQuestion` — topic is free text).

## Step 2 — Options

Call `AskUserQuestion` once with these two questions:

1. **Depth** (header `Depth`, single-select):
   - `survey` — 2-4 pages, balanced overview (Recommended)
   - `recon` — one-page decision brief
   - `expedition` — all angles, long-form
2. **Do a sharpening round-trip** (header `Sharpen`, single-select):
   - `Yes` — let Scout propose a sharpened prompt before researching (Recommended)
   - `No` — use my topic verbatim and start research

## Step 3 — Create the Issue

```
gh issue create --repo "$SCOUT_REPO" \
  --title "[research] <truncate topic to ~60 chars>" \
  --label scout-research \
  --body "$(printf '### Topic\n\n%s\n\n### Depth\n\n%s\n\n### Options\n\n- [%s] Skip sharpening (use my topic verbatim)\n' "<topic>" "<depth>" "<x if sharpen=No else space>")"
```

Print the Issue URL. If sharpen is Yes, tell the user: "Scout will reply with a sharpened proposal in ~30s. Tick the **Start research** checkbox to publish, or reply with feedback for another proposal." If sharpen is No, tell the user the research job will kick off directly (5-30 min).

Do not poll. The sharpen step takes 10-30 seconds; the research step takes 5-30 minutes. The published artifact will appear at the resolved `$ATLAS_URL`.
