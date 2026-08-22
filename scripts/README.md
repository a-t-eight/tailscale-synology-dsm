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
- `setup-worktree.sh` configures repository-owned hooks and signing for a
  control, work, release or accepted worktree.

Preparation never fetches, pushes, tags, builds either SPK, publishes, installs
on a NAS or changes NAS state. See
`docs/runbooks/agent-version-preparation.md`.
