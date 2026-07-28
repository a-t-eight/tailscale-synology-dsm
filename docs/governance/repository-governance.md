# Repository governance

## Purpose

This document defines the minimum governance controls for the Tailscale
Synology DSM downstream repository.

## Branch model

- `main` is an exact fast-forward mirror of `tailscale/tailscale`.
- `synology/main` contains downstream control assets and documentation.
- `work/<upstream>-synology` contains temporary source adaptation.
- `release/<upstream>-synology` contains the tested downstream source stack.
- temporary documentation and governance branches are deleted after verified
  integration.

Downstream files must never be committed to `main`.

## Commit integrity

Every downstream commit must:

- be cryptographically signed;
- contain exactly one `Signed-off-by` trailer;
- represent one logical change;
- retain its exact identity when the reviewed workflow requires it.

Repository-local Git configuration enables automatic commit and tag signing.
The hooks provide prospective enforcement; accepted history is not rewritten.

## Review and ownership

`CODEOWNERS` assigns the repository owner to governance, workflow, packaging,
release and evidence paths.

Pull requests must record:

- exact base and head commits;
- changed paths;
- validation evidence;
- security and privilege impact;
- hardware-testing requirements;
- release-boundary compliance.

## Validation

The canonical command is:

```text
bash scripts/validate-repository.sh --bootstrap
```

The same script is used locally and by GitHub Actions. Locally it discovers
exactly one clean registered worktree at the accepted release commit and tree.
CI supplies the worktree path explicitly. Every Go operation uses that
worktree's `./tool/go`.

The initial baseline applies:

- Bash syntax validation to the shell inventory;
- ShellCheck error-level analysis to governance-owned shell scripts;
- shfmt enforcement to governance-owned shell scripts;
- repository-owned Markdown and YAML validation through the pinned
  Tailscale Go environment;
- actionlint and immutable Action-reference checks to workflows.

Formatting enforcement can expand to legacy scripts only through a separately
reviewed change.

## Automation boundary

CI may:

- validate source and metadata;
- inspect patches and packages;
- build candidate artefacts;
- produce non-production evidence.

CI must not:

- access production DSM credentials;
- install or upgrade the production package;
- run root bootstrap;
- mutate production firewall state;
- reboot DSM;
- publish or approve a stable release automatically.

## GitHub protection order

Repository rules are configured only after the validation workflow is present
on `synology/main` and its check name is stable.

The intended ruleset requires:

- pull requests for `synology/main`;
- the `repository-governance` check;
- linear history;
- blocked force pushes;
- blocked branch deletion;
- conversation resolution;
- administrator enforcement where operationally viable.

Rules must preserve the existing guarded exact fast-forward integration model.
