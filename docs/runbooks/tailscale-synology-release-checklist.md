# Tailscale Synology DSM release checklist

## Identity

- [ ] Release issue exists.
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

## Publication and closeout

- [ ] Stable publication received explicit human approval.
- [ ] Published assets match accepted checksums.
- [ ] Signed release tag points to the final release commit.
- [ ] Permanent release record was reviewed.
- [ ] Release closeout runbook completed.
- [ ] Temporary branches and worktrees were cleaned up.
