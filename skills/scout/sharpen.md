---
name: sharpen
description: Sharpen a raw research topic into a precise, verb-led brief that the Scout research playbook can act on. Invoked by scripts/sharpen.sh before research begins.
---

# Sharpen a raw research topic

You receive a vague or under-specified topic and rewrite it as a precise research brief. The result becomes the prompt that drives an actual Scout research run, so it must be unambiguous, scoped, and faithful to what the user asked.

## Inputs

```
Raw topic: <free text from the user>
Depth: <ceo | standard | deep>
Format: <md | html | auto>
```

Optional, present on a re-sharpen:

```
Previous sharpened proposal: <last sharpened version>
User feedback to incorporate: <user's reply asking for changes>
```

## Rules

1. **Reframe as a verb-led research deliverable.** "Survey of …", "Compare …", "Build a list of …", "Decision framework for …". Not a noun phrase.

2. **Add the current year if the topic is temporal.** State-of-the-art, "best in 2026", recent comparisons, evolving ecosystems — anchor with the year. If the topic is timeless (e.g. "explain CAP theorem"), don't.

3. **Surface implicit criteria.** What axes is the user likely to want compared? Common ones:
   - For tools/products: production-ready vs experimental, OSS vs commercial, recency, cost, maturity.
   - For hardware: price/perf, power draw, ecosystem, vendor lock-in.
   - For talks/SOTA: what's contested, what's consensus, what's bleeding edge.
   - For local/restaurants: price band, vibe, occasion fit.
   Add 1-3 such axes inline. Don't bloat — pick the ones most likely to matter.

4. **Preserve every steering hint in the raw topic verbatim.** If the user wrote "focus on r/homelab" or "academic sources only" or "must include a table", that text appears in the sharpened version word-for-word. Steering hints are sacred — never paraphrase them.

5. **Match scope to depth.** `ceo` → one-page decision. `standard` → 2-4 pages with comparison tables. `deep` → all angles. The sharpened brief should mention the expected output shape if that helps Scout (e.g. "produce a comparison table of N candidates" for `standard`).

6. **Don't invent constraints.** If the user didn't say "open-source only", don't add "focus on open-source". If unsure, leave out.

7. **On a re-sharpen:** treat `User feedback to incorporate` as a hard constraint. Take the previous sharpened proposal, apply the feedback as a delta, output the revised version. Don't drift away from the user's original intent.

## Output

Always emit the sharpened topic as one paragraph. No preamble ("Here is..."), no quotes, no bullet list, no markdown headers, no explanation of what you changed. Just the paragraph, ready to be passed verbatim to the research playbook.

**Then judge whether the topic is multi-angled.** A topic is multi-angled when it bundles independent sub-systems each worth their own deep dive (e.g., issue #10 mixes Slack remote control, branch/PR automation, deployment, routing, and orchestration). It is NOT multi-angled when the angles share a common axis the research already compares along (e.g. "compare ripgrep vs ag vs ack" — single comparison, not multi-angled).

If multi-angled and `Depth: deep` (expedition), append a fenced `scout-subtopics` block listing 2–8 sub-topics. Otherwise emit nothing after the paragraph.

### Sub-topics block format

````
```scout-subtopics
- [ ] (depth) **Title** — one-line rationale.
- [ ] (depth) **Title** — one-line rationale.
```
````

- `depth` is one of `recon` / `survey` / `expedition`.
- Default each child to `survey`; downgrade to `recon` for narrow angles; upgrade to `expedition` only when the sub-topic is itself multi-angled.
- Avoid `expedition` for more than one or two children — each `expedition` child internally spawns 3–8 parallel sub-agents, so stacking them runs hot.
- Cap at 8 sub-topics.
- Every sub-topic must start with `- [ ]` (unticked checkbox), then `(depth)`, then `**Title**`, then `— rationale`.
- Don't propose sub-topics that are mere sub-questions of one angle — those belong to the angle's own deep dive.

### Examples

**Narrow input:**
```
Raw topic: Compare ripgrep, ag, ack, and grep for searching a 50k-file repo. Decision-only.
Depth: standard
Format: auto
```

Output:
```
Decision framework comparing ripgrep, ag, ack, and grep for repository-scale code search in 2026, focused on speed on a 50k-file tree, ergonomic fit (PCRE/regex flavor, smart-case, gitignore awareness), packaging maturity, and the maintenance state of each tool. Decision-only.
```

(No `scout-subtopics` block — single comparison axis.)

**Wide input:**
```
Raw topic: I want to chat with Claude Code on Slack about a project, give a go, have a feature branch built, deployed to my Synology, and exposed via ProjectName-FeatureX.sangu.be. I need a workflow for this.
Depth: deep
Format: auto
```

Output:
```
Design and implement an end-to-end workflow that lets the user chat with Claude Code on Slack to spec, build, and review a feature, then auto-deploy each branch to a per-feature subdomain on Synology. Cover the wiring, state, and failure modes that tie the pieces together; favor production-ready open-source components in 2026.
```
```scout-subtopics
- [ ] (expedition) **Slack ↔ Claude Code remote control** — Per-project channels, message → agent invocation, approval/handoff, mobile UX. Needs survey of GitHub App vs Agent SDK vs self-hosted bot.
- [ ] (survey) **Branch and PR automation from a remote trigger** — How a "go" message produces a branch + commits + PR without a local checkout in the loop.
- [ ] (survey) **Synology preview deployments** — Container Manager / Docker Compose lifecycle per branch, build pipeline, teardown on branch delete.
- [ ] (expedition) **Per-feature subdomain routing** — Wildcard `*.sangu.be` reverse proxy (Traefik/Caddy/nginx), wildcard TLS via Let's Encrypt DNS-01, dynamic config from branch metadata.
- [ ] (recon) **Orchestration and state** — Glue tying the four pieces above; where state lives; failure modes and recovery.
```
