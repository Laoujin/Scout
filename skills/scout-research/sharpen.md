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
```

Optional, present on a re-sharpen:

```
Previous sharpened proposal: <last sharpened version>
User feedback to incorporate: <user's reply asking for changes>
```

Optional, present when the operator has configured a series manifest:

```
Existing series: <raw series.yml — each entry has slug, title, blurb, and optional groups with labels>
```

Optional, present on a re-sharpen when a series was previously selected:

```
Previous series: <prior scout-series block>
```

Optional, present when the operator has configured an identity profile:

```
User profile: <YAML body of the operator's profile.yml>
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

6. **Profile is an explicit input, not an invented constraint.** When a `User profile:` block is present, you may use its fields *only when the raw topic naturally intersects them*.

   - "Best ramen" → use `location`.
   - "Best mobile plan" → use `location` + `currency`.
   - "Recommended pingpong paddle under €100" → use `currency` + (already-listed) interest level.
   - "Explain the CAP theorem" → ignore the profile entirely.

   Never inject all fields blindly. Profile fields are *facts about the operator*, not preferences about the output style.

   Expertise hints (e.g. `programming (expert)`) shift the implied register of the sharpened brief: skip 101 framing for expert-level interests. Don't translate this into output-style instructions — the sharpened topic is still a research brief, not a writing-style memo.

7. **Don't invent constraints — but do suggest missing coverage.** Keep two things distinct. A *constraint* biases the output ("open-source only", "academic sources only"): never invent one — if the user didn't say it, leave it out. A *coverage angle* is a facet of the domain worth researching: standard facets the brief is silent on should be *surfaced as opt-in suggestions* (the completeness sweep in the Output section), not assumed. Suggesting an angle the user can decline ≠ imposing a constraint they didn't ask for.

8. **On a re-sharpen:** treat `User feedback to incorporate` as a hard constraint. Take the previous sharpened proposal, apply the feedback as a delta, output the revised version. Don't drift away from the user's original intent.

   **Sub-topic continuity on re-sharpen.** When `Previous sub-topics:` is present in the input, treat the listed sub-topics as the working set. Apply the user's feedback as a delta to that set: merge, drop, reorder, retitle, or change `(depth)` per the feedback's intent. If the feedback is paragraph-only (no sub-topic guidance), preserve the prior sub-topic list unchanged in your output's `scout-subtopics` block — *unless the re-sharpened topic is no longer multi-angled*, in which case omit the block entirely per the Output section's rules. Only re-decide the multi-angled judgment from scratch if the user explicitly asks ("decompose differently", "treat as one topic", etc.) or if the feedback narrows the topic enough that decomposition no longer fits.

9. **Series match (only when `Existing series:` is present).** The `Existing series:` block is the raw `series.yml` (each entry has `slug`, `title`, `blurb`, and optional `groups` with `label`s). If the sharpened topic *confidently* belongs to exactly one of these existing series, append a `scout-series` block (see Output). Be conservative — if there's no confident match, emit nothing. Never invent a series that isn't in the list. Pick at most one series. For a grouped series, pick the single best-fitting group label from those listed. On a re-sharpen, treat `Previous series:` as the working selection and apply the user's feedback as a delta (keep it, change the group, or drop it).

## Output

Emit the sharpened topic as a structured brief: a **bold one-line deliverable** (verb-led — "Decision framework…", "Survey of…", "Compare…"), then 2–5 markdown bullets. Use bullets such as `Scope:`, `Compare:` (the axes from rule 3), `Constraints:` (steering hints, verbatim), and `Output:` (the shape implied by depth). No preamble ("Here is…"), no quotes, no `#` headings (the bold lead line is the title), no explanation of what you changed. Keep it tight — don't pad. The whole brief is passed verbatim to the research playbook, so the bold lead line should read as the deliverable on its own.

**Then judge whether the topic is multi-angled.** A topic is multi-angled when it bundles independent sub-systems each worth their own deep dive (e.g., issue #10 mixes Slack remote control, branch/PR automation, deployment, routing, and orchestration). It is NOT multi-angled when the angles share a common axis the research already compares along (e.g. "compare ripgrep vs ag vs ack" — single comparison, not multi-angled).

If multi-angled and `Depth: deep` (expedition), append a fenced `scout-subtopics` block listing 2–8 sub-topics. Otherwise emit nothing after the paragraph.

**Then run a completeness sweep (expedition only).** Decomposition above is faithful to what the brief *says*; this step covers what it *omits*. Ask: for this kind of deliverable, what standard facets would a practitioner expect that the brief is silent on? Surface up to 3 as **unticked** `- [ ]` sub-topics — proposed but not assumed, so the user ticks only the ones they want (rule 7: suggest coverage, never impose a constraint). Skip anything the stated angles already cover; if nothing standard is genuinely missing, add nothing. Typical omissions by deliverable type:

- Build/ship a service or tool → security & auth, deployment/distribution, testing, observability.
- Choose a tool/product → total cost, migration effort, lock-in, maintenance burden.
- Design/architecture → failure modes, scaling, operability.

The two angles that prompted this rule (a "build your own MCP server" session that named protocol/ideas/format/debugging/RAG but silently omitted **security** and **deployment**) are exactly what the sweep exists to catch — the user shouldn't have to ask "what am I missing?".

### Sub-topics block format

````
```scout-subtopics
- [x] (depth) **Title** — one-line rationale.
- [x] (depth) **Title** — one-line rationale.
```
````

- `depth` is one of `recon` / `survey` / `expedition`.
- Default each child to `survey`; downgrade to `recon` for narrow angles; upgrade to `expedition` whenever the sub-topic is itself multi-angled.
- Cap at 8 sub-topics total (stated + suggested); at most 3 of those may be unticked completeness suggestions.
- Each sub-topic starts with a checkbox, then `(depth)`, then `**Title**`, then `— rationale`. Use `- [x]` (ticked, selected by default) for angles derived from the stated brief. Use `- [ ]` (unticked, opt-in) for completeness-sweep suggestions the user didn't state. List all ticked angles first, then any unticked suggestions.
- Don't propose sub-topics that are mere sub-questions of one angle — those belong to the angle's own deep dive.

### Series block format

When rule 9 yields a confident match, append (after any sub-topics block):

````
```scout-series
- [x] **<series-slug>** › <group-label> — one-line rationale.
```
````

- Ticked (`- [x]`) by default — it's a suggestion the user can untick.
- Include `› <group-label>` only for a grouped series; omit it entirely for a flat series.
- Exactly one line. Omit the whole block when there is no confident match.

### Examples

**Narrow input:**
```
Raw topic: Compare ripgrep, ag, ack, and grep for searching a 50k-file repo. Decision-only.
Depth: standard
```

Output:
```
**Decision framework: ripgrep vs ag vs ack vs grep for repository-scale code search (2026).**

- Scope: searching a 50k-file repository; decision-only.
- Compare: raw speed on a large tree, ergonomic fit (PCRE/regex flavor, smart-case, gitignore awareness), packaging maturity, maintenance state.
- Output: a comparison table of the four tools with a clear recommendation.
```

(No `scout-subtopics` block — single comparison axis.)

**Wide input:**
```
Raw topic: I want to chat with Claude Code on Slack about a project, give a go, have a feature branch built, deployed to my Synology, and exposed via ProjectName-FeatureX.sangu.be. I need a workflow for this.
Depth: deep
```

Output:
```
**Design and implement a Slack-driven, per-feature deploy workflow for Claude Code on Synology (2026).**

- Scope: chat with Claude Code on Slack to spec, build, and review a feature, then auto-deploy each branch to a per-feature subdomain on Synology.
- Cover: the wiring, state, and failure modes that tie the pieces together.
- Constraints: favor production-ready open-source components.
```
```scout-subtopics
- [x] (expedition) **Slack ↔ Claude Code remote control** — Per-project channels, message → agent invocation, approval/handoff, mobile UX. Needs survey of GitHub App vs Agent SDK vs self-hosted bot.
- [x] (survey) **Branch and PR automation from a remote trigger** — How a "go" message produces a branch + commits + PR without a local checkout in the loop.
- [x] (survey) **Synology preview deployments** — Container Manager / Docker Compose lifecycle per branch, build pipeline, teardown on branch delete.
- [x] (expedition) **Per-feature subdomain routing** — Wildcard `*.sangu.be` reverse proxy (Traefik/Caddy/nginx), wildcard TLS via Let's Encrypt DNS-01, dynamic config from branch metadata.
- [x] (recon) **Orchestration and state** — Glue tying the four pieces above; where state lives; failure modes and recovery.
- [ ] (recon) **Secrets and credential handling** — Where Slack tokens, GitHub creds, and TLS keys live across the pipeline; not named in the brief but standard for a deploy workflow. (completeness suggestion)
```
