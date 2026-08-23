# Synology Product CI Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Make ordinary downstream pull requests run one focused, fork-owned Synology product gate while reserving the inherited full upstream compatibility matrix for explicit or manual upstream-version validation.

**Architecture:** Add one read-only `synology-product` workflow whose single job runs the existing Synology source, shell, patch, package-script, and focused Go validators without caches, secrets, private runners, builds, releases, or NAS access. Remove automatic pull-request triggers only from the three inherited heavy workflows, retain their push and merge-queue behavior, and expose them through `workflow_dispatch`; keep the lightweight Go workflows automatic and preserve the inherited full-CI aggregators unchanged.

**Tech Stack:** GitHub Actions YAML, Bash, Python 3 standard library contract assertions, repository-pinned Go, ShellCheck, actionlint, Git.

**Spec:** `docs/product/unjailed-synology-contract.md`

## Global Constraints

- Work only on `codex/agent-upgrade-workflow` starting at `b938683769f6f1a2581fb4057dbbddd74b5ce9e5` with PR base `release/v1.98.9-synology` at `20c86229955a3d03de01901aee1499cab87c571d`.
- Preserve the seven protected blob identities recorded in `release/upgrade-baseline.json`.
- Keep `checklocks.yml`, `golangci-lint.yml`, and `vet.yml` unchanged so their existing Go path-filtered pull-request coverage remains automatic.
- Preserve all external GitHub Actions at full 40-character commit SHAs.
- Keep the inherited `fuzz` job restricted to pull requests in `tailscale/tailscale`; it covers only upstream `net/stun.FuzzStunParser`, not Synology, DSM, SPK, package, patch, or netfilter behavior.
- Preserve downstream `vm,fuzz` allowed skips for `merge_blocker` and `check_mergeability`; preserve zero allowed skips for `check_mergeability_strict`.
- Do not build either SPK, install or publish a package, modify a NAS or firewall, fetch or tag, update rulesets, merge the PR, or mutate retained evidence, worktrees, archives, or caches.
- Create one signed commit containing exactly one `Signed-off-by` trailer and push it normally without force only after all validation passes.

---

### Task 1: Establish the executable CI-lane contract

**Files:**
- Modify: `tests/releases/github-actions-fork-portability.sh`

**Interfaces:**
- Consumes: raw tracked workflow text from `.github/workflows/vet.yml`, `.github/workflows/test.yml`, `.github/workflows/docker-file-build.yml`, `.github/workflows/natlab-integrationtest.yml`, and the initially absent `.github/workflows/synology-product.yml`.
- Produces: one deterministic offline regression command that validates effective top-level trigger blocks, effective job blocks, exact runner and checkout policy, required product commands, and retained full-CI fork rules.

- [ ] **Step 1: Extend the Python contract over real workflow files**

Add indentation-aware helpers for top-level blocks, trigger mappings, job mappings, job blocks, and checkout-step blocks. Require exactly these properties:

```text
synology-product triggers: pull_request, workflow_dispatch
synology-product pull_request bases: release/*-synology, synology/main
synology-product only job id/name: synology-product
synology-product runner: ubuntu-24.04
synology-product timeout-minutes: 45
synology-product permissions: contents: read
checkout: actions/checkout@de0fac2e4500dabe0009e67214ff5f5447ce83dd
checkout fetch-depth: 0
test triggers: push, merge_group, workflow_dispatch
docker-file-build triggers: push, workflow_dispatch
natlab-integrationtest triggers: push, merge_group, workflow_dispatch
```

Require the job text to invoke the seven `tests/releases` commands, a sorted non-empty `release/dist/synology/tests/*-test.sh` inventory, the six exact focused Go packages with `-count=1`, `git diff --check`, and a final porcelain status check covering tracked and untracked files. Retain the existing vet, Windows, upstream-only fuzz, downstream allowed-skips, strict aggregator, and `PKG_DEPS` LF assertions.

- [ ] **Step 2: Run the contract and observe RED**

Run:

```bash
bash tests/releases/github-actions-fork-portability.sh
```

Expected: exit 1 with failures for the absent `synology-product` workflow and the still-automatic `pull_request` triggers in `test.yml`, `docker-file-build.yml`, and `natlab-integrationtest.yml`; existing fork portability assertions continue to pass.

### Task 2: Add the focused product lane and make inherited heavy CI explicit

**Files:**
- Create: `.github/workflows/synology-product.yml`
- Modify: `.github/workflows/test.yml`
- Modify: `.github/workflows/docker-file-build.yml`
- Modify: `.github/workflows/natlab-integrationtest.yml`

**Interfaces:**
- Consumes: existing repository-owned validators and `actions/checkout` pinned at `de0fac2e4500dabe0009e67214ff5f5447ce83dd`.
- Produces: stable job/check name `synology-product` for ordinary downstream pull requests and manual entry points for inherited heavy compatibility workflows.

- [ ] **Step 1: Create the one-job product workflow**

Create `.github/workflows/synology-product.yml` with only `pull_request` for bases `release/*-synology` and `synology/main`, plus `workflow_dispatch`. Define one job named and keyed `synology-product`, `permissions: contents: read`, `runs-on: ubuntu-24.04`, and `timeout-minutes: 45`. Check out full history without credentials using:

```yaml
- name: Check out source
  uses: actions/checkout@de0fac2e4500dabe0009e67214ff5f5447ce83dd # v6.0.2
  with:
    fetch-depth: 0
    persist-credentials: false
```

The validation step uses `shell: bash`, `set -euo pipefail`, fails clearly when `shellcheck` is unavailable, invokes in order:

```bash
bash tests/releases/version-preparation-contract.sh
bash tests/releases/prepare-version-workflow.sh all
bash tests/releases/control-pre-commit.sh
bash tests/releases/promoted-patch-inventory.sh
bash tests/releases/github-actions-fork-portability.sh
bash tests/releases/shellcheck.sh
bash tests/releases/diff-check.sh
```

It then finds `release/dist/synology/tests/*-test.sh`, sorts with `LC_ALL=C sort`, fails on an empty inventory, runs each with Bash, and executes:

```bash
export PATH="$PWD/tool:$PATH"
./tool/go test -count=1 \
  ./release/dist/synology \
  ./cmd/tailscale/cli \
  ./cmd/tailscaled \
  ./ipn/ipnlocal \
  ./util/linuxfw \
  ./wgengine/router
git diff --check
git status --porcelain=v1 --untracked-files=all
```

Fail if the final status output is non-empty.

- [ ] **Step 2: Make only the heavy inherited pull-request triggers explicit**

Delete the `pull_request` trigger from `.github/workflows/test.yml`, `.github/workflows/docker-file-build.yml`, and `.github/workflows/natlab-integrationtest.yml`. Add an empty `workflow_dispatch:` trigger to each. Retain every existing push branch, both existing `merge_group` blocks, all jobs, action pins, runner selections, commands, and aggregator semantics byte-for-byte otherwise.

- [ ] **Step 3: Run the focused contract and observe GREEN**

Run:

```bash
bash tests/releases/github-actions-fork-portability.sh
```

Expected: exit 0 with the fork-portability, CI-lane ownership, and `PKG_DEPS` LF PASS messages.

### Task 3: Document the validation ownership boundary

**Files:**
- Modify: `docs/product/unjailed-synology-contract.md`
- Modify: `docs/runbooks/agent-version-preparation.md`

**Interfaces:**
- Consumes: the implemented `synology-product` command inventory and explicit inherited compatibility workflow triggers.
- Produces: reviewer-facing ownership and handoff requirements that do not imply package build, release, installation, or Synology fuzz coverage.

- [ ] **Step 1: Extend the product contract**

Add a `CI ownership and validation boundary` section stating that `synology-product` is the ordinary downstream pull-request gate and enumerating its source contracts, preparation fixtures, shell/static checks, protected patch inventory, Synology shell tests, focused Go packages, diff cleanliness, and repository cleanliness. State that inherited upstream compatibility CI is explicit/manual for upstream-version upgrades and that upstream OSS-Fuzz exercises only `net/stun.FuzzStunParser`, not SPK, DSM, package metadata, patches, bootstrap, TUN, or netfilter behavior.

- [ ] **Step 2: Extend the preparation handoff**

Require a green `synology-product` check on ordinary downstream pull requests and an attended manual full `CI` run for a real upstream-version upgrade before handoff. State explicitly that neither lane builds, releases, publishes, or installs either SPK and neither authorizes NAS or firewall mutation.

### Task 4: Validate the complete change and preserved boundaries

**Files:**
- Verify: all files changed by Tasks 1-3
- Verify unchanged: the seven paths recorded by `release/upgrade-baseline.json`

**Interfaces:**
- Consumes: the complete proposed tree and the retained control worktree at `/home/ateight/development/tailscale-synology-unjailed/tailscale-synology-dsm-control`.
- Produces: fresh RED/GREEN, syntax, static-analysis, source-test, protected-byte, diff, and clean-state evidence.

- [ ] **Step 1: Validate changed shell and workflow syntax**

Run:

```bash
bash -n tests/releases/github-actions-fork-portability.sh
shellcheck --severity=style tests/releases/github-actions-fork-portability.sh
actionlint .github/workflows/synology-product.yml \
  .github/workflows/docker-file-build.yml \
  .github/workflows/natlab-integrationtest.yml
```

Use the exact cached ShellCheck 0.11.0 and actionlint 1.7.12 binaries managed by the retained control-worktree verifier. The inherited `test.yml` has 21 existing actionlint diagnostics at the starting SHA; run actionlint against the starting blob and the trigger-only working-tree file, normalize source coordinates, and require exact diagnostic equivalence rather than changing inherited job content. Also run the control verifier's offline aggregate from the control checkout:

```bash
bash scripts/validate-repository.sh \
  --source-environment /home/ateight/development/tailscale-synology-unjailed/tailscale-synology-dsm \
  --fast
```

- [ ] **Step 2: Run the product workflow commands locally in order**

Run from the feature worktree:

```bash
bash tests/releases/version-preparation-contract.sh
bash tests/releases/prepare-version-workflow.sh all
bash tests/releases/control-pre-commit.sh
bash tests/releases/promoted-patch-inventory.sh
bash tests/releases/github-actions-fork-portability.sh
bash tests/releases/shellcheck.sh
bash tests/releases/diff-check.sh
```

Run every sorted `release/dist/synology/tests/*-test.sh`, require a non-empty inventory, then run:

```bash
export PATH="$PWD/tool:$PATH"
./tool/go test -count=1 \
  ./release/dist/synology \
  ./cmd/tailscale/cli \
  ./cmd/tailscaled \
  ./ipn/ipnlocal \
  ./util/linuxfw \
  ./wgengine/router
git diff --check
```

- [ ] **Step 3: Verify protected blobs and exact scope**

Parse `release/upgrade-baseline.json`, compare every protected path's current Git blob and SHA-256 to the recorded values, and require no diff for those paths from `8c9fe5239ee57a89ce687fc8c7608d3df91f6ede`. Inspect `git diff --stat`, `git diff`, and `git status --short --branch`; require only the planned workflow, contract-test, documentation, and plan files, with no product blob, package, patch, checksum, NAS, evidence, worktree, archive, or cache change.

- [ ] **Step 4: Self-review plan and implementation**

Compare every product-spec and owner requirement to a concrete plan task and changed line. Scan this plan for unresolved-template language or deferred implementation instructions; require no match. Re-run the focused contract after review.

### Task 5: Commit, push, and verify PR replacement checks

**Files:**
- Commit only the paths listed in Tasks 1-3 and this plan.

**Interfaces:**
- Consumes: a fully validated clean intended diff and existing signing identity/style.
- Produces: one normally pushed signed commit on `codex/agent-upgrade-workflow` and a new automatic `synology-product` PR check.

- [ ] **Step 1: Recheck race guards**

Require local HEAD and the remote feature ref to remain `b938683769f6f1a2581fb4057dbbddd74b5ce9e5`, PR #7 to remain open with base `release/v1.98.9-synology` at `20c86229955a3d03de01901aee1499cab87c571d`, and the worktree to contain only the intended changes.

- [ ] **Step 2: Create one signed and signed-off commit**

Stage only the planned files and run:

```bash
git commit -S -s -m "ci: add focused Synology product gate"
```

Verify `git verify-commit HEAD`, a good SSH signature, and exactly one `Signed-off-by` trailer.

- [ ] **Step 3: Push without force and verify**

Push only `refs/heads/codex/agent-upgrade-workflow` to the same origin ref. If the known system SSH configuration error occurs, use only:

```bash
git -c core.sshCommand='ssh -F /dev/null -o BatchMode=yes' push \
  origin \
  refs/heads/codex/agent-upgrade-workflow:refs/heads/codex/agent-upgrade-workflow
```

Verify the remote ref equals the new commit, PR #7 remains open with the expected base and new head, GitHub reports a verified signature, the registered feature worktree is clean, and an automatic `synology-product` run starts. Do not expect or manually start a replacement inherited 30-job `CI` run; do not rerun or cancel any workflow.
