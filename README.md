# Tailscale Synology DSM downstream

Unofficial downstream patch, build and validation project for running Tailscale
with kernel TUN, subnet routing and Linux netfilter support on supported
Synology DSM systems.

This project is not affiliated with or supported by Tailscale Inc. or
Synology Inc.

## Branch model

- `synology/main` contains downstream control assets, documentation, generated
  patch series, tests, hooks and build orchestration.
- `main` is an unmodified fast-forward mirror of `tailscale/tailscale`.
- `release/<upstream>-synology` contains a pinned upstream release plus the
  signed downstream commit stack.
- `work/<upstream>-synology` is temporary adaptation state.

## Canonical release metadata

`release/manifest.yaml` is the machine-readable source of release identity,
branch names, package identity, build entrypoints and evidence paths.

Operational scripts must derive release values from that manifest. The
accepted baseline explicitly records its aggregate `release-tree.patch`,
contained `maintenance.patch` reference subset, legacy raw-diff format and exact
historical commits that predate the sign-off rule. The reference subset is
validated independently but is not applied as a second patch. These exceptions
do not transfer to a future release.

Closed release documents and retained evidence remain immutable historical
records.

## Current production baseline

| Property | Value |
| --- | --- |
| Upstream tag | `v1.98.9` |
| Upstream commit | `6c167d40fa37aeb51afa7ff336730670ea4762bf` |
| Downstream release commit | `20c86229955a3d03de01901aee1499cab87c571d` |
| Release source tree | `6d022c18f27a42aab553697c69c852bebd8594b8` |
| Release branch | `release/v1.98.9-synology` |
| Signed release tag | `release/synology-v1.98.96-r1` |
| Accepted package | `tailscale-x86_64-1.98.96-700098096-dsm7.spk` |
| Accepted package SHA-256 | `bed218b4d0099102e9c3be18456d8a94be9a92b4a29295a9dab33932570cbce0` |
| Tested platform | Synology DS920+ / geminilake |
| Minimum DSM | `7.3-81180` |
| Netfilter dependency | `tailscale-netfilter-modules >= 1.0.0-11` |

## Canonical commands

Audit the accepted release inputs:

```text
bash scripts/release/audit-inputs.sh \
  --source-repo /path/to/accepted-release-worktree
```

Validate source and canonical patches:

```text
bash scripts/release/validate-release.sh \
  --source-worktree /path/to/release-worktree \
  --role release \
  --round-trip
```

Review a candidate build without executing it:

```text
bash scripts/release/build-candidate.sh \
  --source-worktree /path/to/release-worktree \
  --role release \
  --dry-run
```

The complete future-version procedure is:

```text
docs/runbooks/tailscale-synology-version-update.md
```

## Safety boundary

Automation may inspect, adapt, validate and build candidate artefacts.

Installation, root bootstrap, firewall mutation, reboot testing and stable
publication remain explicit human-controlled operations.

## Repository layout

- `release/manifest.yaml` — canonical release identity and paths
- `patches/` — generated per-release patch series and manifests
- `scripts/release/` — guarded release entrypoints
- `scripts/setup-worktree.sh` — worktree-specific hooks and signing setup
- `tests/releases/` — source, package, reproducibility and acceptance evidence
- `docs/runbooks/` — operator procedures
- `docs/releases/` — immutable closed-release records
- `build-environment/` — build-environment ownership and pinning
- `support-matrix.yaml` — validated DSM and architecture combinations
