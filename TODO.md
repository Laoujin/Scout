Scout TODO List
===============

## Security

--> The GH token & the Claude Subscription

┌────────┬──────────────────────────────────────────────────────────────────┬─────────┐
│ Effort │                            Mitigation                            │  Stops  │
├────────┼──────────────────────────────────────────────────────────────────┼─────────┤
│ Low    │ Docker network without route to LAN (network_mode: bridge +      │ #1      │
│        │ firewall rule dropping RFC1918 egress)                           │         │
├────────┼──────────────────────────────────────────────────────────────────┼─────────┤
│ Low    │ GH_TOKEN minimum scope — already contents: read, issues: write,  │ limits  │
│        │ which is good; double-check no broader PAT                       │ #2      │
├────────┼──────────────────────────────────────────────────────────────────┼─────────┤
│ Low    │ Never mount ~/.claude/ read-write; read-only bind if at all      │ limits  │
│        │                                                                  │ #2      │
├────────┼──────────────────────────────────────────────────────────────────┼─────────┤
│ Low    │ Read-only root filesystem, writable tmpfs for scratch            │ #3      │
├────────┼──────────────────────────────────────────────────────────────────┼─────────┤
│ Medium │ Require human approval before Scout commits & pushes to Atlas    │ #3, #4  │
│        │ (manual gh pr merge or workflow_dispatch)                        │         │
├────────┼──────────────────────────────────────────────────────────────────┼─────────┤
│ Medium │ Output validator: reject published content containing <script>,  │ #4      │
│        │ off-topic URLs, secrets-like strings                             │         │
├────────┼──────────────────────────────────────────────────────────────────┼─────────┤
│ Medium │ Egress allowlist (only anthropic.com, github.com, approved       │ #1, #2  │
│        │ search domains) via squid/envoy sidecar                          │         │
├────────┼──────────────────────────────────────────────────────────────────┼─────────┤
│ High   │ Seccomp + AppArmor profile, drop all caps, non-root user         │ #6      │
└────────┴──────────────────────────────────────────────────────────────────┴─────────┘
