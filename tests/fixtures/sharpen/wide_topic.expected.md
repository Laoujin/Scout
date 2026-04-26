Design and implement an end-to-end workflow that lets the user chat with Claude Code on Slack (with a Slack channel per project) to spec a feature/bugfix, give a "go", and have Claude Code create a branch and a PR, then auto-deploy each branch to the user's Synology NAS exposed at a per-feature subdomain in the form `ProjectName-FeatureX.sangu.be`. Cover the wiring, state, and failure modes that tie the pieces together end-to-end; favor production-ready open-source components in 2026.

```scout-subtopics
- (expedition) **Slack ↔ Claude Code remote control** — Per-project channels, message → agent invocation, the "go" approval handoff, mobile UX. Needs survey of GitHub App vs Agent SDK vs self-hosted bot.
- (survey) **Branch and PR automation from a remote trigger** — How a "go" message produces a branch + commits + PR without a local checkout in the loop; auth, signing, and review gating.
- (survey) **Synology preview deployments** — Container Manager / Docker Compose lifecycle per branch on DSM, build pipeline, image registry, teardown on branch delete or PR merge.
- (expedition) **Per-feature subdomain routing on `*.sangu.be`** — Wildcard reverse proxy (Traefik/Caddy/nginx-proxy-manager) on Synology, wildcard TLS via Let's Encrypt DNS-01, dynamic config sourced from branch/PR metadata.
- (recon) **Orchestration and state** — Glue tying the four pieces above; where state lives (PR labels, k/v, filesystem), idempotency, failure modes, and recovery.
```
