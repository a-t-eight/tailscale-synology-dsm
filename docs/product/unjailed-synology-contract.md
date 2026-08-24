# Unjailed Tailscale for Synology DSM

## Product behavior

The unjailed package runs `tailscaled` with the kernel networking behavior that
Tailscale uses on Linux rather than DSM's historical userspace-only package
mode. On supported DSM systems it:

- uses `/dev/net/tun` and exposes the `tailscale0` kernel interface;
- uses the Linux netfilter backend for routing, forwarding and NAT;
- preserves routing and netfilter preferences accepted by `tailscale up`;
- supports subnet-routing behavior through the kernel router;
- enters an explicit bootstrap-pending staging state after installation, in
  which DSM reports the package healthy only to retain package resources while
  `tailscaled` remains stopped;
- requires an administrator-installed root runtime before daemon startup;
- verifies the root runtime and repairs required Tailscale netfilter hooks.

Initial approval must run the root-owned outer package script:

```text
sudo /var/packages/Tailscale/scripts/tailscale-synology-bootstrap install
```

The `/usr/local/bin/tailscale-synology-bootstrap` linker target is
package-owned before approval and must not be executed through `sudo` in that
state. A successful bootstrap changes the package target to `root:root`; the
linked command is then a trusted post-bootstrap convenience entry point.

After approval, package startup fails closed when TUN, root-runtime or required
netfilter prerequisites are unavailable. Agent workflows must not run
bootstrap or alter those prerequisites on a NAS.

## r2 and later package contract

The dependency file is exactly:

```text
[iptables-netfilter-extensions]
pkg_min_ver=1.1.0-2
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

## CI ownership and validation boundary

The `synology-product` job is the required fork-owned gate for ordinary
downstream pull requests. It validates the version-preparation contracts and
offline preparation fixtures, control-hook behavior, promoted patch inventory,
changed-shell static analysis, the complete release diff policy, every
repository-owned Synology shell test, focused Go packages that contain the
Synology changes (`release/dist/synology`, `cmd/tailscale/cli`,
`cmd/tailscaled`, `ipn/ipnlocal`, `util/linuxfw`, and `wgengine/router`),
`git diff --check`, and unchanged tracked and untracked repository state. It
does not build an SPK or exercise a DSM host.

The inherited full upstream compatibility workflows are explicit/manual for
an upstream-version upgrade rather than automatic downstream pull-request
gates. Upstream OSS-Fuzz ownership remains with `tailscale/tailscale` and covers
only `net/stun.FuzzStunParser`; it is not Synology fuzz coverage and does not
exercise SPK or DSM behavior, package metadata, downstream patches, bootstrap,
TUN, or netfilter behavior.
