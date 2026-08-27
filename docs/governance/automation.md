# Automation governance

## Purpose

This repository separates downstream control material from the accepted
Tailscale source tree. Its GitHub Actions workflows therefore come from more
than one branch root and serve different assurance purposes.

This guide is the public catalogue of the workflows maintained for the current
release. It identifies where each workflow is defined, when it runs, whether
it participates in repository protection, and the limit of the evidence it
produces.

## Validation lanes

The automation is organised into four lanes:

1. **Control governance** validates `synology/main`, including documentation,
   manifests, release tooling, shell quality, secret scanning, and governance
   contracts.
2. **Release operations** validates release-manifest and source coherence and
   can build an explicitly requested non-production candidate.
3. **Synology product validation** tests the downstream source changes that
   implement and package the DSM runtime.
4. **Upstream compatibility validation** retains selected upstream workflows
   for attended compatibility testing during source adaptation and upgrades.

Passing one lane does not imply that another lane passed. In particular,
automation does not constitute DSM hardware acceptance or permission to
publish a stable release.

## Workflow catalogue

`control` means the workflow is defined on `synology/main`.
`accepted-source` means it is defined by the source commit pinned in
`release/manifest.yaml`. Trigger and status identifiers in this table are
validated offline by `tests/governance/automation-contract.sh`.

| Workflow | File | Root | Ownership | Triggers | Status | Ruleset | Proves | Does not prove |
| --- | --- | --- | --- | --- | --- | --- | --- | --- |
| `Validate repository` | `.github/workflows/validate.yml` | `control` | downstream-owned | `pull_request`, `push`, `workflow_dispatch` | `repository-governance` | Required on `synology/main` | Control-tree governance and pinned release contracts pass | Source runtime or DSM hardware acceptance |
| `Validate release candidate` | `.github/workflows/release-candidate.yml` | `control` | downstream-owned | `pull_request`, `workflow_dispatch` | `release-operations` | Not a required branch check | Manifest, source, patch, and optional candidate-build gates pass | Stable publication or DSM acceptance |
| `Synology product` | `.github/workflows/synology-product.yml` | `accepted-source` | downstream-owned | `pull_request`, `workflow_dispatch` | `synology-product` | Required on downstream release branches | Focused Synology source, shell, and Go tests pass | Installation, reboot, or production network behavior |
| `checklocks` | `.github/workflows/checklocks.yml` | `accepted-source` | upstream-inherited | `push`, `pull_request` | `checklocks` | Not required by downstream rulesets | Annotated lock usage passes the upstream analyser | Complete downstream product correctness |
| `golangci-lint` | `.github/workflows/golangci-lint.yml` | `accepted-source` | downstream-modified | `pull_request`, `workflow_dispatch` | `lint` | Not required by downstream rulesets | Changed Go code passes the configured linter | Runtime, packaging, or hardware behavior |
| `tailscale.com/cmd/vet` | `.github/workflows/vet.yml` | `accepted-source` | downstream-modified | `push`, `pull_request` | `vet` | Not required by downstream rulesets | Selected Go packages pass the repository vet tool | The complete test suite or DSM acceptance |
| `CI` | `.github/workflows/test.yml` | `accepted-source` | downstream-modified | `push`, `merge_group`, `workflow_dispatch` | `multiple jobs` | Not required by downstream rulesets | Broad upstream compatibility jobs pass when attended | A pull request gate for the downstream release branch |
| `natlab-integrationtest` | `.github/workflows/natlab-integrationtest.yml` | `accepted-source` | downstream-modified | `push`, `merge_group`, `workflow_dispatch` | `natlab-integrationtest` | Not required by downstream rulesets | The selected virtual network integration scenario passes | Synology kernel or physical-network behavior |
| `Dockerfile build` | `.github/workflows/docker-file-build.yml` | `accepted-source` | downstream-modified | `push`, `workflow_dispatch` | `deploy` | Not required by downstream rulesets | The upstream Dockerfile builds on its configured trigger | SPK construction or DSM operation |

## Branch protection and merge policy

`synology/main` requires the `repository-governance` check. Downstream release
branches are covered by two deliberately layered rulesets:

- a structural ruleset requires signed commits, linear history, pull requests,
  and the `synology-product` check, with an owner-only break-glass bypass for
  the repository's exact signed fast-forward integration procedure;
- a product-validation ruleset independently requires `synology-product` and
  has no bypass actors.

For ordinary pull-request integration, the structural ruleset permits squash
or rebase and rejects merge commits. The repository's protected-integration
procedure is separate: it may use the explicit owner bypass only after binding
the exact reviewed signed commit, required checks, changed paths, and expected
base. The no-bypass product rule remains effective.

Required job names are protection interfaces. A workflow or job rename must be
coordinated with its ruleset and verified from an emitted check run before the
old required name is removed.

## Mutable GitHub state

Workflow files and this catalogue are versioned. Active workflow records,
rulesets, run histories, and repository settings are GitHub state and can
change independently.

The Actions interface may continue to display records created by workflows
that are no longer present on the default branch. It must not be used alone to
infer the repository's branch model. Before a protected change, an operator
must compare the live rulesets and emitted checks with this guide and the
applicable runbook.

## Human-controlled boundaries

Automation may inspect, validate, and build non-production candidates. It may
not install or upgrade a production NAS, run the administrator bootstrap,
change firewall or routing state, reboot DSM, approve its own change, or
publish a stable release without explicit maintainer approval.
