# Tailscale Synology DSM 1.98.96-r2 release closeout

## Status

The `1.98.96-r2` Synology DSM downstream release has completed source,
package, reproducibility and DSM 7.4.1 runtime acceptance.

The release is accepted for production. Stable GitHub publication remains a
human-maintainer action; this record does not claim that the release tag or
release page has been published.

## Release identity

| Field | Value |
| --- | --- |
| Upstream Tailscale release | `v1.98.9` |
| Synology package version | `1.98.96-700098097` |
| Release revision | `r2` |
| Final release commit | `0fad8b81a3e0eb86c457bc79c474bcc213834c43` |
| Final release tree | `33f5c5927ae4db54b9d582650ed31cc6a2eb7161` |
| Integration branch | `synology/main` |
| Release branch | `release/v1.98.9-r2-synology` |
| Intended signed tag | `release/synology-v1.98.96-r2` |
| Target platform | Synology DSM 7, `x86_64` |
| Minimum DSM version | `7.3-86009` |

## Release packages

The production-accepted sideload package is:

```text
tailscale-x86_64-1.98.96-700098097-dsm7.spk
```

SHA-256:

```text
f947a1747521c50edf49baf597cc18b512b3bb009c3b7afe963fa326ef2d6c16
```

The independently generated Package Center reference package is:

```text
tailscale-x86_64-1.98.96-720098097-dsm7-2.spk
```

SHA-256:

```text
d51dd54def1015bee1c6011a4be7aa6d9b5c9d19b440292276347f861c7d071e
```

The variants intentionally differ because they have different package roles.
Two independent builds of each corresponding variant were byte-for-byte
identical.

## Source and patch validation

The final source history contains 58 downstream commits. All 58 commits have
valid SSH signatures and exactly one matching `Signed-off-by` trailer.

The retained 58-file mail patch series applied cleanly to the pinned upstream
commit and reproduced the exact final release tree. Required GitHub checks
passed for the exact release commit, including the focused Synology product
gate, lint, vet and lock-file validation.

Evidence is stored at:

```text
tests/releases/v1.98.9-r2/source-validation/summary.json
patches/v1.98.9-r2/
```

## Regression and reproducibility validation

All eight Synology shell regression programs passed, covering 41 assertions
with no timeout. The release assets were built twice from the exact release
commit, and corresponding outputs were byte-for-byte identical.

Evidence is stored at:

```text
tests/releases/v1.98.9-r2/shell-regression/summary.json
tests/releases/v1.98.9-r2/reproducible-build/manifest.json
tests/releases/v1.98.9-r2/release-assets.tsv
```

## DSM 7.4.1 runtime acceptance

The accepted sideload artifact was installed and exercised on a Synology
DS920+ running DSM 7.4.1. Final exact-artifact checks confirmed:

- Synology Package Manager reported the package running;
- both installed Tailscale binaries reported release commit
  `0fad8b81a3e0eb86c457bc79c474bcc213834c43`;
- installed binary hashes matched the independently inspected SPK;
- privilege mode was `root`;
- bootstrap state was `current`;
- the runtime was running as UID 0;
- steady-state tailnet operation succeeded after the normal startup
  transition.

The final source change was CI-only. It received abbreviated exact-artifact
identity and startup acceptance after the preceding functional revision had
completed the broader DSM 7.4.1 bootstrap and networking UAT. No second reboot
test is claimed for the CI-only revision.

Sanitised evidence is stored at:

```text
tests/releases/v1.98.9-r2/dsm-runtime/
```

The operator retains the raw runtime transcript outside Git. Repository
evidence excludes hostnames, tailnet names, addresses, peer inventory, account
names, credentials and private keys.

## Evidence provenance

The independent build evidence is identified by:

```text
tailscale-r2-ci-fix-0fad8b81-20260824T170600Z
```

The sealed source review bundle is identified by:

```text
tailscale-synology-review-v1.98.9-r2-dsm741-ci-fix-0fad8b81
```

Its `SHA256SUMS` digest is:

```text
ec0ed1ec021175b5c3882b19a0e7935091c7d103a1a660209b96a26d4fd2244e
```

## Release closeout decision

The `1.98.96-r2` release is the accepted production revision for the pinned
Tailscale `v1.98.9` source baseline. Revision r1 remains retained as superseded
history.

No further functional change belongs on the accepted r2 release branch. A
future code change must use a new release revision or a newer pinned upstream
baseline and repeat the applicable validation gates.

This record does not replace the signed release commit, canonical branch,
canonical patch series, package checksums or machine-readable evidence. Those
artifacts remain authoritative.
