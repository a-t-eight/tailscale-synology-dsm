# Tailscale Synology DSM 1.98.96-r2 evidence index

This directory indexes the reviewed source, reproducible package, regression,
and DSM 7.4.1 acceptance evidence for the r2 release. Large package artifacts,
raw build logs, and the operator's runtime transcript remain outside Git.

## Release identity

- upstream: `v1.98.9` at
  `6c167d40fa37aeb51afa7ff336730670ea4762bf`;
- release branch: `release/v1.98.9-r2-synology`;
- release commit: `0fad8b81a3e0eb86c457bc79c474bcc213834c43`;
- release tree: `33f5c5927ae4db54b9d582650ed31cc6a2eb7161`;
- sideload package: `tailscale-x86_64-1.98.96-700098097-dsm7.spk`;
- sideload SHA-256:
  `f947a1747521c50edf49baf597cc18b512b3bb009c3b7afe963fa326ef2d6c16`.

## Evidence

- `source-validation/summary.json` records signed history, patch round-trip,
  focused Go/shell validation, and required GitHub checks.
- `shell-regression/summary.json` records the eight Synology shell programs and
  41 passing assertions.
- `reproducible-build/manifest.json` records the two byte-identical builds of
  each package variant.
- `dsm-runtime/` records the privacy-reviewed abbreviated acceptance that binds
  the final CI-only revision to the installed executables and root runtime.
- `release-assets.tsv` records package roles and checksums.

The sealed source review bundle is identified by
`tailscale-synology-review-v1.98.9-r2-dsm741-ci-fix-0fad8b81`; its
`SHA256SUMS` digest is
`ec0ed1ec021175b5c3882b19a0e7935091c7d103a1a660209b96a26d4fd2244e`.

The independent build evidence is identified by
`tailscale-r2-ci-fix-0fad8b81-20260824T170600Z`. All four package checksum
manifests were verified and corresponding build-A/build-B package bytes were
compared directly.

## Scope

The preceding functional revision completed the broader DSM 7.4.1 bootstrap
and networking UAT. The final commit changes CI only, but changes the embedded
Git identity; it therefore received abbreviated exact-artifact identity and
startup acceptance. No second reboot test is claimed for that CI-only revision.
