# Project context

This repository maintains a downstream Synology DSM build of Tailscale.

The current downstream changes enable kernel TUN, subnet routing and the
Linux netfilter backend on DSM, and add a controlled root-runtime
bootstrap, netfilter dependency validation, deterministic TUN creation
and supervised netfilter reconciliation.

The first production baseline is derived from upstream `v1.98.9` and was
accepted as package `1.98.96-700098096` after upgrade, restart, reboot,
TUN reconstruction and IPv4/IPv6 netfilter topology testing.

`main` is upstream-owned history. `synology/main` is the downstream
maintenance and documentation branch.
