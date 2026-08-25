# Project context

This repository maintains a downstream Synology DSM build of Tailscale.

The current downstream changes enable kernel TUN, subnet routing and the
Linux netfilter backend on DSM, and add a controlled root-runtime
bootstrap, netfilter dependency validation, deterministic TUN creation
and supervised netfilter reconciliation.

The current production baseline is downstream revision `r2`, derived from
upstream `v1.98.9` at release commit
`0fad8b81a3e0eb86c457bc79c474bcc213834c43`. It was accepted as package
`1.98.96-700098097` on a DS920+ running DSM 7.4.1 after installation,
administrator bootstrap, lifecycle, TUN, routing and IPv4/IPv6 netfilter
testing.

The package declares a hard dependency on
`iptables-netfilter-extensions >= 1.1.0-2`. The earlier r1 package remains
retained as superseded history. `release/manifest.yaml` is the canonical
machine-readable current release identity.

`main` is upstream-owned history. `synology/main` is the downstream
maintenance and documentation branch. Upstream-derived downstream source lives
on versioned `release/*-synology` branches; temporary adaptation and control
work belongs in separate worktrees.
