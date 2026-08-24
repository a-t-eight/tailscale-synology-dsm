# Git hooks

Version-controlled hooks provide advisory local checks. Remote validation
remains authoritative because Git permits local hooks to be bypassed.

Implemented hooks:

- `pre-commit`
- `commit-msg`

Deferred hooks:

- `pre-applypatch`
- `pre-push`
- `post-rewrite`
