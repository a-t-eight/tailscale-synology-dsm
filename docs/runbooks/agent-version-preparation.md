# Agent version preparation

## Purpose

Use `scripts/release/prepare-worktree.sh prepare-version` to replay the current
ordered Synology logical history onto one explicitly pinned upstream version.
The command works only with local Git objects, creates an isolated worktree and
emits review artifacts after validating a mail-patch round trip.

This is preparation, not release or publication.

## Preconditions

1. Start in a clean worktree that descends from the accepted candidate.
2. Run `bash tests/releases/version-preparation-contract.sh`.
3. Make the selected upstream tag and commit available locally through a
   separately reviewed fetch process. The preparation command never fetches.
4. Identify the exact previous upstream base and previous downstream tip.
5. Configure working SSH commit signing and the repository-owned hooks.
6. Select target branch, target worktree and output paths that do not exist.

## Read-only plan

The identities below are examples only:

```text
bash scripts/release/prepare-worktree.sh prepare-version \
  --source-repo /path/to/tailscale-source \
  --upstream-tag v2.0.0 \
  --upstream-commit 1111111111111111111111111111111111111111 \
  --previous-upstream-commit 2222222222222222222222222222222222222222 \
  --previous-release-commit 3333333333333333333333333333333333333333 \
  --new-version 2.0.0 \
  --downstream-revision r1 \
  --target-branch work/v2.0.0-synology-r1 \
  --target-worktree /path/to/work-v2.0.0-synology-r1 \
  --output-root /path/to/review/v2.0.0-r1 \
  --plan-only
```

Review the peeled tag, old base, ordered source commits, new branch/worktree and
artifact path. A plan creates no ref, worktree or artifact.

## Confirmed preparation

Repeat the reviewed command with `--confirm-create` instead of `--plan-only`.
The command:

1. creates the target branch/worktree at the exact new upstream commit;
2. replays each old logical commit in order;
3. signs each new commit with exactly one current-identity sign-off;
4. exports ordered mail patches;
5. applies them to a temporary detached worktree;
6. requires the round-trip tree to equal the prepared tree;
7. atomically installs the review artifact directory.

On a replay conflict, the command aborts the cherry-pick, emits no final
artifact directory and leaves the isolated worktree for review. Do not edit a
generated patch. Resolve the logical source adaptation in its worktree, keep
the commit boundary, then regenerate the complete export.

## Review artifact gate

Require these files:

```text
manifest.json
SHA256SUMS
patches/series
patches/0001-*.patch
preparation-report.md
```

Validate checksums, strict manifest/schema conformance, source and prepared
identities, ordered commits, signatures, one sign-off per commit, fixed
Synology package contract and round-trip tree equality. Use `git range-diff` to
review logical equivalence to the previous stack.

## Handoff boundary

The agent may draft review notes. Creating or updating a pull request requires
separate authorization. Building either SPK, tagging, releasing, publishing,
installing on a NAS, running bootstrap, changing firewall/netfilter state and
rebooting are outside this workflow.

