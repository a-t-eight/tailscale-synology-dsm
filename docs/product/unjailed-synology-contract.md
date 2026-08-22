# Unjailed Tailscale for Synology DSM

## Product behavior

The unjailed package runs `tailscaled` with the kernel networking behavior that
Tailscale uses on Linux rather than DSM's historical userspace-only package
mode. On supported DSM systems it:

- uses `/dev/net/tun` and exposes the `tailscale0` kernel interface;
- uses the Linux netfilter backend for routing, forwarding and NAT;
- preserves routing and netfilter preferences accepted by `tailscale up`;
- supports subnet-routing behavior through the kernel router;
- requires an administrator-installed root runtime before package startup;
- verifies the root runtime and repairs required Tailscale netfilter hooks.

Package startup fails closed when TUN, root-runtime or required netfilter
prerequisites are unavailable. Agent workflows must not run bootstrap or alter
those prerequisites on a NAS.

## r2 and later package contract

The dependency file is exactly:

```text
[iptables-netfilter-extensions]
pkg_min_ver=1.1.0-3
os_min_ver=7.3-86009
```

Tailscale package metadata uses `os_min_ver="7.3-86009"`. Production r2 and
later lineage omits `os_max_ver`; an empty or widened maximum is not a
substitute for omission.

The dependency declaration is only a declaration. This repository does not
build, install or publish the `iptables-netfilter-extensions` SPK as part of a
Tailscale version preparation.

## Preservation boundary

`release/upgrade-baseline.json` records the accepted candidate and the five
core unjailed source blobs plus the canonical patch/checksum. Version-workflow
changes validate those seven identities but do not recreate or modify them.
Any identity difference is a stop condition requiring separate product review.
