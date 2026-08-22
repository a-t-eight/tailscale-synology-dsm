# Tests

Source-owned Synology regression tests remain under
`release/dist/synology/tests/` on each downstream release branch. They are not
duplicated on the control branch.

Control-branch test content records:

- patch-series round-trip validation;
- release asset and shell syntax audits;
- isolated shell regression results;
- SPK metadata and privilege-manifest inspection;
- NAS runtime and netfilter acceptance evidence.

`releases/validate-production-contract.sh` builds disposable local fixtures for
the accepted release identity. It distinguishes living accepted identity from
historical patch lineage, rejects structured metadata and evidence drift, and
does not inspect mutable build output.

## Release evidence

- `releases/v1.98.9/` — accepted validation evidence for the v1.98.9 Synology
  release.

Generated evidence must identify the exact tested release commit and include
checksums for retained logs and machine-readable results.
