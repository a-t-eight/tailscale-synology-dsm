# Documentation

Documentation is organised by task rather than by the order in which the
project was developed.

## Repository and package users

- [Repository guide](repository-guide.md) — branch roles, sources of truth, and
  how to navigate the multi-root repository.
- [Package runtime guide](package-runtime.md) — netfilter dependency,
  administrator bootstrap, ownership, removal, and security boundaries.
- [Development workspace guide](development-workspace.md) — a safe local
  layout for clones, worktrees, caches, build outputs, and retained evidence.

## Release operators

- [Version-update runbook](runbooks/tailscale-synology-version-update.md)
- [Release checklist](runbooks/tailscale-synology-release-checklist.md)
- [Release closeout runbook](runbooks/tailscale-synology-release-closeout.md)
- [Signed protected integration](runbooks/signed-protected-integration.md)
- [Governance tooling](governance/tooling.md)

## Architecture and policy

- [ADR 0001: repository branch model](adr/0001-repository-branch-model.md)
- [ADR 0002: persistent UID-0 runtime trust boundary](adr/0002-privileged-bootstrap-trust-boundary.md)
- [Upstream-compatible root-control design](superpowers/specs/2026-08-28-upstream-compatible-root-control-design.md)
  — approved Task 5 path, reconciliation, migration, residual-risk, and
  validation contract.
- [Final productionisation status](governance/final-productionisation.md) —
  completed work, remaining UID-0 trust-boundary hardening, agent/tooling
  prerequisites, whole-product reproducibility, and the next-release train.
- [Repository governance](governance/repository-governance.md)
- [Automation governance](governance/automation.md) — validation lanes,
  workflow catalogue, required checks, and mutable GitHub state.
- [Security policy](../SECURITY.md)

## Release records

- [1.98.96-r2 acceptance closeout](releases/v1.98.96-r2/README.md)
- [1.98.96-r2 publication record](releases/v1.98.96-r2/PUBLICATION.md)
- [1.98.96-r1 acceptance closeout](releases/v1.98.96-r1/README.md)

Release closeout records describe the evidence and decision at acceptance
time. Publication records document the later human-approved external action
without rewriting the frozen acceptance record.
