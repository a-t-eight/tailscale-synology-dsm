# Automation governance design

## Purpose

Make the repository's cross-branch GitHub Actions model legible from one
authoritative public guide without changing the accepted r2 source, release
tag, package, evidence, published release, live rulesets, or production DSM
state.

The guide will explain why control workflows and source workflows coexist in
the Actions interface, which checks apply to each kind of change, and what each
validation lane proves. Repository-pinned validation will prevent the guide's
workflow and status names from silently diverging from the workflow files.

## Current architecture

The repository has distinct branch roots:

- `synology/main` defines control governance and release operations;
- `release/<version>-synology` defines the accepted downstream source and its
  source-validation workflows;
- `main` remains an upstream-only mirror.

GitHub currently retains nine active workflow records across the control and
accepted-source histories. The repository intentionally separates them into
four validation lanes:

1. control governance;
2. release operations;
3. focused Synology product validation;
4. manually attended upstream compatibility validation.

The implementation behavior is deliberate, but the public documentation does
not currently present the complete operating model in one place.

## Chosen approach

Add a public guide at `docs/governance/automation.md` and make it the
human-readable automation catalogue. Link it from the root README, repository
guide, documentation index, and existing governance material where a link can
replace duplicated explanation without weakening normative safety policy.

The guide will include one row for each workflow record that currently appears
in the Actions interface. Each row will record:

- workflow display name;
- workflow file;
- defining branch root;
- ownership classification;
- trigger category;
- emitted job or required-status name;
- relationship to repository rulesets;
- what the workflow proves;
- what it does not prove.

The guide will distinguish repository-defined behavior from mutable GitHub
state. It will not embed ruleset IDs or run IDs. It will explain that workflow
records can remain visible after their defining files move between branch
histories, so the Actions interface is not by itself an authoritative branch
catalogue.

## Alternatives considered

### Documentation without validation

This is the smallest immediate diff, but exact workflow and required-status
names could drift silently. That would undermine the guide's main purpose.

### Machine-readable manifest and generated documentation

A separate automation manifest could generate the catalogue, but it would add
another maintained interface and generation workflow. That machinery is not
proportionate to nine records and would compete with the workflow files and
guide for authority.

### Selected: guide with repository-pinned contract validation

The public guide remains the only added inventory. A focused validator reads
the catalogue and compares its exact identifiers with the corresponding
workflow definitions in the control tree and accepted-source worktree. This
detects drift without a second inventory or a live GitHub dependency.

## Validation design

Add a governance contract test that receives the explicit accepted-source
worktree already selected by `scripts/validate-repository.sh`.

The test will:

- parse the automation catalogue's machine-checkable identifier columns;
- require each documented control workflow to exist in the control tree;
- require each documented source workflow to exist in the selected pinned
  source tree;
- compare documented display names with top-level workflow `name` values;
- compare documented status names with explicit job `name` values, falling
  back to the job identifier only when no explicit name is present;
- verify the documented trigger categories against the relevant workflow
  trigger keys;
- fail on duplicate catalogue rows, missing files, missing names, or an
  unexpected catalogue size;
- make no network requests and leave both repositories unchanged.

The canonical repository validator will invoke this test after it has verified
the source environment's exact accepted commit and tree. Existing Markdown,
YAML, actionlint, secret, shell, release-contract, and whitespace checks remain
unchanged.

Mutable GitHub configuration cannot be made deterministic by a repository-only
test. Ruleset membership, active workflow records, and required-check discovery
will remain attended review items and will be documented as such.

## Naming boundary

This phase will not rename workflow files, workflow display names, job names,
or required statuses.

Display-name categorisation belongs in the next source revision, where all
downstream-owned and downstream-modified workflows can be reviewed together.
Candidate categories include `Downstream / Synology product` and
`Upstream compatibility / Full CI`.

Inherited workflow filenames will remain aligned with upstream wherever
possible. Renaming `test.yml`, `natlab-integrationtest.yml`,
`docker-file-build.yml`, or other inherited files only for presentation would
increase downstream rebase cost and can split GitHub workflow history. The
downstream-owned `synology-product.yml` and the control files `validate.yml`
and `release-candidate.yml` are already concise.

Job and required-status names such as `synology-product` and
`repository-governance` are protection contracts. They may change only with an
equivalent, atomically reviewed ruleset update that verifies emitted check
names and bypass semantics.

## Safety and release boundaries

The accepted r2 commit `0fad8b81a3e0eb86c457bc79c474bcc213834c43`,
tree `33f5c5927ae4db54b9d582650ed31cc6a2eb7161`, signed tag, package,
evidence, and published release remain frozen.

This phase will not:

- edit accepted-source or upstream-mirror branches;
- build, retag, publish, replace, or install an SPK;
- access a NAS or DSM host;
- run administrator bootstrap;
- mutate firewall or netfilter state;
- change live GitHub workflows or rulesets;
- rename workflow files, display names, jobs, or required statuses;
- approve or merge its own pull request.

## Delivery

Implementation will use an isolated control worktree and a temporary branch
based on the current remote `synology/main`. It will run the complete
repository-pinned validator against the explicit frozen accepted-source
worktree, create signed and signed-off commits, push normally, and open a pull
request for human review. Integration and cleanup remain maintainer actions.
