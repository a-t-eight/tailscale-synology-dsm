# Tailscale Synology DSM release closeout

## Purpose

This runbook closes a validated downstream Tailscale release after source,
package, reproducibility and Synology DSM hardware acceptance are complete. An
acceptance closeout may precede the public GitHub release; publication is a
later, separately approved action.

It creates a permanent, reviewable record without changing the already accepted
release source. The closeout change belongs on the control branch and must be
documentation-only.

This runbook applies to this repository's branch model:

- `synology/main` contains control assets, documentation, generated patch
  records, tests and build orchestration;
- `release/<upstream>-synology` contains the pinned upstream release plus the
  downstream source commit stack;
- a temporary `docs/<release>-closeout` branch carries the permanent release
  record;
- the documentation commit is integrated into `synology/main` without rewriting
  it.

## Safety boundary

Release closeout records completed validation. It does not perform validation
that has not already happened.

Do not use this runbook to:

- claim DSM hardware compatibility from compilation alone;
- accept a package that has not been tested on the target DSM hardware;
- replace missing package checksums, source evidence or runtime evidence with
  prose;
- modify the closed release source branch;
- rebuild or replace accepted release artefacts during documentation closeout;
- suppress failed tests or unresolved acceptance results;
- force-push `synology/main`;
- squash, rebase or otherwise rewrite the signed closeout commit;
- delete the temporary branch or worktree before integration is independently
  verified.

Installation, root bootstrap, firewall mutation and reboot testing remain
human-controlled operations.

Stable publication is not performed by this runbook. After a release is
published, add a separate `PUBLICATION.md` beside the frozen acceptance record
rather than rewriting the evidence and decision as they stood at closeout.

For the next stable publication, sign the final `SHA256SUMS` bytes with the
maintainer's SSH signing key in the `file` namespace and publish the detached
signature as `SHA256SUMS.sig`. Verify it with the protected
`.github/allowed_signers` file before publication is declared complete. This
control is prospective and does not authorise changes to an already closed
release.

## Shell-safety rule

Long procedures must be saved as complete Bash scripts and launched from the
interactive shell with:

```zsh
bash ~/step-name.sh
```

A procedure must not instruct an operator to paste top-level `set`, `trap`,
function definitions or `exit` statements directly into an interactive zsh
session.

Scripts must:

- start with `#!/usr/bin/env bash`;
- be checked with `bash -n`;
- run in a child Bash process;
- validate all expected branches, commits, paths and signatures before a write;
- stop on ambiguity rather than selecting a branch or artefact heuristically;
- print explicit `PASS`, `FAIL`, `STOP` and `NOTICE` results;
- isolate cleanup traps and shell options from the operator's interactive zsh.

## Required inputs

Record these values before beginning closeout.

| Input | Description |
| --- | --- |
| Upstream release | Pinned upstream Tailscale tag, for example `v1.98.9` |
| Package release | Downstream package release, for example `1.98.96-r1` |
| Package version | Complete DSM package version |
| Release branch | Canonical `release/<upstream>-synology` branch |
| Release commit | Final signed downstream source commit |
| Release tree | Git tree for the final release commit |
| Control branch | Normally `synology/main` |
| Accepted package | Exact production-accepted SPK filename |
| Package checksum | SHA-256 of the accepted SPK |
| Other variants | Filenames, purposes and checksums of reference variants |
| Target hardware | Synology model and platform |
| DSM baseline | Exact DSM version and minimum supported DSM version |
| Evidence root | Repository path containing permanent release evidence |
| Private archive | External archive identity and checksum, when retained |
| Documentation path | `docs/releases/<package-release>/README.md` |

Treat values copied from chat history, terminal scrollback or prose notes as
unverified until they are confirmed from Git objects, package files, checksum
manifests or retained evidence.

## Evidence hierarchy

Use the following order when sources disagree:

1. the accepted package bytes and their independently calculated checksum;
2. the final signed release commit and Git tree;
3. the canonical release branch and generated patch series;
4. machine-readable test and reproducibility evidence;
5. sanitised DSM runtime evidence and private-archive provenance;
6. the permanent release closeout record;
7. summary documentation and conversational notes.

The closeout record indexes authoritative evidence. It does not replace it.

## Closeout prerequisites

All required entries must be complete before creating the release record.

### Source state

Confirm:

- the canonical release branch exists;
- the branch points to the intended final release commit;
- the final release commit has an acceptable signature;
- the recorded release tree matches the commit;
- the downstream source commit stack is final;
- canonical patch artefacts reproduce that stack;
- the detached validation worktree remained clean;
- relevant Go tests passed;
- all inventoried Synology shell assets passed syntax validation;
- source-owned regression tests passed;
- no unresolved source-validation failure remains.

### Package state

Confirm:

- the accepted package was built from the final release commit;
- the exact package filename is recorded;
- its SHA-256 is recorded and independently verified;
- package metadata matches the intended version, architecture and DSM floor;
- static package inspection passed;
- all corresponding rebuilds were byte-for-byte reproducible;
- differing package variants have a documented purpose;
- every variant has its own checksum;
- build provenance records the pinned source and build environment;
- no candidate or superseded package is described as production accepted.

### DSM hardware acceptance

Confirm on real target hardware:

- DSM accepted installation or upgrade of the final package;
- installed binaries identify the final release commit;
- persistent Tailscale state was preserved as intended;
- node identity and Tailscale addressing were preserved;
- retained routing preferences were preserved;
- required administrator bootstrap approval was completed;
- `tailscaled` runs with the intended executable, arguments and privilege;
- the netfilter reconciler runs with the intended script;
- LocalAPI access works;
- expected `ts-input`, `ts-forward` and `ts-postrouting` state is present;
- reboot or lifecycle behaviour required by the release was tested;
- rollback instructions remain viable;
- sanitised evidence was reviewed before committing it.

A successful build is not hardware acceptance.

## Phase 1 — freeze and identify the release

1. Stop functional work on the release branch.
2. Resolve the final release commit from the canonical local branch.
3. Fetch the remote and verify the remote branch points to the same commit.
4. Resolve the commit tree.
5. verify the commit signature.
6. Record the package and evidence identities.
7. Confirm that no newer candidate has superseded the selected package.

The closeout process must stop if:

- local and remote release refs disagree;
- more than one plausible final release branch exists;
- the accepted package cannot be tied to the selected release commit;
- any checksum is missing or inconsistent;
- hardware acceptance is incomplete;
- the evidence root contains unexplained modifications.

## Phase 2 — audit retained evidence

Review the release evidence root as a coherent set.

At minimum, retain or index:

```text
tests/releases/<upstream>/README.md
tests/releases/<upstream>/SHA256SUMS
tests/releases/<upstream>/release-assets.tsv
tests/releases/<upstream>/source-validation/
tests/releases/<upstream>/shell-regression/
tests/releases/<upstream>/reproducible-build/
tests/releases/<upstream>/dsm-runtime/
```

The exact layout may evolve, but the record must identify:

- source-validation results;
- shell-regression results;
- package identities and checksums;
- reproducible-build results;
- build-environment and source provenance;
- DSM runtime acceptance;
- sanitisation decisions;
- private runtime archive provenance, when applicable.

Do not commit a full runtime archive containing tailnet-specific status,
preferences, host inventory, secrets or detailed private logs. Retain its
checksum and manifest outside Git, plus reviewed sanitised evidence in Git.

## Phase 3 — create the permanent release record

Create:

```text
docs/releases/<package-release>/README.md
```

The record must include:

1. status and closeout decision;
2. upstream release and package identity;
3. final release commit and tree;
4. integration and release branch names;
5. target architecture, hardware and DSM baseline;
6. accepted package filename and SHA-256;
7. identities and purposes of any other package variants;
8. source-validation conclusion and evidence path;
9. shell-regression conclusion and evidence path;
10. reproducible-build conclusion, inputs and evidence path;
11. DSM production-runtime conclusion and evidence path;
12. evidence index;
13. limitations or rejected claims;
14. the rule for future changes.

Use statements supported by retained evidence. Avoid vague wording such as
"fully tested" when the evidence supports only a narrower claim.

The final decision must state that future functional changes require either:

- a new downstream release revision; or
- a newer pinned upstream Tailscale release.

## Phase 4 — audit the closeout record

Before staging the document, verify:

- UTF-8 text;
- one final newline;
- no trailing whitespace;
- no unresolved placeholders;
- no private hostnames, tailnet names, addresses, tokens or user-specific paths;
- every commit and tree uses a full SHA;
- every package checksum contains 64 hexadecimal characters;
- evidence paths exist at the reviewed base;
- the release branch resolves to the final release commit;
- the document contains no functional source change;
- Git status shows only the expected untracked release record.

Review the complete document, not only a summary or generated diff statistic.

## Phase 5 — create the signed documentation commit

Create an isolated worktree from the exact current remote `synology/main`.

Use a temporary branch such as:

```text
docs/<package-release>-closeout
```

Before committing, require:

- the worktree branch matches the intended branch;
- `HEAD` matches the reviewed control-branch commit;
- the worktree contains only the release record;
- `git diff --cached --check` passes;
- the staged path list contains exactly one expected document.

Create one signed and signed-off commit.

Validate:

- the new commit parent is the reviewed `synology/main` commit;
- the signature status is good;
- exactly one matching `Signed-off-by` trailer exists;
- the commit changes only the expected release record;
- the worktree is clean after commit creation.

Do not amend the commit after it has been reviewed for integration. Any required
correction must be followed by a fresh validation of the new commit identity.

## Phase 6 — push and open the pull request

Before pushing, verify that the remote documentation branch does not already
exist unless an existing reviewed workflow explicitly expects it.

Push only the documentation branch and set its upstream.

Before opening the pull request, fetch and require:

- remote base equals the reviewed base commit;
- remote head equals the signed documentation commit;
- the head is zero commits behind the base;
- the head is exactly one commit ahead of the base;
- the diff contains only the expected closeout document;
- no existing pull request uses the same head branch.

The pull request must identify:

- the release being closed;
- the final release source commit and tree;
- accepted package and checksum;
- retained evidence categories;
- validation performed on the documentation commit;
- that the change is documentation-only;
- that no source, package, tag or release asset is modified.

## Phase 7 — integrate the exact signed commit

Revalidate immediately before integration:

- pull request state is open and not draft;
- base and head branch names are unchanged;
- base and head commit IDs are unchanged;
- the pull request remains mergeable;
- no failed or pending required checks exist;
- no unresolved review thread exists;
- the head remains exactly one commit ahead and zero behind;
- the head commit still has a good signature;
- the diff still contains only the release record.

When the signed documentation commit is a direct child of `synology/main`,
integrate it by guarded fast-forward.

This preserves:

- linear control-branch history;
- the reviewed commit SHA;
- the original signature;
- the signed-off trailer.

Do not use squash or rebase because either method rewrites the reviewed signed
commit. Do not create an unnecessary merge commit when an exact fast-forward is
possible.

The guarded push must name the expected old and new commits. Stop if the remote
base moved.

After integration, verify:

- remote `synology/main` points to the exact signed documentation commit;
- the documentation branch still points to that commit;
- GitHub records the pull request as merged;
- GitHub records the exact documentation commit as the merge commit;
- the worktree remains clean.

## Phase 8 — clean up temporary state

Delete temporary state only after post-integration validation passes.

In order:

1. delete the remote documentation branch;
2. verify that the remote branch is absent;
3. remove the clean temporary worktree;
4. verify that its path and registration are absent;
5. verify the local branch still points to the integrated commit;
6. verify that commit is an ancestor of remote `synology/main`;
7. delete the local branch with an expected-old-value guard;
8. fetch with pruning;
9. verify the remote branch, local branch and worktree are absent;
10. verify remote `synology/main` still points to the integrated commit.

Do not use a force removal for a worktree containing uncommitted changes.

## Phase 9 — record later publication

After explicit human approval creates the signed tag and public release, add:

```text
docs/releases/<package-release>/PUBLICATION.md
```

The publication record must include:

- public release URL and publication timestamp;
- release branch, commit, tree, signed tag, and tag object;
- exact filenames, sizes, and checksums of every published asset;
- the `SHA256SUMS.sig` filename and checksum, signing principal and key
  fingerprint, and the detached-signature verification result;
- post-publication reachability and checksum verification;
- signing, immutability, or provenance controls that were and were not enabled;
- an explicit statement that no accepted source, package, tag, or asset was
  changed by recording publication.

Create and integrate this record as a new signed, signed-off documentation-only
commit. Do not amend the acceptance closeout commit or alter its historical
statement that publication remained pending at acceptance time.

The detached checksum signature uses OpenSSH's `file` namespace. Create it from
the final checksum file with the maintainer-controlled signing key:

```text
ssh-keygen -Y sign \
  -f /path/to/maintainer-signing-key \
  -n file \
  SHA256SUMS
```

Verify the exact bytes before upload, substituting the principal declared in
the protected allowed-signers file:

```text
ssh-keygen -Y verify \
  -f .github/allowed_signers \
  -I maintainer@example.invalid \
  -n file \
  -s SHA256SUMS.sig \
  < SHA256SUMS
```

The verification command must exit successfully. A checksum file, its
signature, and the allowed-signers file are three separate inputs; publishing
only the checksum does not satisfy this gate.

## Failure handling

### Base branch moved

Stop. Fetch the new base and determine whether the documentation branch can be
safely recreated from it.

Do not rebase a signed closeout commit after review. Create a new signed commit
on a new reviewed base when necessary.

### Documentation commit changed

Stop. Re-run all content, signature, parent, path and pull-request validations
against the new commit.

### Unexpected changed path

Stop. Unstage the release record when safe and inspect the worktree. Do not
commit, push or merge until the additional path is explained and separately
reviewed.

### Signature failure

Stop. Confirm signing configuration and agent availability. Do not replace the
required signed commit with an unsigned commit for convenience.

### Failed or pending checks

Do not integrate. Inspect the check and determine whether it is required,
relevant and correctly configured. Never suppress a failing validation solely
to complete closeout.

### Ambiguous release identity

Stop. Reconcile the canonical release branch, commit, tree, package and checksum
from authoritative artefacts. Do not select the most plausible value.

### Cleanup partially completed

Do not recreate deleted remote state automatically. Audit which operations
succeeded, confirm `synology/main` retains the integrated commit and resume only
the remaining cleanup steps.

## Post-closeout invariants

At completion:

- remote `synology/main` contains the permanent closeout record;
- the exact signed documentation commit is retained in history;
- the pull request is recorded as merged;
- the release source commit and tree are unchanged;
- accepted package bytes and checksums are unchanged;
- release evidence remains available;
- a separate publication record exists when a public release has occurred;
- temporary local and remote documentation branches are absent;
- the temporary worktree is absent;
- the canonical release branch is retained according to repository policy;
- future functional changes are directed to a new release revision or upstream
  baseline.

## Worked example: `1.98.96-r1`

The first validated use of this process closed:

| Field | Value |
| --- | --- |
| Upstream release | `v1.98.9` |
| Package release | `1.98.96-r1` |
| Release branch | `release/v1.98.9-synology` |
| Release commit | `20c86229955a3d03de01901aee1499cab87c571d` |
| Release tree | `6d022c18f27a42aab553697c69c852bebd8594b8` |
| Closeout document | `docs/releases/v1.98.96-r1/README.md` |
| Closeout commit | `4e659239f0e4d5b017b26d17cf6e4a8b7f48dc09` |
| Integration branch | `synology/main` |
| Pull request | `#1` |
| Integration method | Guarded fast-forward of the exact signed commit |

The release-specific closeout record remains the authoritative summary for that
release. This worked example documents the procedure's first completed use; it
must not be copied without replacing and independently validating every
release-specific value.

## Operator completion record

For each release, record the following in the work log or tracking issue:

```text
Release:
Upstream:
Release branch:
Release commit:
Release tree:
Accepted package:
Accepted package SHA-256:
Reference package variants:
Evidence root:
DSM hardware:
DSM version:
Runtime acceptance date:
Closeout document:
Closeout commit:
Pull request:
Integration commit:
Cleanup result:
Open limitations:
```

A closeout is complete only when every applicable field is populated and the
post-closeout invariants have passed.

<!-- BEGIN RELEASE MANIFEST RELATIONSHIP -->

## Release manifest relationship

Future releases begin with `release/manifest.yaml` and the version-update
runbook. At closeout, treat the manifest as an input index rather than proof.

Every closeout value must still be verified against the accepted package bytes,
signed release commit and tree, canonical patches, checksums and retained
evidence.

The manifest must identify:

- upstream tag and full commit;
- final downstream release commit and tree;
- downstream revision and signed release tag;
- complete package identity and checksum;
- canonical release branch;
- canonical patch, build-output, evidence and release-record paths.

A closed release record is immutable even after `release/manifest.yaml` moves
to the next release.

<!-- END RELEASE MANIFEST RELATIONSHIP -->
