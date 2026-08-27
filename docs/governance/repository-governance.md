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

The canonical validator applies:

- Bash syntax, ShellCheck error-level analysis and shfmt enforcement to one
  deterministic inventory of all repository-owned control-tree shell;
- repository-owned Markdown and YAML validation through the pinned
  Tailscale Go environment;
- actionlint and immutable Action-reference checks to workflows;
- Gitleaks scanning to the current control tree in CI and to the staged diff
  from the repository-owned pre-commit hook;
- synthetic positive and negative tests for the non-installing SPK inspector.

The cross-branch workflow catalogue, validation lanes, and required-check
relationships are defined in [automation governance](automation.md). The
canonical validator checks its stable identifiers against both the control
tree and the pinned accepted-source tree without querying GitHub.

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

<!-- BEGIN MANIFEST-DRIVEN RELEASE OPERATIONS -->

## Manifest-driven release operations

`release/manifest.yaml` is the single operational source for a downstream
release's upstream identity, downstream revision, package identity, branch
names, build entrypoint and evidence paths.

Release operations use three branch classes:

- `operations/*` changes control-plane release tooling;
- `work/<upstream>-synology` adapts the downstream source stack;
- `release/<upstream>-synology` contains the validated signed source stack.

The `release-operations` CI check validates manifest and source coherence. It
does not replace the required `repository-governance` check and is not
authorised to publish a stable release.

Candidate automation may build artefacts only after exact source, patch and
toolchain validation. Production DSM installation, root bootstrap, firewall
mutation, reboot and stable publication remain explicit human gates.

<!-- END MANIFEST-DRIVEN RELEASE OPERATIONS -->

## Protected SSH signer trust

Release validation stores public SSH trust in `.github/allowed_signers`.
Pull-request CI checks out the protected base separately and reads the signer
file from that checkout, rather than treating the pull-request head as the
normal trust root.

The bootstrap PR is the sole exception because protected base
`c08cb5af27701615f6180d79182d2c8559c601bf` predates the signer file. During that PR,
`RELEASE_ALLOWED_SIGNERS_SHA256` must equal the signer file SHA-256. Remove the
repository variable immediately after the bootstrap commit is integrated.


<!-- BEGIN SIGNED PROTECTED INTEGRATION -->

## Signed protected integration

GitHub merge, squash and rebase execution are not accepted as the integration
primitive when reviewed commit identity must be preserved. A repository-owned
entrypoint performs the protected ref update only after the pull request,
reviewed signed commit, changed-path allowlist, immutable review evidence,
discussions and required checks are exact.

The update must:

- bind an explicit force-with-lease to the expected protected base SHA;
- move the protected branch only to the reviewed signed direct child;
- require a new successful protected-branch push check distinguished from prior
  pull-request checks by check-run ID;
- record GitHub's pull-request terminal state or use the documented
  comment-and-close fallback;
- preserve a resume boundary after remote integration;
- run repository and accepted-release validation before exact temporary-state
  cleanup.

The bypass required by the ruleset is an explicit governed authority, not a
replacement for pull-request review or validation.

<!-- END SIGNED PROTECTED INTEGRATION -->

<!-- BEGIN TARGETED QUALITY CONTROLS -->

## Targeted quality and package-inspection controls

The repository uses one canonical shell inventory for Bash syntax, ShellCheck
and shfmt. Imported source worktrees remain outside this control-tree
formatting boundary.

Gitleaks is pinned as a checksum-verified CLI release. CI scans the current
control tree. The pre-commit hook scans only the staged Git diff with redacted
output. No automatic baseline or ignore file is generated; any future
suppression requires explicit review.

Candidate SPKs are statically inspected before checksums and candidate metadata
are accepted. Inspection:

- does not source `INFO`;
- does not execute package scripts;
- does not install or start the package;
- rejects archive traversal, unsafe members and duplicate normalised paths;
- checks manifest-bound `INFO` identity;
- validates lifecycle shell syntax and package JSON configuration;
- validates `package.tgz` as a safe readable archive.

Static inspection is not DSM hardware acceptance.

<!-- END TARGETED QUALITY CONTROLS -->
