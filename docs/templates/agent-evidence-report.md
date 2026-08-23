# Synology version preparation evidence

## Change summary

- Upstream tag and full commit:
- Previous upstream commit:
- Previous downstream tip:
- New version and downstream revision:
- Prepared branch, commit and tree:

## Ordered logical history

List each source commit beside its prepared commit and subject in replay order.

## Validation evidence

- Baseline/protected-blob contract:
- Commit signatures and single sign-offs:
- Focused Go and Synology shell tests:
- Mail-patch checksum verification:
- Patch round-trip tree equality:
- Range-diff review:

## Fixed product contract

- Dependency section: `iptables-netfilter-extensions`
- Dependency minimum: `1.1.0-3`
- Dependency DSM minimum: `7.3-86009`
- Tailscale DSM minimum: `7.3-86009`
- Production `os_max_ver`: absent

## Risks and reviewer attention

Describe upstream conflicts, deliberately changed logical behavior, deferred
hardware validation and any unavailable optional validator.

## Prohibited side effects

Confirm that preparation did not fetch, push, create a pull request or tag,
build either SPK, release, publish, install on a NAS, run root bootstrap, alter
firewall/netfilter state or reboot DSM.

## Verdict

Use one verdict:

- `PASS — ready for independent source review`
- `STOP — identity, replay or validation failure`
- `DEFERRED — outside version-preparation scope`
