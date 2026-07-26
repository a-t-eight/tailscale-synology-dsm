# v1.98.9 release validation evidence

This directory records validation performed against the final signed Synology
release commit:

`20c86229955a3d03de01901aee1499cab87c571d`

Release tree:

`6d022c18f27a42aab553697c69c852bebd8594b8`

## Release asset audit

`release-assets.tsv` inventories the 14 Synology-specific shell test, runtime
and build-helper assets from the final release tree. It records Git mode, byte
size, line count, SHA-256 digest, shebang and repository path.

Syntax-only validation passed for all 14 assets. Detailed syntax results are
stored in `source-validation/shell-syntax.tsv`.

## Source validation

The final release source passed:

- Go package tests for `release/dist` and `release/dist/synology`;
- shell syntax validation for all 14 inventoried assets;
- a clean-worktree check after all validation.

## Shell regression suite

The eight source-owned tests under `release/dist/synology/tests/` were executed
from the clean detached final-release worktree.

- Test scripts discovered: 8
- Test scripts passed: 8
- Individual assertions passed: 32
- Timed-out tests: 0
- Worktree modifications: 0

`shell-regression/summary.json` is the machine-readable runner result. Its log paths are relative
to this evidence directory.

## Reproducible build

Two independent builds from the same signed commit produced byte-for-byte
identical packages.

- Sideload SHA-256: `bed218b4d0099102e9c3be18456d8a94be9a92b4a29295a9dab33932570cbce0`
- Package Center reference SHA-256: `6e01fb115dd15cd922d89bafb5d516d87533d33dda3bd4c0e70cd45f4d77c817`
- SOURCE_DATE_EPOCH: `1785030856`
- INFO create_time: `20260726-01:54:16` UTC
- Outer tar timestamp mismatches: 0
- Inner tar timestamp mismatches: 0
- gzip header mtime: 0

`reproducible-build/manifest.json` is portable release provenance.
`reproducible-build/source/` preserves the original local build logs,
environment record, manifest and checksums.

## DSM runtime acceptance

Production runtime acceptance on a Synology DS920+ running DSM 7.3.2
passed for the final release commit.

- DSM accepted the exact same package version as an upgrade.
- Persistent identity, addressing, state and preferences were preserved.
- The required post-upgrade administrator bootstrap refresh passed.
- tailscaled and the netfilter reconciler were validated through PID files
  and /proc command lines.
- Required Tailscale filter and NAT chains were present.

Portable evidence and source-archive provenance are retained under
`dsm-runtime/`.

These evidence files do not replace the signed release branch or canonical
patch artefacts. The release commit remains authoritative.
