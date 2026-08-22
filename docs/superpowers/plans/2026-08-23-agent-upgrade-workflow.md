# Agent Upgrade Workflow Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Provide one offline, fail-closed command that prepares an explicitly pinned Tailscale Synology version in an isolated worktree and emits validated review artifacts.

**Architecture:** Promote the minimum existing control layer into the candidate source branch, then extend `scripts/release/prepare-worktree.sh` with a separate explicit `prepare-version` mode. A real temporary Git fixture drives the behavior through TDD; the command stages artifacts until signed replay and patch round-trip validation complete.

**Tech Stack:** Bash, Git worktrees, SSH commit signing, Python 3 standard library for strict JSON/schema checks, SHA-256, repository-pinned Go.

**Spec:** `docs/superpowers/specs/2026-08-23-agent-upgrade-workflow-design.md`

## Global Constraints

- Base commit is exactly `8c9fe5239ee57a89ce687fc8c7608d3df91f6ede`.
- Never recreate or alter the seven protected blobs enumerated in the spec.
- Dependency declaration is exactly `[iptables-netfilter-extensions]`.
- Dependency minimum is exactly `pkg_min_ver=1.1.0-3`.
- Dependency and Tailscale DSM minimum is exactly `7.3-86009`.
- Production r2/new lineage contains no `os_max_ver`.
- New downstream commits are signed and contain exactly one `Signed-off-by` trailer.
- No fetch, push, pull request, tag creation, release, publication, SPK build, dependency-SPK build, NAS install, root bootstrap, firewall mutation, or reboot.

---

### Task 1: Promote the source-worktree control layer

**Files:**
- Create from accepted control blobs: `AGENTS.md`
- Create from accepted control blobs: `CLAUDE.md`
- Create from accepted control blobs: `.githooks/README.md`
- Create from accepted control blobs: `.githooks/commit-msg`
- Create from accepted control blobs: `.githooks/pre-commit`
- Create from accepted control blobs: `scripts/setup-worktree.sh`
- Create from accepted control blobs: `scripts/release/common.sh`
- Create from accepted control blobs: `scripts/release/prepare-worktree.sh`
- Create from accepted control blobs: `scripts/README.md`
- Create from accepted control blobs: `tests/README.md`
- Create from accepted control blobs: `release/manifest.yaml`
- Create from accepted control blobs: `docs/runbooks/tailscale-synology-version-update.md`
- Add missing accepted lineage files under: `patches/v1.98.9/`

**Interfaces:**
- Consumes: exact blobs from `e6cc919d7fc5ee35e14bb1aa56d33ec782c2c016` and the seven protected candidate blobs.
- Produces: source-worktree instructions, worktree setup, release helpers, existing preparation interface, historical lineage, and accepted manifest for later tasks.

- [ ] **Step 1: Record source blob selections and collision decisions**

Run:

```bash
git diff --name-status HEAD e6cc919d7fc5ee35e14bb1aa56d33ec782c2c016 -- \
  AGENTS.md CLAUDE.md .githooks scripts/setup-worktree.sh \
  scripts/release/common.sh scripts/release/prepare-worktree.sh \
  scripts/README.md tests/README.md release/manifest.yaml \
  docs/runbooks/tailscale-synology-version-update.md \
  patches/v1.98.9
```

Expected: control assets are absent from the candidate except the protected
canonical patch and checksum, whose candidate blobs remain authoritative.

- [ ] **Step 2: Promote exact non-colliding control blobs**

Run `git restore --source=e6cc919d7fc5ee35e14bb1aa56d33ec782c2c016 --` for the listed files and for lineage paths other than
`patches/v1.98.9/synology-netfilter.patch` and
`patches/v1.98.9/synology-netfilter.patch.sha256`.

Expected: promoted files match their control-commit blobs byte for byte and the
two protected patch blobs still match the candidate.

- [ ] **Step 3: Verify shell syntax and protected identities**

Run:

```bash
bash -n scripts/setup-worktree.sh scripts/release/common.sh \
  scripts/release/prepare-worktree.sh .githooks/commit-msg .githooks/pre-commit
git diff --exit-code 8c9fe5239ee57a89ce687fc8c7608d3df91f6ede -- \
  cmd/tailscale/cli/up.go cmd/tailscaled/tailscaled.go ipn/ipnlocal/local.go \
  util/linuxfw/iptables_runner.go wgengine/router/osrouter/router_linux.go \
  patches/v1.98.9/synology-netfilter.patch \
  patches/v1.98.9/synology-netfilter.patch.sha256
```

Expected: both commands exit 0.

- [ ] **Step 4: Commit the promoted control layer**

```bash
git add AGENTS.md CLAUDE.md .githooks scripts/setup-worktree.sh \
  scripts/release/common.sh scripts/release/prepare-worktree.sh \
  scripts/README.md tests/README.md release/manifest.yaml \
  docs/runbooks/tailscale-synology-version-update.md \
  patches/v1.98.9
git commit -S -s -m "chore: promote Synology release controls"
```

Expected: the commit verifies with `git verify-commit` and has one sign-off.

### Task 2: Establish executable upgrade contracts

**Files:**
- Create: `release/version-preparation.schema.json`
- Create: `release/upgrade-baseline.json`
- Create: `docs/product/unjailed-synology-contract.md`
- Create: `docs/runbooks/agent-version-preparation.md`
- Create: `docs/templates/agent-evidence-report.md`
- Modify: `AGENTS.md`

**Interfaces:**
- Consumes: immutable candidate identities and fixed Synology contract from the design spec.
- Produces: `schema_version = 1` JSON contract consumed by `prepare-worktree.sh`; concise agent rules and a standard evidence report structure.

- [ ] **Step 1: Write a failing contract validation test**

Add `tests/releases/version-preparation-contract.sh` that invokes a Python
strict-JSON validator against `release/upgrade-baseline.json` and
`release/version-preparation.schema.json`, then checks actual candidate blobs
and the exact `PKG_DEPS` bytes. The test must require all safety booleans to be
false and reject an `os_max_ver` field.

- [ ] **Step 2: Run the contract test and observe RED**

Run:

```bash
bash tests/releases/version-preparation-contract.sh
```

Expected: FAIL because the baseline and schema files do not exist.

- [ ] **Step 3: Add the minimal machine-readable contracts**

Create strict JSON files containing the exact candidate commit/tree, seven
protected Git blob and SHA-256 pairs, exact dependency lines, DSM floor,
`os_max_ver_allowed: false`, and false capabilities for every prohibited side
effect. The schema permits no unknown top-level members.

- [ ] **Step 4: Run the contract test and observe GREEN**

Run `bash tests/releases/version-preparation-contract.sh`.

Expected: PASS with actual file, Git blob, checksum, dependency, and safety
checks.

- [ ] **Step 5: Add concise product, runbook, report, and root-agent docs**

Document that unjailed means the daemon uses kernel TUN and Linux netfilter,
supports routing preferences, and gates startup on administrator-installed
root runtime prerequisites. Document the exact new command inputs/outputs and
reuse the report template sections defined by the spec. Append a short
`Agent version preparation` section to `AGENTS.md` pointing to these contracts.

- [ ] **Step 6: Commit the contracts**

```bash
git add AGENTS.md release/version-preparation.schema.json \
  release/upgrade-baseline.json docs/product/unjailed-synology-contract.md \
  docs/runbooks/agent-version-preparation.md \
  docs/templates/agent-evidence-report.md \
  tests/releases/version-preparation-contract.sh
git commit -S -s -m "docs: define agent upgrade contracts"
```

Expected: contract test passes and commit signature/sign-off verify.

### Task 3: Add the offline success fixture and minimal preparation mode

**Files:**
- Create: `tests/releases/prepare-version-workflow.sh`
- Modify: `scripts/release/prepare-worktree.sh`
- Modify: `scripts/release/common.sh`

**Interfaces:**
- Consumes: `prepare-version` arguments from the spec and the version-preparation schema.
- Produces: an isolated signed worktree and atomically installed artifacts at `--output-root`.

- [ ] **Step 1: Write the success fixture first**

The test creates a temporary repository, an old base, two ordered logical
commits, a new upstream commit tagged `v2.0.0`, an SSH signing key, and a bare
origin. It invokes:

```bash
bash scripts/release/prepare-worktree.sh prepare-version \
  --source-repo "$fixture_repo" \
  --upstream-tag v2.0.0 \
  --upstream-commit "$new_upstream" \
  --previous-upstream-commit "$old_upstream" \
  --previous-release-commit "$old_release" \
  --new-version 2.0.0 \
  --downstream-revision r1 \
  --target-branch work/v2.0.0-synology-r1 \
  --target-worktree "$prepared_worktree" \
  --output-root "$artifacts" \
  --confirm-create
```

Assert two signed commits in source order, one sign-off each, exact upstream
base, schema-valid manifest, two ordered mail patches, matching prepared and
round-trip tree IDs, fixed Synology contract, and unchanged origin/tag refs.

- [ ] **Step 2: Run the success fixture and observe RED**

Run `bash tests/releases/prepare-version-workflow.sh success`.

Expected: FAIL because `prepare-version` is unsupported.

- [ ] **Step 3: Implement strict argument and identity preflight**

Add `prepare-version` dispatch and validate full SHAs, version/revision/branch
forms, clean source worktree, local tag peeling, old ancestry, non-empty linear
range, absent targets, signer configuration, required commands, and exact
baseline safety contract. `--plan-only` prints exact identities without
mutation; `--confirm-create` is required otherwise.

- [ ] **Step 4: Implement ordered signed replay**

Create the target worktree at the exact new upstream commit. For each
`git rev-list --reverse --topo-order old..tip` entry, cherry-pick without
committing, strip all inherited `Signed-off-by` trailers from its message, and
commit with `git commit -S -s -F`. Verify the commit signature and exactly one
sign-off immediately before continuing.

- [ ] **Step 5: Implement staged export and round trip**

Export mail patches into a same-parent staging directory, derive `series` from
actual filenames, compute checksums, write strict JSON and Markdown artifacts,
apply the series in a temporary detached worktree, compare tree IDs, then rename
the staging directory to `--output-root`.

- [ ] **Step 6: Run success fixture and observe GREEN**

Run `bash tests/releases/prepare-version-workflow.sh success`.

Expected: PASS and the test removes only its own temporary worktrees.

- [ ] **Step 7: Commit the successful workflow slice**

```bash
git add scripts/release/common.sh scripts/release/prepare-worktree.sh \
  tests/releases/prepare-version-workflow.sh
git commit -S -s -m "feat: prepare pinned Synology versions"
```

Expected: focused workflow and contract tests pass; commit verifies.

### Task 4: Prove mismatch and conflict fail closed

**Files:**
- Modify: `tests/releases/prepare-version-workflow.sh`
- Modify: `scripts/release/prepare-worktree.sh`
- Modify: `scripts/release/common.sh`

**Interfaces:**
- Consumes: the preparation mode from Task 3.
- Produces: stable nonzero behavior with no publication or final artifacts on invalid identity or replay conflict.

- [ ] **Step 1: Add the mismatched-tag test and observe RED if needed**

Invoke `--plan-only` with `v2.0.0` and a different full commit. Assert nonzero,
no target branch/worktree/output/staging directory, and unchanged tag/origin
refs.

- [ ] **Step 2: Add the replay-conflict test and observe RED**

Create a new upstream commit that edits the same line as the first downstream
logical commit. Assert nonzero, no final output, no `CHERRY_PICK_HEAD`, no
unmerged entries, unchanged tag/origin refs, and a clear `STOP` message naming
the source commit that conflicted.

- [ ] **Step 3: Implement minimal fail-closed cleanup**

On replay failure, run `git cherry-pick --abort`, remove only the workflow's
private artifact staging directory, leave the isolated target worktree for
review, and exit with the failing Git status. Never delete or reset a path that
existed before invocation.

- [ ] **Step 4: Run all fixture cases and observe GREEN**

Run:

```bash
bash tests/releases/prepare-version-workflow.sh all
```

Expected: success, mismatch, and conflict cases pass; origin and tag snapshots
remain identical in every case.

- [ ] **Step 5: Commit fail-closed behavior**

```bash
git add scripts/release/common.sh scripts/release/prepare-worktree.sh \
  tests/releases/prepare-version-workflow.sh
git commit -S -s -m "test: enforce fail-closed version preparation"
```

Expected: focused tests and commit verification pass.

### Task 5: Complete documentation and standard evidence reporting

**Files:**
- Modify: `docs/runbooks/tailscale-synology-version-update.md`
- Modify: `docs/runbooks/agent-version-preparation.md`
- Modify: `scripts/README.md`
- Modify: `tests/README.md`

**Interfaces:**
- Consumes: the tested CLI and artifact contract.
- Produces: one unambiguous operator/agent route to the new mode and explicit handoff boundaries.

- [ ] **Step 1: Document exact plan-only and confirmed commands**

Add commands using explicit example-only SHAs, label them as examples, explain
local-object prerequisites, output layout, conflict handling, and review steps.

- [ ] **Step 2: Document evidence and PR handoff**

Require attaching `manifest.json`, `SHA256SUMS`, `preparation-report.md`,
`git range-diff` review notes, signature/sign-off verification, and test output.
State that PR creation and all publication remain separate human-authorized
actions.

- [ ] **Step 3: Validate docs and commit**

Run available Markdown lint in offline mode if present, then:

```bash
git add docs/runbooks/tailscale-synology-version-update.md \
  docs/runbooks/agent-version-preparation.md scripts/README.md tests/README.md
git commit -S -s -m "docs: add version preparation runbook"
```

Expected: docs reflect the tested interface and commit verifies.

### Task 6: Focused and broad verification

**Files:**
- Modify only if a failing test exposes a tested workflow defect.

**Interfaces:**
- Consumes: complete feature tree.
- Produces: fresh verification evidence and a requirements checklist.

- [ ] **Step 1: Run focused contract and workflow tests**

```bash
bash tests/releases/version-preparation-contract.sh
bash tests/releases/prepare-version-workflow.sh all
```

- [ ] **Step 2: Run all Synology shell regression tests**

```bash
for test_script in release/dist/synology/tests/*.sh; do
  bash "$test_script"
done
```

- [ ] **Step 3: Run offline focused Go tests through pinned Go**

```bash
env GOPROXY=off GOTOOLCHAIN=local \
  GOCACHE=/tmp/tailscale-agent-upgrade-go-cache \
  GOMODCACHE=/home/ateight/development/tailscale-synology-unjailed/go/pkg/mod \
  ./tool/go test ./release/dist/synology ./wgengine/router/osrouter \
  ./cmd/tailscale/cli ./ipn/ipnlocal ./util/linuxfw
```

- [ ] **Step 4: Run syntax and available style checks**

Run `bash -n` over repository-owned shell files, `shellcheck` over changed shell
files, `shfmt -d` if installed, strict JSON parsing, and Markdown/YAML tools only
when locally available without downloads.

- [ ] **Step 5: Verify patches and protected blobs**

Run the canonical checksum from `patches/v1.98.9`, validate the promoted
historical SHA256 inventory, run the synthetic patch round trip again, and run
`git diff --exit-code 8c9fe523...` over all seven protected paths.

- [ ] **Step 6: Verify every new commit**

For each commit in `8c9fe523..HEAD`, run `git verify-commit` and assert exactly
one `Signed-off-by` trailer. Confirm no prohibited remote or tag ref changed.

### Task 7: Evidence-backed cleanup and post-cleanup inventory

**Files:**
- Create: `docs/cleanup/2026-08-23-pre-cleanup-manifest.md`
- Create: `docs/cleanup/2026-08-23-post-cleanup-inventory.md`

**Interfaces:**
- Consumes: verified implementation state and top-level workspace inventory.
- Produces: auditable keep/remove decisions and a final inventory; no ambiguous deletion.

- [ ] **Step 1: Enumerate cleanup candidates without deleting**

List only named C0R/controller/state-machine scripts, temporary preflight,
controller/correction/evidence roots, detached dirty evidence worktrees, and
redundant top-level patch copies. Record absolute path, type, size, Git/worktree
state, checksum/tree identity, uniqueness evidence, and `KEEP`, `REMOVE`, or
`AMBIGUOUS`.

- [ ] **Step 2: Prove detached-worktree equivalence**

For each candidate, record HEAD, index tree, worktree status, untracked files,
and compare its staged tree to accepted candidate tree
`6d171c2a01c0fafb9567f3f4bc49bdd4f7ff7392`. Only an equal staged tree with no
unique unstaged/untracked product change can be `REMOVE`.

- [ ] **Step 3: Prove patch-copy equality or distinction**

Record SHA-256 for each top-level copy, the protected canonical patch, and its
checksum. Mark a copy `REMOVE` only when it is byte-identical and no retained
evidence references that absolute copy as required current-release evidence.

- [ ] **Step 4: Commit the pre-cleanup manifest before deletion**

```bash
git add docs/cleanup/2026-08-23-pre-cleanup-manifest.md
git commit -S -s -m "docs: record workspace cleanup decisions"
```

- [ ] **Step 5: Remove only manifest-approved targets**

Use exact absolute paths. Remove registered worktrees with `git worktree remove`
from outside them; do not force removal. Delete only unregistered targets marked
`REMOVE`. Leave every `AMBIGUOUS` path unchanged.

- [ ] **Step 6: Write and commit the post-cleanup inventory**

Record retained source/base, r2 candidate, control, contract, feature worktree,
branches, canonical assets, history, SPKs/evidence, and remaining ambiguous
items. Include `git worktree list --porcelain` and checksum verification.

```bash
git add docs/cleanup/2026-08-23-post-cleanup-inventory.md
git commit -S -s -m "docs: record post-cleanup workspace inventory"
```

### Task 8: Finish the branch without integration or publication

**Files:**
- No file changes expected.

**Interfaces:**
- Consumes: fresh complete verification evidence.
- Produces: preserved local branch/worktree and final implementation report.

- [ ] **Step 1: Re-run the complete relevant verification suite**

Repeat Task 6 on the final tree and inspect `git status --short --branch`.

- [ ] **Step 2: Capture final identity and diff**

Record branch, HEAD, tree, commit list, diff statistics, worktree path, protected
blob verification, cleanup reports, and any unavailable optional tool.

- [ ] **Step 3: Preserve local state**

Keep `codex/agent-upgrade-workflow` and its worktree. Do not merge, push, create
a pull request, tag, release, publish, or operate a NAS.
