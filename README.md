# Tailscale Synology DSM downstream

Unofficial downstream patch, build, and validation project for running
Tailscale with kernel TUN, subnet routing, exit-node, and Linux netfilter
support on compatible Synology DSM systems.

This project is independently maintained and is not affiliated with or
supported by Tailscale, Inc. or Synology Inc.

## Start here

| Audience | Entry point |
| --- | --- |
| Install the current package | [Published releases](https://github.com/a-t-eight/tailscale-synology-dsm/releases) and the release-specific installation notes |
| Understand the repository | [Repository guide](docs/repository-guide.md) |
| Understand the package and root bootstrap | [Package runtime guide](docs/package-runtime.md) |
| Prepare a future Tailscale version | [Version-update runbook](docs/runbooks/tailscale-synology-version-update.md) |
| Build or validate a release | [Governance tooling](docs/governance/tooling.md) |
| Organise a local multi-worktree checkout | [Development workspace guide](docs/development-workspace.md) |

Package users normally do not need to clone this repository. Download the SPK
and `SHA256SUMS` from the applicable GitHub release and follow that release's
installation and administrator-bootstrap instructions.

## Current production release

| Property | Value |
| --- | --- |
| Upstream source tag | `v1.98.9` |
| Upstream source commit | `6c167d40fa37aeb51afa7ff336730670ea4762bf` |
| Downstream revision | `r2` |
| Downstream release commit | `0fad8b81a3e0eb86c457bc79c474bcc213834c43` |
| Release source tree | `33f5c5927ae4db54b9d582650ed31cc6a2eb7161` |
| Release branch | `release/v1.98.9-r2-synology` |
| Signed release tag | `release/synology-v1.98.96-r2` |
| Published release | [Tailscale for Synology DSM 1.98.96-r2](https://github.com/a-t-eight/tailscale-synology-dsm/releases/tag/release/synology-v1.98.96-r2) |
| Accepted package | `tailscale-x86_64-1.98.96-700098097-dsm7.spk` |
| Accepted package SHA-256 | `f947a1747521c50edf49baf597cc18b512b3bb009c3b7afe963fa326ef2d6c16` |
| Tested platform | Synology DS920+ / `geminilake` / `x86_64` |
| Tested DSM | DSM 7.4.1 |
| Package DSM minimum | `7.3-86009` |
| Hard package dependency | `iptables-netfilter-extensions >= 1.1.0-2` |

Revision r1 remains in the repository as superseded release history. The
machine-readable current identity is [release/manifest.yaml](release/manifest.yaml),
and validated platform status is recorded in
[support-matrix.yaml](support-matrix.yaml).

## What this project changes

The downstream source stack:

- enables kernel TUN operation on DSM;
- enables Tailscale's Linux routing and netfilter paths;
- adds an attended administrator bootstrap for the required root runtime;
- requires the separate netfilter-extension package;
- reconstructs and supervises required DSM networking state;
- adds deterministic package construction, inspection, and release evidence.

The package declares a hard dependency on
`iptables-netfilter-extensions >= 1.1.0-2`. That dependency is a separate
Synology SPK built with the
[SynoCommunity `spksrc` toolchain](https://github.com/SynoCommunity/spksrc).
It supplies iptables and netfilter kernel modules that stock DSM does not make
available to the package and that are required for Tailscale's full Linux
networking feature set.

## Repository model

This is one GitHub repository containing multiple branch roots with distinct
roles. The default branch is intentionally not the Tailscale source branch.

| Ref | Purpose | Change policy |
| --- | --- | --- |
| `main` | Exact fast-forward mirror of upstream Tailscale | Never add downstream files or commits |
| `synology/main` | Default downstream control branch: manifests, patches, tests, evidence indexes, tooling, and documentation | Documentation and control changes through reviewed signed commits |
| `release/<upstream>-synology` | Pinned upstream source plus an accepted signed downstream source stack | Frozen after release acceptance |
| `work/*` | Temporary source adaptation or release preparation | Disposable only after integration and evidence checks |
| `codex/*`, `docs/*`, `operations/*` | Temporary control-branch changes | Merge into `synology/main`, then remove after verification |
| `release/synology-*` tags | Signed release identities, treated as immutable by project policy | Never move or reuse |

The signed source commit stack is authoritative. Generated mail patches on
`synology/main` reproduce that stack and are validated by an exact round trip.
See the [repository guide](docs/repository-guide.md) for the complete mental
model and worktree workflow.

## Maintainer workflow

1. Clone the repository with its default `synology/main` branch.
2. Read `release/manifest.yaml`; do not infer the current release from a
   directory name or floating upstream reference.
3. Use a separate Git worktree for upstream-derived source branches.
4. Configure every worktree with `scripts/setup-worktree.sh`.
5. Run the repository-owned validation and build entrypoints.
6. Keep package installation, root bootstrap, firewall changes, reboot tests,
   and stable publication as explicit human-approved operations.

Validate the current control tree against an explicit accepted source
worktree:

```text
bash scripts/validate-repository.sh \
  --source-environment /path/to/accepted-release-worktree \
  --bootstrap
```

Validate the accepted source and patch round trip:

```text
bash scripts/release/validate-release.sh \
  --source-worktree /path/to/accepted-release-worktree \
  --role accepted \
  --round-trip
```

Do not build from the repository workspace root, from `synology/main`, or from
an arbitrarily selected source checkout.

## Project layout

- `release/manifest.yaml` — canonical current release identity and paths
- `support-matrix.yaml` — tested and unsupported platform records
- `patches/` — generated release patch series and retained historical exports
- `scripts/release/` — guarded release audit, preparation, build, and evidence entrypoints
- `scripts/governance/` — protected integration controls
- `tests/releases/` — source, package, reproducibility, and DSM acceptance evidence
- `docs/releases/` — frozen release closeout records and separate publication records
- `docs/runbooks/` — release and integration procedures
- `build-environment/` — build-toolchain ownership and separation

## Safety boundary

Automation may inspect, adapt, validate, and build non-production candidates.
It must not install packages on production DSM, run administrator bootstrap,
change production firewall state, reboot DSM, approve its own changes, or
publish a stable release without explicit maintainer approval.
