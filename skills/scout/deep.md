# Scout deep-tier procedure

When `DEPTH=deep`, the parent (you, the main Scout session) becomes planner + writer. Researcher and reviewer sub-agents do the actual search and critique. This file extends `SKILL.md`; read it in addition to the base skill when `DEPTH=deep`.

## Flow

```
1. Parse inputs; fetch today's date (it's injected as DATE).
2. Plan: enumerate 3–8 sub-questions the artifact must answer.
   Breadth heuristic — pick the angles that apply to the topic:
     - the chooser's decision criteria
     - the maintainer/producer's claims
     - the skeptic's counter-reading
     - the operator's day-to-day experience
     - alternatives / competitors
     - how we got here (history / why now)
   Save the list of sub-questions to RESEARCH_DIR/outline.md (one per line).
3. Dispatch researcher sub-agents in parallel, one per sub-question.
   Use the Agent tool, subagent_type="scout-researcher".
   Each researcher gets: SUB_QUESTION, TOPIC, DATE, RESEARCH_DIR, LEDGER_FILE=citations.a<N>.jsonl, EXCLUDE_URLS=<empty for first wave>.
   Parallelism cap: max 6 concurrent researchers. If more sub-questions, batch.
4. After all researchers return: run `scripts/merge_ledgers.sh RESEARCH_DIR`.
   This reads every citations.a*.jsonl, dedupes by URL, renumbers, writes citations.jsonl.
   Researcher summaries stay in your context as draft material.
5. Draft the body (index.md or index.html) from the researcher summaries and the merged ledger.
   The body is the publishing artifact; researcher summaries are intermediate material — rewrite, don't copy-paste.
6. Dispatch scout-reviewer sub-agent (Agent tool, subagent_type="scout-reviewer").
   Pass: ARTIFACT_PATH, LEDGER_PATH=citations.jsonl, OUTLINE_PATH=outline.md, TOPIC, DEPTH=deep.
7. Apply reviewer's blocking-issue deltas in one pass.
   If reviewer's "Coverage gaps" section is non-trivial:
     - Dispatch up to 2 remediation researchers (same scout-researcher type) on the named gaps.
     - Pass EXCLUDE_URLS=<all URLs already in citations.jsonl>.
     - After they return: re-merge ledgers, add their findings to the body.
     - HARD CAP: one remediation round. No second reviewer pass.
   Apply reviewer's "Prose nits" deltas if trivial; skip if they'd cost another pass.
8. Final self-check (same as SKILL.md step 6). Write the artifact.
9. Report the final path.
```

## Hard caps (non-negotiable)

- Max 6 concurrent researcher sub-agents in the initial wave.
- Max 2 remediation researchers in the post-reviewer round.
- Exactly 1 reviewer sub-agent call. No re-review after fix.
- If the reviewer returns "artifact needs rewrite" as its blocking issue, write a one-line status to TOPIC frontmatter (`review_status: needs_rewrite`) and publish anyway — the user can decide to re-run. Do not loop.

## Researcher brief template

When you dispatch a researcher, the brief in the Agent tool's `prompt` field should be this exact shape, filled in:

```
You are a scout-researcher sub-agent.

SUB_QUESTION: <one-sentence sub-question from your outline>
TOPIC: <raw Scout topic>
DATE: <YYYY-MM-DD>
RESEARCH_DIR: <absolute path>
LEDGER_FILE: citations.a<N>.jsonl
EXCLUDE_URLS: <newline-separated list of URLs already cited by siblings, or "none">

Follow your skill. Return status/summary/source-count/coverage when done.
```

## Why researcher output is a compressed summary, not a trajectory

Each researcher has its own 200K context window. The parent's context is the bottleneck. If researchers dumped raw search trajectories back, deep runs would blow past the parent's limit (this is one of the fragilities open_deep_research and 199-biotech explicitly engineer around). Researchers do the search, extract, and summarise; parent only sees the summary + the ledger file on disk. The ledger is the source of truth; the summary is the handoff for drafting.

## What the parent writes vs what researchers write

- **Parent writes:** `outline.md` (before dispatch), `index.md` or `index.html` (after researchers + reviewer), any revised content in the fix pass.
- **Researchers write:** `citations.a<N>.jsonl` (their per-agent ledger). Nothing else.
- **`merge_ledgers.sh` writes:** `citations.jsonl` (the merged, deduped, renumbered file).
- **Reviewer writes:** nothing (tool allowlist is Read-only).
