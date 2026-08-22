# Scripts

## Source-worktree release preparation

- `release/prepare-worktree.sh prepare-version` is the single deep interface
  for replaying an ordered logical stack onto an explicit local upstream
  tag/commit. It creates a signed isolated worktree and review artifacts after
  patch round-trip validation.
- `release/prepare-worktree.sh` without a subcommand preserves the accepted
  manifest-driven control workflow.
- `release/common.sh` contains strict manifest, patch and worktree helpers used
  by both modes.
- `setup-worktree.sh` configures repository-owned hooks and signing. The
  `control` role is limited to the separate complete control-only tree that
  contains `scripts/validate-repository.sh`; this promoted source-worktree layer
  uses the `accepted`, `work`, or `release` roles with that control tree. Those
  source-role wrappers require and invoke the retained
  `scripts/release/validate-release.sh` from the external control worktree; the
  frozen accepted-release validator is not copied into source branches.

Preparation never fetches, pushes, tags, builds either SPK, publishes, installs
on a NAS or changes NAS state. See
`docs/runbooks/agent-version-preparation.md`.
