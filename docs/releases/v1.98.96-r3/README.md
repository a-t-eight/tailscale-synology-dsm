# Tailscale Synology DSM 1.98.96-r3 release closeout

## Status

This is an unofficial downstream release record for the Tailscale Synology DSM package. It records a reviewed candidate only: no stable publication, release tag, production installation, root-bootstrap automation, firewall mutation, or reboot automation is authorised by this repository state. It does not imply support or endorsement by Tailscale or Synology.

## Release identity and integrity

| Field | Value |
| --- | --- |
| Upstream | `v1.98.9` at `6c167d40fa37aeb51afa7ff336730670ea4762bf` |
| r3 source commit/tree | `f49613eccf9350583cc328183f192a591cd76348` / `44c0bc3cd3bbcd3eb70cacf34e9611909a38bd10` |
| Release branch / intended tag | `release/v1.98.9-r3-synology` / `release/synology-v1.98.96-r3` |
| Required companion package | `iptables-netfilter-extensions >= 1.1.0-2` |

The source reconstruction is layered: the retained r2 58-patch base is applied once, followed by the seven r3 delta patches. Each layer has its own ordered inventory and SHA-256 manifest; applying both to the pinned upstream commit must reproduce the r3 tree. This avoids duplicating the r2 payloads in the r3 public export.

## Accepted artifacts

- Sideload: `tailscale-x86_64-1.98.96-700098098-dsm7.spk` — SHA-256 `a8323d98c318c210ce9c3c467ae6ece9a3bf3e13735ee77efc1b855820ddc41d`.
- Package Center reference: `tailscale-x86_64-1.98.96-720098098-dsm7-2.spk` — SHA-256 `9f507a8336471fe9990e94f7c23276ad5cb40c477d6f2a3763faa4d3f32b818c`.

The matching A/B builds for each artifact were byte-identical. Original payload inspection was performed at control commit `932c74d40db66304c04908cd0e287cdb5a357e36`. Canonical role-bound validation was first completed at `b9c9582acd1fdb6c02d0593610837e475da9b773`, after the inspector gained explicit sideload and Package Center reference bindings; this later validation head, rather than the original payload-inspection commit, is the applicable identity for role/name/SHA verification. The machine-readable evidence is under `tests/releases/v1.98.9-r3/`.

## Task 5 DSM 7.4.1 acceptance

Maintainer evidence supports the attended DSM 7.4.1 result: DSM-managed resource preservation, linked mutation rejection, outer bootstrap and manifest binding, a UID 0 runtime, root-owned target, no active transaction, LocalAPI and tailnet readiness, idempotent install, package restart, remove then re-bootstrap, attended reboot recovery, TUN, IPv4/IPv6 netfilter hooks, and functional network operation.

Task 5 hardens the privileged bootstrap trust boundary while retaining the required root runtime. It does not downgrade the package to the ordinary DSM package-user model.

## Deliberately untested scope and residual risk

Upgrade from r2, rollback, uninstall, and volume migration were not tested and are not claimed. The same-version package revision can also interact with DSM package caching; the artifact hash is the release discriminator. Manual review remains required before any tag, publication, deployment, or production action.

Sanitised records exclude workstation and host identifiers, local paths, tailnet or peer names, addresses, account identities, credentials, raw runtime transcripts, and filesystem inventories.
