# v1.98.9 release validation evidence

This directory records validation performed against the accepted Synology
release commit:

`cc5d96275e9dd76fd8a4f38209a2df91199a425c`

## Release asset audit

`release-assets.tsv` inventories the 14 Synology-specific test, runtime and build
assets from the release tree. It records Git mode, byte size, line count,
SHA-256 digest, shebang and repository path.

Syntax-only validation passed for all 14 assets.

## Shell regression suite

The eight source-owned tests under `release/dist/synology/tests/` were executed
from a clean detached worktree at the accepted release commit.

- Test scripts discovered: 8
- Test scripts passed: 8
- Individual assertions passed: 32
- Timed-out tests: 0
- Worktree modifications: 0

`summary.json` is the machine-readable runner result. Its log paths are
relative to this evidence directory. `logs/` contains the complete output
from each test.

These evidence files do not replace the source-owned tests. The release commit
and canonical patch artifacts remain authoritative.
