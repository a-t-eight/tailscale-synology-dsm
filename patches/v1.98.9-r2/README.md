# Tailscale Synology DSM r2 patch series for v1.98.9

The 58 signed mail patches in this directory are the canonical export of the
linear downstream source range from Tailscale `v1.98.9` at
`6c167d40fa37aeb51afa7ff336730670ea4762bf` through release commit
`0fad8b81a3e0eb86c457bc79c474bcc213834c43`.

Applying `series` in order with `git am --3way` reproduces tree
`33f5c5927ae4db54b9d582650ed31cc6a2eb7161` and preserves the original signed
commit boundaries and signed-off trailers.

The sealed source review bundle was:

```text
tailscale-synology-review-v1.98.9-r2-dsm741-ci-fix-0fad8b81
```

Its `SHA256SUMS` file had SHA-256:

```text
ec0ed1ec021175b5c3882b19a0e7935091c7d103a1a660209b96a26d4fd2244e
```

The bundle checksum manifest was verified before these generated patch files
were imported. Patch files must be regenerated from the signed source history;
they must never be edited manually.
