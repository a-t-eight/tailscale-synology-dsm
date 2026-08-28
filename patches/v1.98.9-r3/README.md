# Tailscale Synology DSM r3 delta patch series for v1.98.9

This directory contains the seven signed mail patches that form the r3 delta
from accepted r2 source commit
`0fad8b81a3e0eb86c457bc79c474bcc213834c43` to accepted r3 source commit
`f49613eccf9350583cc328183f192a591cd76348`.

## Layered source contract

The canonical historical base remains the 58-patch r2 series at
`patches/v1.98.9-r2/`. It starts from Tailscale `v1.98.9` upstream commit
`6c167d40fa37aeb51afa7ff336730670ea4762bf` and reconstructs accepted r2 tree
`33f5c5927ae4db54b9d582650ed31cc6a2eb7161` at the r2 base commit above.

This r3 directory deliberately publishes only the seven-commit delta. Applying
this ordered series after the r2 base reconstructs accepted r3 tree
`44c0bc3cd3bbcd3eb70cacf34e9611909a38bd10`. The delta preserves the original
signed commit boundaries and signed-off trailers.

## Generation

These payloads were generated without manual edits with:

```text
git format-patch --output-directory patches/v1.98.9-r3 \
  0fad8b81a3e0eb86c457bc79c474bcc213834c43..f49613eccf9350583cc328183f192a591cd76348
```

`series` is the required application order. `SHA256SUMS` covers every mail
patch in that order. Regenerate both metadata files after regenerating the
patches; never modify a patch payload.

## Full layered round trip

In a disposable detached worktree at upstream commit `6c167d40`, first run
`git am --3way` over every filename in `patches/v1.98.9-r2/series`, then run
the same command over every filename in this directory's `series`. The final
tree must be `44c0bc3cd3bbcd3eb70cacf34e9611909a38bd10`.

Before application, validate each layer with `sha256sum -c SHA256SUMS` from
its own directory. Validate every represented source commit with the
repository's allowed-signers policy and confirm exactly one matching
`Signed-off-by` trailer. The r2 base and r3 delta are one layered reproducible
history contract; release tooling support for that layering is intentionally
deferred to Task 2.
