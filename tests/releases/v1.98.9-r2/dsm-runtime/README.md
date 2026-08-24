# DSM 7.4.1 abbreviated exact-artifact acceptance

## Decision

`PASS — accepted for governed r2 release closeout`

The operator installed and exercised the final sideload package built from
commit `0fad8b81a3e0eb86c457bc79c474bcc213834c43`. This abbreviated acceptance
binds the final CI-only source revision to the installed package and runtime;
the preceding functional revision had already completed the broader DSM 7.4.1
bootstrap and networking acceptance cycle.

## Verified identity

- upstream: Tailscale `v1.98.9` at
  `6c167d40fa37aeb51afa7ff336730670ea4762bf`;
- release commit: `0fad8b81a3e0eb86c457bc79c474bcc213834c43`;
- release tree: `33f5c5927ae4db54b9d582650ed31cc6a2eb7161`;
- installed package version: `1.98.96-700098097`;
- installed architecture: `x86_64`;
- installed minimum DSM: `7.3-86009`;
- accepted sideload package SHA-256:
  `f947a1747521c50edf49baf597cc18b512b3bb009c3b7afe963fa326ef2d6c16`.

Both the installed `tailscale` and `tailscaled` binaries reported the exact
release commit. Their SHA-256 values, together with the bootstrap executable's
SHA-256, matched files independently streamed from the accepted SPK:

```text
54163d86209b56544a03a0f840365c768a917f71e3b50d77afcafee97c44fcf0  bin/tailscale
633dbb61def7057c482dbea1650d259b163d15436cd9c258362a7c45155054c2  bin/tailscaled
563126fa3a21caaaa27f76d637592f7c81f0fed638cfd5d7beb2693928a4689d  bin/tailscale-synology-bootstrap
```

## Verified runtime state

The operator observed:

- Synology Package Manager status `running`;
- privilege mode `root`;
- bootstrap state `current`;
- runtime state `running, UID=0`;
- steady-state tailnet operation after the expected immediate startup
  transition.

## Scope and sanitisation

This record deliberately excludes the NAS hostname, tailnet name, addresses,
peer inventory, account names, credentials, private keys, and raw runtime
logs. The operator retains the original terminal transcript outside Git.

The machine-readable companion record is `acceptance.env`. This abbreviated
acceptance does not claim a second reboot test for the CI-only revision.
