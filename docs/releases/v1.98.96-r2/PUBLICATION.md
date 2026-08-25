# Tailscale Synology DSM 1.98.96-r2 publication record

## Status

The human-maintainer publication gate for `1.98.96-r2` completed on
2026-08-25. This record documents publication without modifying the earlier
acceptance closeout record.

Public release:

```text
https://github.com/a-t-eight/tailscale-synology-dsm/releases/tag/release/synology-v1.98.96-r2
```

GitHub release ID: `375936420`

Publication timestamp: `2026-08-25T07:15:09Z`

## Published identity

| Field | Value |
| --- | --- |
| Release branch | `release/v1.98.9-r2-synology` |
| Release commit | `0fad8b81a3e0eb86c457bc79c474bcc213834c43` |
| Release tree | `33f5c5927ae4db54b9d582650ed31cc6a2eb7161` |
| Signed tag | `release/synology-v1.98.96-r2` |
| Tag object | `04a86b465cc41ba2b0aa8492292a326bd333c648` |
| Release status | Published, not a prerelease |

The annotated tag has a valid SSH signature and resolves to the exact accepted
release commit.

## Published assets

```text
tailscale-x86_64-1.98.96-700098097-dsm7.spk
SHA-256: f947a1747521c50edf49baf597cc18b512b3bb009c3b7afe963fa326ef2d6c16
Size: 36908032 bytes
```

```text
SHA256SUMS
GitHub asset SHA-256: ec74acb14dd01365d1ff354719c3525da397278b8a0f17dd1ae8f126a9d6bfd2
Size: 110 bytes
```

Post-publication checks confirmed that the release page, SPK, and checksum
asset were publicly reachable and that GitHub reported the accepted digests.

The SPK is not signed by Synology. `SHA256SUMS` does not carry a detached
signature in r2. Release immutability was not enabled when r2 was published and
is deferred for review before the next actual build. The exact package checksum
remains recorded in the signed and protected control history.

## Relationship to acceptance closeout

[README.md](README.md) records the source, package, reproducibility, and DSM
runtime acceptance decision before publication. Its statement that publication
remained a human-maintainer action is historically accurate and is not
rewritten by this later event.

Revision r1 remains retained as superseded history. No source, package, tag, or
release asset change is authorised by this publication record.
