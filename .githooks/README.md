# Git hooks

Version-controlled hooks provide advisory local checks. Remote validation
remains authoritative because Git permits local hooks to be bypassed.

These hooks are selected directly only for a complete control-only worktree
that contains `scripts/validate-repository.sh`. Source, accepted, work, and
release worktrees use the role-specific wrappers created by
`scripts/setup-worktree.sh`.

Implemented hooks:

- `pre-commit`
- `commit-msg`

Deferred hooks:

- `pre-applypatch`
- `pre-push`
- `post-rewrite`
