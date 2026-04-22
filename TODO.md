Scout TODO List
===============

- [x] RESEARCH: Agents that could be used for doing research for Scout
- [ ] RESEARCH: Need an always on something instead of Synology which has problems: need more CPU/RAM, newer kernel, CPU with AVX2, no lock-in with custom DSM/Linux.
- [ ] RESEARCH: Need to buy a birthday gift for my girlfriend, I know about flowers, a massage, a cooking workshop ... I need truly unique ideas here
- [ ] RESEARCH: I need a listing of restaurants in Ghent. Everything romantic.

## Scout functionality

- [x] How to make this your own: how to set this up with your own Atlas
    - [x] Make as frictionless as possible (rawgithubusercontent/install.sh | bash)
    - [x] Maybe could be a multi step installation
    - [x] Should not clone my Atlas but start with a bare repository
- [ ] Slash Claude command
    - [ ] The options should be the Claude menu, the user picks, then it creates the github issue
    - [ ] Or we could just remove it
- [ ] Generating an image for the research would be very cool (ie give a Nano Banana API key?)
- [x] We prefer tables... but on mobile tables are not really handy... how do we handle that?
- [x] Add Claude cost to frontmatter
- [ ] Cleanup README


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
