# Security policy

## Supported baseline

Security fixes are assessed against the current production baseline documented
on `synology/main` and the active `release/*-synology` branch.

Older downstream revisions may not receive fixes after a replacement release is
accepted.

## Reporting a vulnerability

Do not disclose an exploitable vulnerability, secret, private runtime archive
or tailnet-specific evidence in a public issue.

Use GitHub's private vulnerability-reporting interface for this repository when
available. If that interface is unavailable, contact the repository owner
privately through their established GitHub contact channel before publishing
technical details.

Include:

- affected release and commit;
- DSM model, architecture and version;
- reproduction conditions;
- expected and observed behaviour;
- privilege and network exposure;
- sanitised logs or evidence;
- proposed mitigation, when known.

## Sensitive evidence

Do not commit:

- authentication keys, tokens or cookies;
- private tailnet names or status output;
- private host inventories or addressing;
- unsanitised runtime archives;
- production configuration containing secrets.

Retain private evidence outside Git. Commit only its checksum, manifest,
transfer verification and reviewed sanitised extracts.

## Response boundary

A security fix must not bypass:

- signed-commit requirements;
- package and patch validation;
- reproducible-build checks;
- DSM hardware acceptance;
- explicit administrator approval for privileged runtime changes.
