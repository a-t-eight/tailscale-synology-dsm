# Tailscale Synology DSM patch set for v1.98.9

## Authoritative source

The signed downstream commit stack on
`release/v1.98.9-synology` is authoritative.

- Upstream base: `6c167d40fa37aeb51afa7ff336730670ea4762bf`
- Production tip: `cc5d96275e9dd76fd8a4f38209a2df91199a425c`
- Production tree: `e004b64196c89a32e2a4b71949d2aff19d133ef8`

## Artifacts

### `maintenance.patch`

Recommended cumulative patch for future maintenance and upstream adaptation.

It reproduces the accepted production source and package changes, excluding
two inactive historical patch artifacts that are not referenced by the build
or runtime:

- `patches/v1.98.9/synology-netfilter.patch`
- `patches/v1.98.9/synology-netfilter.patch.sha256`

Expected resulting tree:

`b8ced487a68252e56e9665df1993e4b4970d87d9`

### `release-tree.patch`

Exact cumulative diff from upstream `v1.98.9` to the accepted production
release tree. It includes the two inactive historical artifacts and
reconstructs the production tree byte-for-byte.

### `history/`

Exact 18-commit `git format-patch` export of the signed development history.
Applying `history/series` with `git am` reconstructs the production tree and
preserves the logical commit sequence.

## Commit policy

All downstream commits have valid signatures.

The first 12 commits are accepted legacy commits without mandatory sign-off
trailers. Exactly one valid `Signed-off-by` trailer is required beginning at:

`9b7c0464a2b5561cfb3e70bf07c22a6906c88cc8`

## Generated files

Patch files must not be manually edited. Correct the source commit stack or
generation process and regenerate the complete artifact set.
