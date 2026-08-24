# Pre-cleanup manifest: agent upgrade workflow

Date: 2026-08-23 (Australia/Sydney)

This manifest freezes the cleanup decision before any deletion. Cleanup is limited to exact targets whose retained equivalent and lack of unique product changes were verified. No NAS, remote, publication, tag, release, or dependency-SPK action is in scope.

## Implementation gate

- Feature branch: `codex/agent-upgrade-workflow`
- Feature worktree: `/home/ateight/development/tailscale-synology-unjailed/tailscale-synology-agent-upgrade-workflow`
- Pre-cleanup feature HEAD: `20899f9110a389a611c5557af07ccbf511eb02d6`
- Follow-up alias-cleanup feature HEAD: `0c8d38579085ca4e1419b51471be41cb76df5c92`
- Clean candidate base: `8c9fe5239ee57a89ce687fc8c7608d3df91f6ede`
- The focused preparation tests, all Synology shell tests, offline relevant Go tests, shell syntax and static analysis, canonical patch checksum, historical checksum inventory, and accepted-source round trip passed before cleanup.
- The canonical seven protected blobs were unchanged from the candidate before cleanup.

## Keep

The following are retained without modification:

- Accepted source/base worktree and branch:
  `/home/ateight/development/tailscale-synology-unjailed/tailscale-synology-dsm`, `release/v1.98.9-synology`, `20c86229955a3d03de01901aee1499cab87c571d`.
- Clean r2 candidate worktree and branch:
  `/home/ateight/development/tailscale-synology-unjailed/tailscale-synology-dsm-r2`, `work/release-v1.98.9-synology-r2`, `8c9fe5239ee57a89ce687fc8c7608d3df91f6ede`.
- Control worktree and branch:
  `/home/ateight/development/tailscale-synology-unjailed/tailscale-synology-dsm-control`, `synology/main`, `891f03cea97aaa06009e9f8d7ee7494b7e1e4340`.
- Contract worktree and branch:
  `/home/ateight/development/tailscale-synology-unjailed/tailscale-synology-dsm-contract`, `governance/accepted-production-contract`, `e6cc919d7fc5ee35e14bb1aa56d33ec782c2c016`.
- This feature worktree and branch, the complete shared Git history, canonical patches and checksums, release manifests and scripts, tests, runbooks, contracts, accepted SPKs, and current-release build evidence.
- The Mac planning checkout, which is outside this cleanup and must not be touched.

## Remove

Only these exact targets are approved for removal:

1. `/home/ateight/development/tailscale-synology-unjailed/evidence/tailscale-r2-isolated-gocross-20260822T013718Z`
2. `/home/ateight/development/tailscale-synology-unjailed/evidence/tailscale-r2-isolated-gocross-20260822T020519Z`
3. `/home/ateight/development/tailscale-synology-unjailed/synology-netfilter-v1.98.9.patch`
4. `/home/ateight/development/tailscale-synology-unjailed/synology-netfilter-v1.98.9.patch.sha256`
5. `/tmp/ts-r2-preflight.L5rExv/.r2-candidate.env.task7-8c9fe5239ee57a89ce687fc8c7608d3df91f6ede.tmp`
6. `/tmp/ts-r2-preflight.L5rExv/.r2-candidate.env.sha256.task7-8c9fe5239ee57a89ce687fc8c7608d3df91f6ede.tmp`
7. `/home/ateight/development/tailscale-synology-unjailed/evidence/.validation-continuation-failure-manifest.e1IIc1`

The first two targets are registered detached Git worktrees. They will be removed with Git's worktree command, then stale administrative entries will be pruned. The final two targets are redundant workspace-root copies, not tracked files in the feature worktree.

## Removal proof

For each detached evidence worktree:

- detached HEAD is `20c86229955a3d03de01901aee1499cab87c571d`;
- the index is byte-for-byte equal to candidate tree `8c9fe5239ee57a89ce687fc8c7608d3df91f6ede` (`git diff --cached --quiet` succeeded);
- the working tree equals the index (`git diff --quiet` succeeded);
- there are zero untracked files; and
- the only staged paths relative to the accepted source are the same five candidate paths:
  `release/dist/synology/files/PKG_DEPS`,
  `release/dist/synology/package_revision.go`,
  `release/dist/synology/pkgs.go`,
  `release/dist/synology/pkgs_test.go`, and
  `tool/build-synology-root-bootstrap.sh`.

Consequently, neither detached worktree contains a unique product change. Its complete tree remains available through the retained candidate commit and r2 worktree.

For the redundant patch copies:

- workspace-root patch size: 6,781 bytes;
- canonical `patches/v1.98.9/synology-netfilter.patch` size: 6,781 bytes;
- both patch SHA-256 values: `ad577d4032e3c14fa37b284b7e5116c364122471b1d9fdc2c906bf8ae198920f`;
- the root checksum file records that same digest for the root basename;
- canonical checksum file SHA-256: `b0a7641e8297c79ea2c40ffddc82632cfbdaf83029b4552e42572b227a2b7fe4`;
- root checksum file SHA-256: `69e55e7e72229178c3d1fbb473aaddec7850c381cbf4505c8f09b2949397a629`.

The checksum files differ only because they name different patch basenames. The canonical in-repository patch and checksum will remain tracked and will be revalidated after deletion.

For the three follow-up aliases, the pre-removal checks required both paths to
be ordinary non-symlink files, the alias to have exactly two links, matching
device/inode values, byte equality, and the recorded SHA-256:

- 1,160-byte alias at device/inode `77:425497`, two links, SHA-256
  `1473ef559f4a3196cdd6f9ac4a943527aafd1b708053b9c6518e5e5ef262403a`;
  retained peer: `/tmp/ts-r2-preflight.L5rExv/r2-candidate.env`.
- 111-byte alias at device/inode `77:425588`, two links, SHA-256
  `4acf168a463b9e224372fff91174770ff6e06b5cebcf8301be3a4282282a4f3c`;
  retained peer: `/tmp/ts-r2-preflight.L5rExv/r2-candidate.env.sha256`.
- 26,979-byte alias at device/inode `2096:735675`, two links, SHA-256
  `4ba2e44179ea2454a78bb9c79c0093dc92a8d01aa74bc6a5d16b4dcbc7403de3`;
  retained peer:
  `/home/ateight/development/tailscale-synology-unjailed/evidence/tailscale-r2-validation-continuation-20260822T041553Z/SHA256SUMS.validation-continuation.failure`.

Deleting one hard-link name leaves the retained peer and its bytes recoverable
at the named path. No other path is approved by this follow-up cleanup.

## Retained as ambiguous

No authoritative exact enumeration proves that the following historical or temporary-looking roots are abandoned without unique accepted-release evidence. They are therefore deliberately retained:

- `/tmp/ts-r2-preflight.L5rExv` and other Tailscale/Synology temporary roots under `/tmp`;
- `/home/ateight/development/tailscale-synology-unjailed/evidence/sdd-r2-controller`;
- `/home/ateight/development/tailscale-synology-unjailed/evidence/tailscale-r2-license-header-correction-controller-20260822T072104Z`;
- `/home/ateight/development/tailscale-synology-unjailed/archive/codex-execution-scripts`;
- workspace reconciliation roots matching `.tailscale-synology-v1.98.9-reconcile-*`; and
- finalization, recovery, preflight, controller, correction, and evidence directories not named in the approved removal list above.

These targets may contain durable audit, controller, recovery, or build evidence. A later cleanup may remove them only after an explicit target list and uniqueness review.

## Exact retained and ambiguous root inventory

Directory identities below are `device:inode`; their byte sizes are current
`du -sb` totals. File identities are SHA-256. None is a registered Git
worktree. `AMBIGUOUS` means no byte/tree-equivalent retained replacement was
proved, so the path is retained without modification. The build-output root is
`KEEP` because it contains accepted current-release evidence.

```text
Decision   Type/bytes             Identity                                                         Absolute path
KEEP       directory/442749660    2096:21625                                                       /home/ateight/development/tailscale-synology-unjailed/tailscale-synology-build-output
AMBIGUOUS  directory/664350133    2096:229945                                                      /home/ateight/development/tailscale-synology-unjailed/go
AMBIGUOUS  directory/482249       2096:2009                                                        /home/ateight/development/tailscale-synology-unjailed/.tailscale-synology-v1.98.9-reconcile-20260726-161554
AMBIGUOUS  directory/3290019      2096:296844                                                      /home/ateight/development/tailscale-synology-unjailed/archive/codex-execution-scripts
AMBIGUOUS  file/1256              81ec4b8c3cd3df4f3c66c5a1cd3dc98d769e98a054fdd69542abd0a861e720a0 /home/ateight/development/tailscale-synology-unjailed/tailscale-synology-dsm-init.sh
AMBIGUOUS  file/482               3c42a6bc75430f9ac41944103469c04087eebb3036ea7a1c78986ab241b0a5f5 /home/ateight/development/tailscale-synology-unjailed/tailscale-synology-dsm-init-branch.sh
AMBIGUOUS  file/770               ac3a8e707376ac03a9917644ff85136f95add239d7335d13adaf4e350ceee616 /home/ateight/development/tailscale-synology-unjailed/tailscale-synology-blocker-audit.sh
AMBIGUOUS  file/5265              ad6d3604c0feb1ee242ded78b5aeca06fd073c7ce98971fe265876d12c1f839d /home/ateight/development/tailscale-synology-unjailed/tailscale-synology-netfilter-v1.98.9.patch
AMBIGUOUS  directory/129342       2096:317539                                                      /home/ateight/development/tailscale-synology-unjailed/evidence/sdd-r2-controller
AMBIGUOUS  directory/8043         2096:321092                                                      /home/ateight/development/tailscale-synology-unjailed/evidence/tailscale-r2-20260821T162854Z
AMBIGUOUS  directory/12882        2096:321105                                                      /home/ateight/development/tailscale-synology-unjailed/evidence/tailscale-r2-20260821T163635Z
AMBIGUOUS  directory/31580428     2096:371315                                                      /home/ateight/development/tailscale-synology-unjailed/evidence/tailscale-r2-20260821T181240Z
AMBIGUOUS  directory/663916117    2096:735681                                                      /home/ateight/development/tailscale-synology-unjailed/evidence/tailscale-r2-evidence-finalization-20260822T045906Z
AMBIGUOUS  directory/663998564    2096:735961                                                      /home/ateight/development/tailscale-synology-unjailed/evidence/tailscale-r2-evidence-finalization-recovery-20260822T052259Z
AMBIGUOUS  directory/664112746    2096:736249                                                      /home/ateight/development/tailscale-synology-unjailed/evidence/tailscale-r2-evidence-finalization-recovery2-20260822T054049Z
AMBIGUOUS  directory/664299927    2096:736551                                                      /home/ateight/development/tailscale-synology-unjailed/evidence/tailscale-r2-evidence-finalization-recovery3-20260822T061553Z
AMBIGUOUS  directory/1506677429   2096:6215                                                        /home/ateight/development/tailscale-synology-unjailed/evidence/tailscale-r2-isolated-gocross-cache-20260822T013718Z
AMBIGUOUS  directory/1506676875   2096:561764                                                      /home/ateight/development/tailscale-synology-unjailed/evidence/tailscale-r2-isolated-gocross-cache-20260822T020519Z
AMBIGUOUS  directory/126197921    2096:644195                                                      /home/ateight/development/tailscale-synology-unjailed/evidence/tailscale-r2-isolated-gocross-clone-20260822T024416Z
AMBIGUOUS  directory/2672323490   2096:644187                                                      /home/ateight/development/tailscale-synology-unjailed/evidence/tailscale-r2-isolated-gocross-clone-cache-20260822T024416Z
AMBIGUOUS  directory/43711        2096:736885                                                      /home/ateight/development/tailscale-synology-unjailed/evidence/tailscale-r2-license-header-correction-controller-20260822T072104Z
AMBIGUOUS  directory/51666005     2096:285350                                                      /home/ateight/development/tailscale-synology-unjailed/evidence/tailscale-r2-prefetch-build-20260821T200409Z
AMBIGUOUS  directory/642944759    2096:728739                                                      /home/ateight/development/tailscale-synology-unjailed/evidence/tailscale-r2-standalone-build-20260822T032526Z
AMBIGUOUS  directory/648671944    2096:321199                                                      /home/ateight/development/tailscale-synology-unjailed/evidence/tailscale-r2-tool-cache-20260821T175508Z
AMBIGUOUS  directory/657478557    2096:295424                                                      /home/ateight/development/tailscale-synology-unjailed/evidence/tailscale-r2-tool-cache-prefetch-20260821T194434Z
AMBIGUOUS  directory/1781756062   2096:396539                                                      /home/ateight/development/tailscale-synology-unjailed/evidence/tailscale-r2-tool-cache-prefetch-20260821T195426Z
AMBIGUOUS  directory/661115140    2096:346246                                                      /home/ateight/development/tailscale-synology-unjailed/evidence/tailscale-r2-tool-cache-recovery-20260821T181048Z
AMBIGUOUS  directory/663916117    2096:735255                                                      /home/ateight/development/tailscale-synology-unjailed/evidence/tailscale-r2-validation-continuation-20260822T041553Z
```

The current `/tmp` roots and files in plan scope are also individually retained:

```text
Decision   Type/bytes            Identity                                                         Absolute path
AMBIGUOUS  directory/649644235   77:509136                                                        /tmp/tailscale-agent-upgrade-go-cache
AMBIGUOUS  file/160              23d8836e3540299d5669b60701d8aca47de1724f4f63b2e29ccec64461c3569a /tmp/tailscale-hook-direct.stderr
AMBIGUOUS  file/0                e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855 /tmp/tailscale-hook-direct.stdout
AMBIGUOUS  directory/33910       77:528771                                                        /tmp/tailscale-hook-review.rwtohi
AMBIGUOUS  file/0                e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855 /tmp/tailscale-shellcheck-error.stderr
AMBIGUOUS  file/0                e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855 /tmp/tailscale-shellcheck-error.stdout
AMBIGUOUS  file/0                e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855 /tmp/tailscale-shellcheck-excluded.stderr
AMBIGUOUS  file/0                e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855 /tmp/tailscale-shellcheck-excluded.stdout
AMBIGUOUS  file/0                e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855 /tmp/tailscale-shellcheck-path.stderr
AMBIGUOUS  file/551              e9c0310856219e61c28c9b18bcde570d00fc08a4daff881211d0fb7fe2e8cb4e /tmp/tailscale-shellcheck-path.stdout
AMBIGUOUS  file/0                e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855 /tmp/tailscale-shellcheck-plain.stderr
AMBIGUOUS  file/551              e9c0310856219e61c28c9b18bcde570d00fc08a4daff881211d0fb7fe2e8cb4e /tmp/tailscale-shellcheck-plain.stdout
AMBIGUOUS  file/264              970b71648a2cf73415a4d0f3bd0737816639f37791e4343854cde167ac5f62c8 /tmp/tailscale-shellcheck-scriptdir.stdout
AMBIGUOUS  directory/169643      77:130686                                                        /tmp/tailscale-synology-cache-fix-round2-20260821T072028Z
AMBIGUOUS  directory/118117      77:147966                                                        /tmp/tailscale-synology-cache-fix-round3-20260821T074200Z
AMBIGUOUS  directory/47044       77:304764                                                        /tmp/tailscale-synology-json-standards-20260821TAjlSlH
AMBIGUOUS  directory/78566       77:261788                                                        /tmp/tailscale-synology-parser-fix-20260821T2eGSkR
AMBIGUOUS  directory/49271       77:101925                                                        /tmp/tailscale-synology-task6-20260821T062314Z
AMBIGUOUS  directory/248801      77:107729                                                        /tmp/tailscale-synology-task6-remediation-20260821T063749Z
AMBIGUOUS  directory/234420      77:161925                                                        /tmp/tailscale-synology-task6-retry-20260821T075301Z
AMBIGUOUS  directory/297941      77:194101                                                        /tmp/tailscale-synology-whole-commit-fix-20260821TJAQeVmID
AMBIGUOUS  file/59               351484cdc58fca438297bdef10137aaaed784ba882cf4afe5090c77c6a06ef20 /tmp/tailscale-synology-whole-commit-fix-current
AMBIGUOUS  directory/4551        77:20675                                                         /tmp/tailscale-synology-worktree-repair-20260821T044857Z
AMBIGUOUS  directory/352498      77:383156                                                        /tmp/ts-r2-preflight.L5rExv
AMBIGUOUS  directory/18674       77:385520                                                        /tmp/ts-r2-task-2.knck4m
AMBIGUOUS  directory/3508        77:386602                                                        /tmp/ts-r2-task-3.JFO1vx
AMBIGUOUS  directory/14774       77:397099                                                        /tmp/ts-r2-task-4-fix1.yGxuu4
AMBIGUOUS  directory/15399       77:387890                                                        /tmp/ts-r2-task-4.C6zM2v
AMBIGUOUS  directory/4822        77:406002                                                        /tmp/ts-r2-task-5.rh9smH
AMBIGUOUS  directory/40436       77:422950                                                        /tmp/ts-r2-validation-proof.0wbyDP
```
