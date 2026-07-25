# ADR 0001: Repository branch model

- Status: Accepted
- Date: 2026-07-25

## Context

The repository must remain easy to synchronise with upstream Tailscale
while also storing downstream patch exports, documentation, tests and
maintenance tooling.

## Decision

- `main` is an exact fast-forward mirror of upstream `main`.
- `synology/main` is an unrelated orphan branch and the GitHub default.
- `release/<version>-synology` contains upstream source plus the applied
  signed downstream commit stack.
- Temporary development occurs on `work/*` branches.
- Signed tags preserve releases and rejected historical checkpoints.

## Consequences

Upstream source history remains uncontaminated. Downstream project assets
remain visible on the repository landing page. Operations that need both
histories use separate Git worktrees.
