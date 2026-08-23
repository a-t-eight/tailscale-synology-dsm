# Post-cleanup inventory: agent upgrade workflow

Date: 2026-08-23 (Australia/Sydney)

Cleanup followed the original committed pre-cleanup manifest at `993f77a4fa18b4246bb4dc5ce6632968c92c5e62` and the exact follow-up inventory at `89c8676e39e1273041926f0e569f7b8029e8a7e1`. No target outside their exact removal lists was deleted.

## Removed

The following exact targets are absent:

- `/home/ateight/development/tailscale-synology-unjailed/evidence/tailscale-r2-isolated-gocross-20260822T013718Z`
- `/home/ateight/development/tailscale-synology-unjailed/evidence/tailscale-r2-isolated-gocross-20260822T020519Z`
- `/home/ateight/development/tailscale-synology-unjailed/synology-netfilter-v1.98.9.patch`
- `/home/ateight/development/tailscale-synology-unjailed/synology-netfilter-v1.98.9.patch.sha256`
- `/tmp/ts-r2-preflight.L5rExv/.r2-candidate.env.task7-8c9fe5239ee57a89ce687fc8c7608d3df91f6ede.tmp`
- `/tmp/ts-r2-preflight.L5rExv/.r2-candidate.env.sha256.task7-8c9fe5239ee57a89ce687fc8c7608d3df91f6ede.tmp`
- `/home/ateight/development/tailscale-synology-unjailed/evidence/.validation-continuation-failure-manifest.e1IIc1`

Git administrative records for the removed worktrees were pruned. Their trees remain recoverable from candidate commit `8c9fe5239ee57a89ce687fc8c7608d3df91f6ede`; the redundant patch remains recoverable from the retained tracked canonical copy. Each follow-up hard-link alias is recoverable by recreating a link to its retained peer below.

## Follow-up alias post-state

All three removed names are absent. Their ordinary non-symlink retained peers
are unchanged byte-for-byte and now have one link:

```text
Type/bytes  Device:inode  Links  SHA-256                                                          Retained path
file/1160   77:425497     1      1473ef559f4a3196cdd6f9ac4a943527aafd1b708053b9c6518e5e5ef262403a  /tmp/ts-r2-preflight.L5rExv/r2-candidate.env
file/111    77:425588     1      4acf168a463b9e224372fff91174770ff6e06b5cebcf8301be3a4282282a4f3c  /tmp/ts-r2-preflight.L5rExv/r2-candidate.env.sha256
file/26979  2096:735675   1      4ba2e44179ea2454a78bb9c79c0093dc92a8d01aa74bc6a5d16b4dcbc7403de3  /home/ateight/development/tailscale-synology-unjailed/evidence/tailscale-r2-validation-continuation-20260822T041553Z/SHA256SUMS.validation-continuation.failure
```

The parent `/tmp/ts-r2-preflight.L5rExv` remains 352,498 bytes by `du -sb`;
the retained validation-continuation root remains 663,916,117 bytes. No
containing directory was removed.

## Registered worktrees retained

1. Accepted source: `/home/ateight/development/tailscale-synology-unjailed/tailscale-synology-dsm`, branch `release/v1.98.9-synology`, HEAD `20c86229955a3d03de01901aee1499cab87c571d`.
2. Feature: `/home/ateight/development/tailscale-synology-unjailed/tailscale-synology-agent-upgrade-workflow`, branch `codex/agent-upgrade-workflow`, pre-inventory HEAD `993f77a4fa18b4246bb4dc5ce6632968c92c5e62`.
3. Contract: `/home/ateight/development/tailscale-synology-unjailed/tailscale-synology-dsm-contract`, branch `governance/accepted-production-contract`, HEAD `e6cc919d7fc5ee35e14bb1aa56d33ec782c2c016`.
4. Control: `/home/ateight/development/tailscale-synology-unjailed/tailscale-synology-dsm-control`, branch `synology/main`, HEAD `891f03cea97aaa06009e9f8d7ee7494b7e1e4340`.
5. Clean r2 candidate: `/home/ateight/development/tailscale-synology-unjailed/tailscale-synology-dsm-r2`, branch `work/release-v1.98.9-synology-r2`, HEAD `8c9fe5239ee57a89ce687fc8c7608d3df91f6ede`.

There are no remaining registered detached evidence worktrees.

## Canonical release assets retained

- `patches/v1.98.9/synology-netfilter.patch`: SHA-256 `ad577d4032e3c14fa37b284b7e5116c364122471b1d9fdc2c906bf8ae198920f`.
- `patches/v1.98.9/synology-netfilter.patch.sha256`: SHA-256 `b0a7641e8297c79ea2c40ffddc82632cfbdaf83029b4552e42572b227a2b7fe4`.
- The canonical checksum validation reports `synology-netfilter.patch: OK`.
- A path-restricted diff confirms the canonical patch, its checksum, and the five core unjailed source files remain unchanged from candidate `8c9fe5239ee57a89ce687fc8c7608d3df91f6ede`.

The source/base, r2 candidate, control, contract, feature branch and worktree, Git history, canonical patch/tests/release assets, accepted SPKs, and accepted current-release build evidence remain in place.

## Ambiguous targets retained

The pre-cleanup manifest's ambiguous targets were not modified. Confirmed retained examples include:

- `/tmp/ts-r2-preflight.L5rExv`
- `/home/ateight/development/tailscale-synology-unjailed/evidence/sdd-r2-controller`
- `/home/ateight/development/tailscale-synology-unjailed/evidence/tailscale-r2-license-header-correction-controller-20260822T072104Z`
- `/home/ateight/development/tailscale-synology-unjailed/archive/codex-execution-scripts`

This is a complete reconciliation, not a sample-only decision: every non-target
path individually enumerated under `Exact retained and ambiguous root
inventory` in follow-up pre-cleanup commit
`89c8676e39e1273041926f0e569f7b8029e8a7e1` remains present at the same absolute
path, with the same type and recorded file SHA-256 or directory device/inode.
Its `KEEP` or `AMBIGUOUS` decision is unchanged. The only content-level change
inside an inventoried root is removal of the two approved hard-link names from
`/tmp/ts-r2-preflight.L5rExv`; its retained peers and total `du -sb` size are
unchanged because the bytes were already shared.

The Mac planning checkout was not touched. No NAS, remote, push, pull request, tag, release, publication, installation, or dependency-SPK build action occurred.
