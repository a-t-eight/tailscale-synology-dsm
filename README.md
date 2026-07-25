# Tailscale Synology DSM downstream

Unofficial downstream patch, build and validation project for running
Tailscale with kernel TUN, subnet routing and Linux netfilter support on
supported Synology DSM systems.

This project is not affiliated with or supported by Tailscale Inc. or
Synology Inc.

## Branch model

- `synology/main` contains downstream control assets, documentation,
  generated patch series, tests, hooks and build orchestration.
- `main` is an unmodified mirror of `tailscale/tailscale` upstream.
- `release/<upstream>-synology` branches contain an upstream release plus
  the applied downstream commit stack.
- `work/<upstream>-synology` branches are temporary adaptation branches.

## Current production baseline

| Property | Value |
|---|---|
| Upstream tag | `v1.98.9` |
| Upstream commit | `6c167d40fa37aeb51afa7ff336730670ea4762bf` |
| Downstream tip | `cc5d96275e9dd76fd8a4f38209a2df91199a425c` |
| Release branch | `release/v1.98.9-synology` |
| Package version | `1.98.96-700098096` |
| Package architecture | `x86_64` |
| Tested platform | Synology DS920+ / geminilake |
| Minimum DSM | `7.3-81180` |
| Netfilter dependency | `tailscale-netfilter-modules >= 1.0.0-11` |

Production sideload SPK SHA-256:

```text
fa60ade44b2bbe95c0aa8c99221fd1dd9fb08f152bbafbc608af51fa9107a177
```

## Safety boundary

Builds and candidate validation may be assisted by automation or agents.
Installation, root bootstrap, firewall mutation and reboot testing remain
human-controlled operations.

## Repository layout

- `patches/` — generated per-release patch series and manifests
- `scripts/` — patch, build and NAS validation tooling
- `tests/` — patch round-trip, package and acceptance tests
- `docs/` — architecture decisions, build and operational documentation
- `build-environment/` — pinned build-environment definitions
- `.githooks/` — version-controlled local Git hooks
- `.github/` — optional remote validation configuration
- `support-matrix.yaml` — validated DSM and architecture combinations
