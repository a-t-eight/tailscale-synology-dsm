# Tailscale Synology DSM patch set for v1.98.9

## Authoritative source

The signed downstream commit stack on
`release/v1.98.9-synology` is authoritative.

- Upstream base: `6c167d40fa37aeb51afa7ff336730670ea4762bf`
- Production tip: `20c86229955a3d03de01901aee1499cab87c571d`
- Production tree: `6d022c18f27a42aab553697c69c852bebd8594b8`

## Artifacts

### `maintenance.patch`

Recommended cumulative patch for future maintenance and upstream adaptation.

It reproduces the accepted production source and package changes, excluding
two inactive historical patch artifacts that are not referenced by the build
or runtime:

- `patches/v1.98.9/synology-netfilter.patch`
- `patches/v1.98.9/synology-netfilter.patch.sha256`

Expected resulting tree:

`11877662819d8c8276fd7fa9df2dbf28434494c4`

### `release-tree.patch`

Exact cumulative diff from upstream `v1.98.9` to the accepted production
release tree. It includes the two inactive historical artifacts and
reconstructs the production tree byte-for-byte.

Expected resulting tree:

`6d022c18f27a42aab553697c69c852bebd8594b8`

### `history/`

Exact 19-commit `git format-patch` export of the signed development history.
Applying `history/series` with `git am` reconstructs the production tree and
preserves the logical commit sequence.

## Reproducible packages

Two independent builds from the signed production tip produced byte-identical
packages.

- Sideload SHA-256:
  `bed218b4d0099102e9c3be18456d8a94be9a92b4a29295a9dab33932570cbce0`
- Package Center reference SHA-256:
  `6e01fb115dd15cd922d89bafb5d516d87533d33dda3bd4c0e70cd45f4d77c817`
- SOURCE_DATE_EPOCH:
  `1785030856`
- INFO create time:
  `20260726-01:54:16` UTC

Complete build and validation evidence is retained under
`tests/releases/v1.98.9/`.

## Commit policy

All downstream commits have valid signatures.

The first 12 commits are accepted legacy commits without mandatory sign-off
trailers. Exactly one valid `Signed-off-by` trailer is required beginning at:

`9b7c0464a2b5561cfb3e70bf07c22a6906c88cc8`

Seven commits are governed by that sign-off requirement.

## Generated files

Patch files and manifests must not be manually edited. Correct the source
commit stack or generation process and regenerate the complete artifact set.
