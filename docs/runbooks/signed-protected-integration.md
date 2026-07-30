# Signed protected integration

## Purpose

This runbook integrates one reviewed signed pull-request commit into the
protected `synology/main` branch without invoking GitHub's merge, squash or
rebase endpoints.

The protected branch is updated only from an exact expected-old commit to the
reviewed signed direct child. The operation uses an explicit
`--force-with-lease` because the repository ruleset requires pull requests and
blocks non-fast-forward operations, while the reviewed commit identity must be
preserved exactly.

## Required authority

The operator must be an authenticated GitHub actor recorded as an `always`
bypass actor for the active ruleset applying to `synology/main`.

The bypass is used only after the script confirms:

- the exact protected base and reviewed head;
- a direct parent-child relationship;
- local and GitHub signature verification;
- exactly one matching sign-off;
- immutable review evidence and reviewed patch digest;
- the exact changed-path allowlist;
- successful required pull-request checks;
- no issue comments, review comments, requested changes or unresolved threads.

## Review evidence contract

The integration command requires a checksum-pinned JSON review record with this
minimum structure:

```json
{
  "schema_version": 1,
  "repository": "OWNER/REPOSITORY",
  "control_branch": "synology/main",
  "base_commit": "FULL_SHA",
  "reviewed_commit": "FULL_SHA",
  "implementation_branch": "BRANCH",
  "changed_paths": ["path/one", "path/two"],
  "review_patch_sha256": "SHA256",
  "required_checks": ["repository-governance"],
  "authorises_integration": true,
  "validation_failures": 0
}
```

The review record does not authorise package publication, DSM installation,
repository-setting changes or any unrelated branch update.

## Dry-run gate

Run the exact command first with `--dry-run`:

```text
bash scripts/governance/integrate-signed-pr.sh \
  --repository OWNER/REPOSITORY \
  --pr-number NUMBER \
  --control-branch synology/main \
  --work-branch BRANCH \
  --expected-base BASE_SHA \
  --expected-head REVIEWED_SHA \
  --review-evidence /path/to/review.json \
  --review-evidence-sha256 REVIEW_SHA256 \
  --pr-worktree /path/to/pr-worktree \
  --control-worktree /path/to/control-worktree \
  --source-worktree /path/to/accepted-source-worktree \
  --evidence-dir /path/to/evidence \
  --required-check repository-governance \
  --required-check release-operations \
  --dry-run
```

Only checks that are explicitly recorded in the review evidence may be passed
as `--required-check` arguments.

## Integration gate

After reviewing the dry-run evidence, replace `--dry-run` with:

```text
--confirm-integrate
```

The script then:

1. Revalidates the exact pull request, signed commit, review evidence, checks,
   discussions and protected ruleset.
2. Pushes the reviewed head with an expected-old lease bound to the exact base.
3. Writes a resume-state record immediately after the protected ref changes.
4. Requires a new successful `repository-governance` push check whose check-run
   ID was not present before integration.
5. Records GitHub's pull-request terminal state.
6. Uses a comment-and-close fallback when GitHub does not mark the directly
   integrated pull request as merged.
7. Fast-forwards the persistent control worktree.
8. Runs repository and accepted-release round-trip validation.
9. Removes only the exact temporary worktree and local or remote work branch.
10. Generates permanent Markdown and JSON evidence.

## Resume boundary

A failure after the protected ref changes must not be handled by rerunning the
initial integration command.

Inspect the state file printed by the failed run, preserve the temporary
worktree and branch, then use the same arguments with:

```text
--resume
```

Resume mode verifies the state contract and current protected head before
continuing with the new push check, pull-request terminal state, persistent
control validation and cleanup.

## Pull-request terminal state

The evidence records one of two modes:

- `github-merged`: GitHub marked the pull request merged and recorded the exact
  reviewed signed commit as its merge identity;
- `comment-close`: the protected branch was integrated successfully, a
  deterministic evidence comment was added and the pull request was closed
  without claiming that GitHub's merge endpoint was used.

Both modes require the protected branch to point to the reviewed signed commit
and a new successful protected-branch push check.

## Prohibited operations

The integration entrypoint does not:

- call GitHub's merge, squash or rebase endpoint;
- build, install, transfer or publish a package;
- create a release or tag;
- change repository settings or rulesets;
- access production DSM credentials;
- run root bootstrap, mutate firewall state or reboot DSM.
