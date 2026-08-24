# Tailscale Synology DSM version update

## Purpose

This runbook adapts the downstream Synology logical commit stack to one
explicitly selected Tailscale release. In a source worktree, use the deep
`prepare-version` interface through the review-artifact gate, then hand the
result to the attended control-worktree release process.

It does not select the latest release automatically.

The promoted `release/manifest.yaml` remains the immutable accepted r1
operational record. Do not rewrite it merely to plan a new version. Update the
living control-branch manifest only after the prepared source and artifacts are
independently reviewed.

## Safety boundary

Automation may inspect, adapt, test and build candidate artefacts. It must not:

- install or upgrade the production package;
- run root bootstrap on DSM;
- alter production firewall or netfilter state;
- reboot DSM;
- publish a stable release;
- approve its own pull request.

## Phase 1 — select and pin local identities

1. Create a release tracking record. Use the repository issue template when
   Issues are enabled; otherwise use the pull request or release record.
2. Select an explicit upstream tag.
3. Resolve and verify its full commit SHA.
4. Make the tag and commit available locally through a separately authorized
   fetch process; the preparation interface does not fetch.
5. Record the exact previous upstream commit and previous downstream tip.
6. Assign a new downstream revision.
7. Choose an absent `work/vN.N.N-synology-rN` branch, worktree path and artifact
   path.
8. Run the read-only plan and review every printed identity before mutation.

Do not use a floating `latest` reference in committed release metadata.

## Phase 2 — validate the preserved baseline

Run:

```text
bash tests/releases/version-preparation-contract.sh
```

The check verifies the accepted candidate, all seven protected blobs, exact r2
dependency bytes, DSM floor, absence of a production maximum and disabled
publication capabilities. It must pass before a branch or worktree is created.

## Phase 3 — prepare the adaptation worktree

Review the plan:

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

Create the worktree only after verifying every printed value:

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
  --confirm-create
```

All identities above are examples. A failed replay is not a reason to edit a
generated patch manually. The command aborts conflict state, emits no final
artifact directory and leaves the isolated worktree for review.

## Phase 4 — review the signed commit stack and artifacts

1. Verify `manifest.json` against `release/version-preparation.schema.json`.
2. Verify `SHA256SUMS` and the ordered `patches/series` inventory.
3. Verify every prepared commit signature and its single sign-off.
4. Use `git range-diff` against the previous downstream stack.
5. Run targeted source tests for each adapted logical change.
6. Review `preparation-report.md` using
   `docs/templates/agent-evidence-report.md`.
7. If an upstream conflict needs adaptation, keep the original logical commit
   boundary and regenerate the complete patch export.

The signed commit stack remains authoritative.

## Phase 5 — validate source and patches

From the attended control worktree, update the living manifest to the reviewed
source/artifact identities and run its full validator:

```text
bash /path/to/control-worktree/scripts/release/validate-release.sh \
  --control-worktree /path/to/control-worktree \
  --source-worktree /path/to/release-worktree \
  --role release \
  --round-trip
```

Require:

- exact upstream ancestry;
- clean release worktree;
- valid downstream signatures and sign-offs;
- Synology shell syntax;
- repository-pinned Go tests;
- a patch round-trip tree identical to the release source tree.

## Phase 6 — build candidates

This and later phases run from the attended control worktree; they are not
capabilities of `prepare-version`.

Review the build plan:

```text
bash scripts/release/build-candidate.sh \
  --source-worktree /path/to/release-worktree \
  --role release \
  --dry-run
```

Build only after the plan and validation are accepted:

```text
bash scripts/release/build-candidate.sh \
  --source-worktree /path/to/release-worktree \
  --role release \
  --output-root /path/to/candidate-output \
  --confirm-build
```

The command records candidate checksums and build metadata. It does not publish
or install the package.

## Phase 7 — reproducibility and package inspection

1. Build the same source in the same pinned environment independently.
2. Compare the complete SPK bytes.
3. Inspect outer SPK metadata.
4. Inspect the inner package payload.
5. Verify architecture, DSM floor, version and service scripts.
6. Classify every differing package variant.
7. Reject unexplained differences.

## Phase 8 — manual DSM acceptance

On the designated test hardware, validate:

- installation or upgrade;
- binary and source identity;
- retained state and node identity;
- routing preferences;
- LocalAPI access;
- TUN and netfilter state;
- service lifecycle;
- reboot behaviour when required;
- rollback viability.

Before installation or upgrade, independently retain the accepted package
checksum, a compatible previous package, persistent state, relevant DSM
settings and administrative access that does not depend on Tailscale. Define
the stop and rollback decision before changing the NAS.

A successful build is not DSM acceptance.

## Phase 9 — collect reviewed evidence

Review the plan:

```text
bash scripts/release/collect-evidence.sh \
  --source-worktree /path/to/release-worktree \
  --candidate-root /path/to/candidate-output \
  --dry-run
```

Create the evidence skeleton only after candidate evidence is complete:

```text
bash scripts/release/collect-evidence.sh \
  --source-worktree /path/to/release-worktree \
  --candidate-root /path/to/candidate-output \
  --confirm-collect
```

Runtime evidence must be sanitised manually before it enters Git.

## Phase 10 — publish and close out

Stable publication remains a separate explicit human action after:

- source validation;
- package validation;
- reproducibility;
- DSM hardware acceptance;
- evidence review;
- rollback review.

After publication, use:

```text
docs/runbooks/tailscale-synology-release-closeout.md
```

Future functional changes require a new downstream revision or a newer pinned
upstream release.
