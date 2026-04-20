---
description: Trigger a Scout research run via GitHub Actions (workflow_dispatch).
argument-hint: "[topic] [depth=standard] [format=auto]"
allowed-tools: Bash(gh workflow run:*), Bash(gh run list:*), Bash(gh run view:*)
---

Parse $ARGUMENTS as:
- `topic` = everything up to any `depth=` or `format=` token (required)
- `depth` = value after `depth=` if present, else `standard`
- `format` = value after `format=` if present, else `auto`

Then trigger the Scout workflow:

```
gh workflow run research.yml --repo Laoujin/Scout \
  -f topic="<topic>" \
  -f depth="<depth>" \
  -f format="<format>"
```

After triggering, run `gh run list --repo Laoujin/Scout --workflow research.yml --limit 1` and report the run URL. Do not poll or wait — the run takes 5-30 minutes.

Remind the user that the result will appear at https://laoujin.github.io/atlas/ once the run completes.
