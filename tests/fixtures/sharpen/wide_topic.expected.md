**Design and implement a Slack-driven, per-feature deploy workflow for Claude Code on Synology (2026).**

- Scope: chat with Claude Code on Slack (one channel per project) to spec a feature or bugfix, give a "go" that triggers implementation, and have the change land as a branch and PR, deploy to a Synology NAS, and expose itself at a per-feature subdomain like ProjectName-FeatureX.sangu.be.
- Cover: the wiring, state, and failure modes that tie the pieces together.
- Constraints: favor production-ready open-source components.

```scout-subtopics
- [x] (expedition) **Slack ↔ Claude Code remote control** — Per-project channel mapping, message → agent invocation, the "go" approval gate, mobile UX. Needs survey of GitHub App vs Agent SDK vs self-hosted bot.
- [x] (survey) **Branch and PR automation from a remote trigger** — How a "go" message produces a branch + commits + PR without a local checkout in the loop, and how PR status flows back to Slack.
- [x] (survey) **Synology preview deployments** — Container Manager / Docker Compose lifecycle per branch on DSM, build pipeline, image registry choice, teardown on branch delete or PR close.
- [x] (expedition) **Per-feature subdomain routing on sangu.be** — Wildcard `*.sangu.be` reverse proxy (Traefik/Caddy/nginx), wildcard TLS via Let's Encrypt DNS-01, dynamic config generated from branch metadata.
- [x] (recon) **Orchestration and state** — Glue tying the four pieces above; where per-feature state lives (DB, env, secrets); failure modes and recovery when one stage fails mid-flow.
```
