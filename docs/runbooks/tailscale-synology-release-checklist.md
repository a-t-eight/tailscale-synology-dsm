# Tailscale Synology DSM release checklist

## Identity

- [ ] A durable release tracking record exists as a release issue, pull request or frozen closeout record.
- [ ] Upstream tag is explicit.
- [ ] Upstream commit is a full verified SHA.
- [ ] Downstream revision is new.
- [ ] Work and release branch names are unique.
- [ ] `release/manifest.yaml` passes audit.
- [ ] New release patch format is `mail`.
- [ ] Applied patch filenames are explicitly ordered in the manifest.
- [ ] Reference-only patch list is empty or separately justified.
- [ ] New release legacy no-signoff exception list is empty.

## Source and patches

- [ ] Worktree starts at the exact upstream commit.
- [ ] Downstream commits are logically separated.
- [ ] Every downstream commit is signed.
- [ ] Every downstream commit has one matching sign-off.
- [ ] `git range-diff` was reviewed.
- [ ] Generated patches were not edited manually.
- [ ] Patch round-trip reproduces the release tree.

## Validation and build

- [ ] Complete control-tree Bash syntax, ShellCheck and shfmt validation passed.
- [ ] Current-tree and staged-diff secret scans passed without an automatic baseline.
- [ ] Synthetic positive and malicious SPK inspector fixtures passed.
- [ ] Synology shell syntax passed.
- [ ] Repository-pinned Go tests passed.
- [ ] Candidate build used the source worktree's `./tool/go`.
- [ ] Static package structure, `INFO`, payload, lifecycle shell and JSON inspection passed.
- [ ] Independent rebuilds are byte-for-byte reproducible.
- [ ] Every candidate or reference variant has a checksum.

## DSM acceptance

- [ ] Installation or upgrade passed on target hardware.
- [ ] Binary and source identity match.
- [ ] State and node identity were preserved as intended.
- [ ] Routing and netfilter behaviour passed.
- [ ] Lifecycle and reboot testing passed when required.
- [ ] Rollback remains viable.
- [ ] Runtime evidence was sanitised.

## Acceptance closeout

- [ ] Permanent release record was reviewed.
- [ ] Release closeout runbook completed.
- [ ] Acceptance closeout was integrated without changing accepted source or package bytes.

## Publication record

- [ ] Stable publication received explicit human approval.
- [ ] Signed release tag points to the final release commit.
- [ ] Published assets match accepted checksums.
- [ ] `SHA256SUMS` has a detached SSH signature published as `SHA256SUMS.sig`.
- [ ] The detached signature verifies with the protected allowed-signers file,
  expected maintainer identity, and `file` signing namespace.
- [ ] Public release and assets are reachable.
- [ ] A separate `PUBLICATION.md` records tag, assets, checksums, checksum-signature identity and verification, timestamp, and control limitations.
- [ ] The frozen acceptance closeout was not rewritten after publication.

## Local cleanup

- [ ] Workspace inventory classifies every temporary path and retained evidence root.
- [ ] No cleanup candidate has dirty files, unique commits, active worktree use or unsealed evidence.
- [ ] Exact cleanup targets received separate maintainer approval.
- [ ] Temporary branches and worktrees were cleaned up.

## Signed protected integration

- [ ] Checksum-pinned review evidence authorises the exact base, head, paths and required checks.
- [ ] Reviewed head is the signed and signed-off direct child of the protected base.
- [ ] Integration dry run passed with no unresolved discussion or failed check.
- [ ] Protected ref update used an explicit expected-old force-with-lease.
- [ ] New protected-branch push check passed with a new check-run ID.
- [ ] Pull-request terminal mode and any comment-and-close fallback were recorded.
- [ ] Persistent control and accepted-release round-trip validation passed.
- [ ] Exact temporary worktree and local or remote work branches were removed.
