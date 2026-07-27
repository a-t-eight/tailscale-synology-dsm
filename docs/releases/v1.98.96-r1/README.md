# Tailscale Synology DSM 1.98.96-r1 release closeout

## Status

The `1.98.96-r1` Synology DSM downstream release has completed source,
package, reproducibility and production runtime acceptance.

This record closes the release-validation phase. The signed release commit and
its canonical patch artefacts remain authoritative.

## Release identity

| Field | Value |
| --- | --- |
| Upstream Tailscale release | `v1.98.9` |
| Synology package version | `1.98.96-700098096` |
| Release revision | `r1` |
| Final release commit | `20c86229955a3d03de01901aee1499cab87c571d` |
| Final release tree | `6d022c18f27a42aab553697c69c852bebd8594b8` |
| Integration branch | `synology/main` |
| Release branch | `release/v1.98.9-synology` |
| Target platform | Synology DSM 7, `x86_64` |
| Minimum DSM version | `7.3-81180` |

## Release package

The production-accepted sideload package is:

```text
tailscale-x86_64-1.98.96-700098096-dsm7.spk
```

SHA-256:

```text
bed218b4d0099102e9c3be18456d8a94be9a92b4a29295a9dab33932570cbce0
```

The separately generated Package Center reference package has SHA-256:

```text
6e01fb115dd15cd922d89bafb5d516d87533d33dda3bd4c0e70cd45f4d77c817
```

The sideload and Package Center packages intentionally differ because their
package metadata and installation roles differ. Repeated builds of each
corresponding package variant were byte-for-byte reproducible.

## Source validation

Validation was performed from a clean detached worktree at the final release
commit.

The final source passed:

- Go package tests for `release/dist` and `release/dist/synology`;
- shell syntax validation for all 14 inventoried Synology-specific shell
  assets;
- validation that the worktree remained clean after testing.

The permanent source evidence is stored under:

```text
tests/releases/v1.98.9/source-validation/
```

The complete Synology release-asset inventory is:

```text
tests/releases/v1.98.9/release-assets.tsv
```

## Shell regression validation

All eight source-owned regression tests under:

```text
release/dist/synology/tests/
```

passed from the clean detached release worktree.

Recorded results:

- test scripts discovered: 8;
- test scripts passed: 8;
- individual assertions passed: 32;
- timed-out tests: 0;
- worktree modifications: 0.

The machine-readable result is stored at:

```text
tests/releases/v1.98.9/shell-regression/summary.json
```

## Reproducible-build validation

Two independent builds from the final release commit produced byte-for-byte
identical outputs for each corresponding package variant.

The release builder used:

```text
SOURCE_DATE_EPOCH=1785030856
```

The resulting package metadata used:

```text
INFO create_time=20260726-01:54:16 UTC
```

Recorded reproducibility checks:

- outer tar timestamp mismatches: 0;
- inner tar timestamp mismatches: 0;
- gzip header modification time: 0;
- sideload package rebuilds: identical;
- Package Center reference rebuilds: identical.

Portable build provenance is stored under:

```text
tests/releases/v1.98.9/reproducible-build/
```

## DSM production runtime acceptance

The final sideload package passed production runtime acceptance on:

- Synology DS920+;
- DSM 7.3.2;
- `x86_64`;
- final release commit
  `20c86229955a3d03de01901aee1499cab87c571d`.

Acceptance confirmed that:

- DSM accepted the package as a same-version upgrade;
- the installed binaries changed to the final release commit;
- persistent Tailscale state remained byte-identical;
- node identity and Tailscale addressing were preserved;
- retained routing preferences were preserved;
- the expected post-upgrade root-bootstrap approval became stale;
- administrator bootstrap re-approval completed successfully;
- `tailscaled` ran as UID 0 with the expected executable and arguments;
- the netfilter reconciler ran with the expected script;
- LocalAPI access was operational;
- `filter/ts-input` was present;
- `filter/ts-forward` was present;
- `nat/ts-postrouting` was present.

The reusable runtime validator is:

```text
scripts/nas/validate-synology-runtime.sh
```

It validates processes through package PID files and
`/proc/<pid>/cmdline`, avoiding DSM's incomplete `ps w` process view.

Sanitised runtime evidence and source-archive provenance are stored under:

```text
tests/releases/v1.98.9/dsm-runtime/
```

The full source runtime archive remains outside Git because it contains
tailnet-specific status, preferences, host inventory and detailed runtime
logs. The repository retains its SHA-256 digest, complete source manifest,
transfer verification and selected sanitised evidence.

## Evidence index

The top-level release evidence record is:

```text
tests/releases/v1.98.9/README.md
```

The evidence checksum manifest is:

```text
tests/releases/v1.98.9/SHA256SUMS
```

Principal evidence locations:

```text
tests/releases/v1.98.9/release-assets.tsv
tests/releases/v1.98.9/source-validation/
tests/releases/v1.98.9/shell-regression/
tests/releases/v1.98.9/reproducible-build/
tests/releases/v1.98.9/dsm-runtime/
```

## Release closeout decision

The `1.98.96-r1` release is accepted as the completed downstream Synology DSM
release for the pinned Tailscale `v1.98.9` source baseline.

No further functional changes belong on the closed release branch. Any future
code change must be developed and validated separately, then incorporated
through a new release revision or a newer pinned upstream release.

This documentation record does not replace:

- the signed release commit;
- the canonical release branch;
- the canonical patch series;
- package checksums;
- machine-readable validation evidence.

Those artefacts remain the source of truth for reproduction and verification.
