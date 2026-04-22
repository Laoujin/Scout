---
description: Open a Scout research Issue.
argument-hint: "[topic]"
allowed-tools: AskUserQuestion, Bash(gh issue create:*)
---

`$ARGUMENTS` is the research topic (free text, may be empty).

## Step 1 — Topic

If `$ARGUMENTS` is non-empty, use it verbatim as the topic. Otherwise ask the user for one in chat (plain message, not `AskUserQuestion` — topic is free text).

## Step 2 — Options

Call `AskUserQuestion` once with these three questions:

1. **Depth** (header `Depth`, single-select):
   - `survey` — 2-4 pages, balanced overview (Recommended)
   - `recon` — one-page decision brief
   - `expedition` — all angles, long-form
2. **Format** (header `Format`, single-select):
   - `auto` — Scout picks md or html (Recommended)
   - `md` — markdown body
   - `html` — bespoke HTML body
3. **Skip sharpening** (header `Sharpen`, single-select):
   - `No` — let Scout sharpen the topic and propose (Recommended)
   - `Yes` — use my topic verbatim, no proposal round-trip

## Step 3 — Create the Issue

```
gh issue create --repo {{SCOUT_REPO}} \
  --title "[research] <truncate topic to ~60 chars>" \
  --label scout-research \
  --body "$(printf '### Topic\n\n%s\n\n### Depth\n\n%s\n\n### Format\n\n%s\n\n### Options\n\n- [%s] Skip sharpening (use my topic verbatim)\n' "<topic>" "<depth>" "<format>" "<x if skip else space>")"
```

Print the Issue URL. If skip-sharpening is No, tell the user: "Scout will reply with a sharpened proposal in ~30s. Tick the **Start research** checkbox to publish, or reply with feedback for another proposal." If skip-sharpening is Yes, tell the user the research job will kick off directly (5-30 min).

Do not poll. The sharpen step takes 10-30 seconds; the research step takes 5-30 minutes. The published artifact will appear at https://laoujin.github.io/atlas/.
