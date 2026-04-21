---
description: Open a Scout research Issue (default) or directly dispatch the workflow.
argument-hint: "[topic] [depth=standard] [format=auto] [--dispatch]"
allowed-tools: Bash(gh issue create:*), Bash(gh workflow run:*), Bash(gh run list:*), Bash(gh issue view:*)
---

Parse $ARGUMENTS as:

- `topic` = everything up to any `depth=`, `format=`, or `--dispatch` token (required)
- `depth` = value after `depth=` if present, else `standard`
- `format` = value after `format=` if present, else `auto`
- `dispatch` = `true` if `--dispatch` appears anywhere, else `false`

## Default path: open an Issue

Build a body matching the research Issue Form structure so the workflow's parser sees the same shape it gets from a manually-opened Issue:

```
gh issue create --repo Laoujin/Scout \
  --title "[research] <truncate topic to ~60 chars>" \
  --label scout-research \
  --body "$(printf '### Topic\n\n%s\n\n### Depth\n\n%s\n\n### Format\n\n%s\n\n### Options\n\n- [ ] Skip tightening (use my topic verbatim)\n' "<topic>" "<depth>" "<format>")"
```

After creation, print the Issue URL and tell the user: "Scout will reply with a sharpened proposal in ~30s. Tick the **Start research** checkbox to publish, or reply with feedback for another proposal."

Do not poll — the tighten step takes 10-30 seconds; the research step takes 5-30 minutes.

## --dispatch path: skip the Issue, run research immediately

When `--dispatch` is set, fire the workflow directly with the raw topic:

```
gh workflow run research.yml --repo Laoujin/Scout \
  -f topic="<topic>" -f depth="<depth>" -f format="<format>"
```

Then `gh run list --repo Laoujin/Scout --workflow research.yml --limit 1` and report the run URL.

In both cases, remind the user that the published artifact will appear at https://laoujin.github.io/atlas/.
