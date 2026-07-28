# Tailscale Synology DSM version update

## Purpose

This runbook adapts the downstream Synology patch stack to one explicitly
selected Tailscale release. It starts from `release/manifest.yaml` and finishes
at the existing release-closeout process.

It does not select the latest release automatically.

## Safety boundary

Automation may inspect, adapt, test and build candidate artefacts. It must not:

- install or upgrade the production package;
- run root bootstrap on DSM;
- alter production firewall or netfilter state;
- reboot DSM;
- publish a stable release;
- approve its own pull request.

## Phase 1 — select and pin

1. Create a release tracking issue from the repository template.
2. Select an explicit upstream tag.
3. Resolve and verify its full commit SHA.
4. Update `release/manifest.yaml`.
5. Assign a new downstream revision.
6. Set `validation.patch_series_format` to `mail` for the new generated
   `git format-patch` series.
7. List the ordered mail patches in `validation.patch_apply_files`.
8. Empty `validation.patch_reference_files` unless a separately reviewed
   non-applied reference artefact is intentionally retained.
9. Empty `validation.accepted_legacy_no_signoff_commits`; historical exceptions
   do not transfer to a new release.
10. Choose new work and release branches.
11. Choose new patch, build-output, evidence and release-record paths.
12. Review every manifest change before creating a worktree.

Do not use a floating `latest` reference in committed release metadata.

## Phase 2 — audit inputs

Run:

```text
bash scripts/release/audit-inputs.sh \
  --source-repo /path/to/persistent-source-worktree
```

The audit must pass before a branch or worktree is created.

## Phase 3 — prepare the adaptation worktree

Review the plan:

```text
bash scripts/release/prepare-worktree.sh \
  --source-repo /path/to/persistent-source-worktree \
  --role work \
  --plan-only
```

Create the worktree only after verifying every printed value:

```text
bash scripts/release/prepare-worktree.sh \
  --source-repo /path/to/persistent-source-worktree \
  --role work \
  --target-worktree /path/to/worktree \
  --apply-patches \
  --confirm-create
```

A failed patch application is not a reason to edit generated patches manually.

## Phase 4 — adapt the signed commit stack

1. Resolve conflicts in the source commits.
2. Keep each logical downstream change in a separate commit.
3. Sign and sign off every downstream commit.
4. Use `git range-diff` against the previous downstream stack.
5. Run targeted tests after each logical adaptation.
6. Regenerate the complete patch series with `git format-patch`.
7. Replace the canonical patch export only after the source stack is final.

The signed commit stack remains authoritative.

## Phase 5 — validate source and patches

Run the full validator:

```text
bash scripts/release/validate-release.sh \
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
