Design and implement an end-to-end workflow that lets the user chat with Claude Code on Slack — ideally with a dedicated channel per project — to spec, approve, and ship a feature or bugfix, with the agent producing a branch and PR, deploying each branch to the user's Synology NAS, and exposing it at a per-feature subdomain like `ProjectName-FeatureX.sangu.be` in 2026. Cover the wiring, state, and failure modes that tie the pieces together; favor production-ready open-source components and call out where managed/commercial options materially change the trade-off.

```scout-subtopics
- (expedition) **Slack ↔ Claude Code remote control** — Per-project channels, message → agent invocation, "go" approval gates, mobile UX. Survey GitHub App vs Agent SDK vs self-hosted bot patterns.
- (survey) **Branch and PR automation from a remote trigger** — How a Slack "go" produces a branch, commits, and a PR without a developer-local checkout in the loop; auth, identity, and review hand-off.
- (expedition) **Synology per-branch preview deployments** — Container Manager / Docker Compose lifecycle per branch on DSM, build pipeline, resource limits, teardown on branch delete or PR merge.
- (survey) **Per-feature subdomain routing on `*.sangu.be`** — Wildcard reverse proxy (Traefik / Caddy / nginx-proxy-manager), wildcard TLS via Let's Encrypt DNS-01, dynamic config driven by branch metadata.
- (recon) **Orchestration and state glue** — What ties the four pieces together (webhooks, queue, small control-plane service), where canonical state lives, and failure/recovery modes when one stage fails mid-flight.
```
