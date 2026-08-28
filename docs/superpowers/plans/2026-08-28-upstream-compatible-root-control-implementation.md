# Upstream-Compatible Root Control Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Produce a reviewable r3 Synology candidate that authenticates every root-promoted package file and isolates downstream bootstrap and reconciliation control state without changing upstream daemon application paths.

**Architecture:** Build a deterministic manifest into the outer SPK, use the root-owned outer bootstrap to stage and atomically promote the complete target before activating root privilege, and keep only reconciler PID/pending state in a validated root-only `/run` directory. Preserve upstream `SYNOPKG_PKGVAR`, LocalAPI, UI and logrotate contracts; update the control-tree SPK inspector after the source manifest format is fixed.

**Tech Stack:** Go Synology package builder and tests, Bash lifecycle/bootstrap/reconciler scripts, Python static archive inspection embedded in repository-owned Bash, deterministic SPK build tooling.

**Spec:** `docs/superpowers/specs/2026-08-28-upstream-compatible-root-control-design.md`

## Global Constraints

- Source starts at accepted r2 commit `0fad8b81a3e0eb86c457bc79c474bcc213834c43` in an isolated `work/*-synology` branch.
- `tailscaled` remains UID 0 after attended bootstrap; effective `run-as: root` and `root:root` target ownership remain required.
- `tailscaled.state`, `tailscaled.sock`, `tailscaled.pid`, `tailscaled.stdout.log`, `STATE_DIRECTORY`, DSM UI access and daemon logrotate remain in their upstream locations.
- The package dependency remains `iptables-netfilter-extensions >= 1.1.0-2`; the DSM floor remains `7.3-86009`.
- `install` and `remove` mutations use only `/var/packages/Tailscale/scripts/tailscale-synology-bootstrap`; the target-linked command is status-only.
- No production NAS install, root bootstrap, firewall change, route change, reboot, release publication or tag is authorised by this plan.
- Write every behavioural test first, run it, and record the expected failure before changing production code.
- Keep manifest/build support, bootstrap promotion, reconciliation lifecycle and control-tree inspection as separate signed, signed-off commits.

---

### Task 1: Generate the deterministic root-payload manifest and r3 package identity

**Files:**
- Modify: `release/dist/synology/pkgs.go`
- Modify: `release/dist/synology/pkgs_test.go`
- Modify: `release/dist/synology/package_revision.go`
- Modify: `tool/build-synology-root-bootstrap.sh`

**Interfaces:**
- Produces: `buildRootPayloadManifest(innerPath string, dsmVersion int, packagePrivilegeFile string) ([]byte, error)`.
- Produces: manifest header `tailscale-synology-root-payload-v1` followed by sorted `file MODE SHA256 PATH` records.
- Produces: outer member `conf/root-payload.manifest`, mode `0644`, plus `conf/root-control/`, mode `0755`.
- Records installed modes for immutable package scripts, privilege templates and inner target files from `package.tgz`. DSM rewrites `conf/resource` during installation, so the bootstrap verifies that descriptor as a root-owned, single-link regular file with mode `0600` without binding its post-install bytes to the pre-install manifest.
- Advances: `synologyPackageRevision` from `2` to `3`, yielding sideload `700098098` and Package Center `720098098`.

- [ ] **Step 1: Add failing manifest unit tests**

Add focused Go tests that create a synthetic inner tarball and assert:

```go
func TestRootPayloadManifestIsCompleteAndDeterministic(t *testing.T)
func TestRootPayloadManifestRejectsUnsafeInnerMembers(t *testing.T)
func TestDSM7SPKContainsRootControlManifest(t *testing.T)
```

The expected manifest must include all regular inner files under `target/`, all
outer package scripts, `conf/PKG_DEPS`, and both immutable
privilege templates. It must exclude `conf/privilege` and itself.

- [ ] **Step 2: Run the tests and verify RED**

Run:

```bash
./tool/go test -count=1 -run '^(TestRootPayloadManifest|TestDSM7SPKContainsRootControlManifest)' ./release/dist/synology
```

Expected: FAIL because `buildRootPayloadManifest` and the SPK members do not
exist.

- [ ] **Step 3: Implement the minimal manifest builder**

Add a small manifest entry type and deterministic renderer:

```go
type rootPayloadEntry struct {
    path   string
    mode   int64
    digest [sha256.Size]byte
}

func buildRootPayloadManifest(innerPath string, dsmVersion int) ([]byte, error)
```

Parse `package.tgz` without extracting it. Reject duplicate normalised names,
absolute paths, `..`, links, devices and FIFOs. Hash regular members while
streaming. Read outer static sources from the embedded filesystem, apply the
observed installed-mode mapping, sort by destination path and render exactly
one newline-terminated record per file.

- [ ] **Step 4: Include the manifest and root-control directory in DSM 7 SPKs**

In `buildSPK`, generate the manifest before opening the outer archive and add:

```go
memFile("conf/root-payload.manifest", rootManifest, 0644),
dir("conf/root-control"),
```

Do not add either member to DSM 6 packages.

- [ ] **Step 5: Add failing r3 revision assertions, then implement them**

Change the existing package revision tests to require revision `3`, filenames
ending `700098098`/`720098098`, then run the focused test and confirm RED. Set
`synologyPackageRevision = 3` and update the build script's exact metadata
assertions; rerun to GREEN.

- [ ] **Step 6: Run Task 1 verification**

```bash
./tool/go test -count=1 ./release/dist/synology
bash -n tool/build-synology-root-bootstrap.sh
git diff --check
```

Expected: PASS with no warnings or whitespace errors.

- [ ] **Step 7: Commit Task 1**

```bash
git add release/dist/synology/pkgs.go \
  release/dist/synology/pkgs_test.go \
  release/dist/synology/package_revision.go \
  tool/build-synology-root-bootstrap.sh
git commit -S -s -m "synology: authenticate root payload manifest"
```

---

### Task 2: Promote the target transactionally from the root-owned bootstrap

**Files:**
- Modify: `release/dist/synology/files/scripts/tailscale-synology-bootstrap`
- Modify: `release/dist/synology/tests/root-bootstrap-test.sh`
- Modify: `release/dist/synology/tests/bootstrap-synopkg-path-test.sh`

**Interfaces:**
- Consumes: `conf/root-payload.manifest` format from Task 1.
- Produces: `conf/root-control/root-bootstrap.state`, mode `0644`, containing schema, mode and manifest SHA-256.
- Produces: one private `conf/root-control/transactions/active-*` directory, mode `0700`, removed after success or successful rollback.
- Produces: target promotion that replaces each manifested regular file with a validated root-owned inode before privilege activation.
- Preserves: daemon PID lookup in `${PACKAGE_ROOT}/var/tailscaled.pid`.

- [ ] **Step 1: Move the fixture contract to the new trusted paths**

Extend `setup_fixture` to create every manifested target/outer file, generate a
valid fixture manifest, and create `conf/root-control`. Update assertions to use:

```text
conf/root-control/root-bootstrap.state
conf/root-control/transactions
```

Keep a legacy `var/root-bootstrap.state` fixture for migration tests.

- [ ] **Step 2: Add and verify failing security tests**

Add one focused case per behaviour:

```bash
test_target_entrypoint_is_status_only
test_manifest_mismatch_fails_before_privilege_change
test_unmanifested_target_file_is_rejected
test_trusted_symlink_and_hardlink_are_rejected
test_open_writer_cannot_change_promoted_target
test_privilege_is_installed_after_final_target_verification
test_success_removes_private_transaction
test_legacy_state_is_not_trusted
```

For the open-writer test, hold a writable descriptor to the old target binary,
perform install, write through the descriptor, and assert the promoted path's
digest remains the manifest digest.

Run:

```bash
bash release/dist/synology/tests/root-bootstrap-test.sh
```

Expected: the new cases fail because r2 trusts two hashes, stores state/backups
under `var`, recursively chowns in place, and permits post-bootstrap target
mutations.

- [ ] **Step 3: Add trusted-path and manifest parsing primitives**

Implement narrowly scoped functions with test overrides only where existing
fixtures require them:

```bash
require_trusted_directory PATH MODE
require_trusted_regular_file PATH MODE
parse_root_payload_manifest
verify_outer_payload
inventory_target_payload
```

Use `lstat`-equivalent `stat` checks, require UID 0, exact modes, regular files
with link count one, root-owned non-writable ancestors, safe relative manifest
paths, unique entries and exact SHA-256 values. Permit only the known
root-owned DSM `target` symlink after resolving and validating its destination.

- [ ] **Step 4: Implement same-directory target staging and final verification**

After bounded package stop:

1. create the private transaction directory;
2. validate root-owned outer material and manifest;
3. take ownership of target directories without following links;
4. copy each expected target file to a root-owned same-directory temporary
   inode, set its expected mode, verify its digest, and atomically rename it;
5. perform a second no-follow inventory and reject missing/extra/unsafe entries;
6. write state with the manifest digest;
7. install the root privilege;
8. start and verify UID 0.

Do not execute target content before step 7 completes.

- [ ] **Step 5: Implement rollback and migration semantics**

Rollback restores the prior privilege, target owner and prior trusted state.
Successful rollback removes the transaction. Failed rollback retains the sole
transaction and blocks further mutation. Treat legacy r2 state as untrusted;
unlink only exact legacy regular files/symlinks after successful promotion and
leave legacy backup/log directories inert.

- [ ] **Step 6: Make the target copy status-only**

If `BOOTSTRAP_SOURCE_PATH` resolves beneath the target, allow only `status`.
Return a nonzero explanation for `install` and `remove` that names the outer
root-owned command.

- [ ] **Step 7: Run Task 2 verification**

```bash
bash release/dist/synology/tests/root-bootstrap-test.sh
bash release/dist/synology/tests/bootstrap-synopkg-path-test.sh
bash -n release/dist/synology/files/scripts/tailscale-synology-bootstrap
shellcheck -S error release/dist/synology/files/scripts/tailscale-synology-bootstrap \
  release/dist/synology/tests/root-bootstrap-test.sh \
  release/dist/synology/tests/bootstrap-synopkg-path-test.sh
```

Expected: PASS, including the recorded RED cases.

- [ ] **Step 8: Commit Task 2**

```bash
git add release/dist/synology/files/scripts/tailscale-synology-bootstrap \
  release/dist/synology/tests/root-bootstrap-test.sh \
  release/dist/synology/tests/bootstrap-synopkg-path-test.sh
git commit -S -s -m "synology: harden root payload promotion"
```

---

### Task 3: Isolate reconciler control state and use DSM system logging

**Files:**
- Modify: `release/dist/synology/files/scripts/start-stop-status`
- Modify: `release/dist/synology/files/scripts/tailscale-netfilter-reconciler`
- Modify: `release/dist/synology/tests/start-stop-definitions-test.sh`
- Modify: `release/dist/synology/tests/netfilter-reconciler-test.sh`
- Modify: `release/dist/synology/tests/netfilter-reconciler-shutdown-test.sh`

**Interfaces:**
- Consumes: bootstrap state and manifest digest under `conf/root-control`.
- Produces: validated runtime directory `${TAILSCALE_SYNOLOGY_RUNTIME_DIR:-/run/tailscale-synology}`, `root:root 0700`.
- Produces: reconciler PID `reconciler.pid` and pending marker `repair.pending` under the runtime directory.
- Preserves: `${SYNOPKG_PKGVAR}/tailscaled.sock`, daemon state/PID/stdout paths and `STATE_DIRECTORY`.
- Produces: logger invocation `/usr/bin/logger -t tailscale-netfilter-reconciler -p PRIORITY -- MESSAGE`.

- [ ] **Step 1: Add and verify failing lifecycle-path tests**

Extend the definition fixture to assert:

```bash
BOOTSTRAP_STATE_FILE="${PKG_ROOT}/conf/root-control/root-bootstrap.state"
RECONCILER_RUNTIME_DIR="${TEST_ROOT}/run/tailscale-synology"
RECONCILER_PID_FILE="${RECONCILER_RUNTIME_DIR}/reconciler.pid"
RECONCILER_PENDING_FILE="${RECONCILER_RUNTIME_DIR}/repair.pending"
SOCKET_FILE="${SYNOPKG_PKGVAR}/tailscaled.sock"
```

Add cases proving package-account `start/status/stop` never create or remove the
root runtime directory, root start rejects symlink/mode/owner drift, root stop
cleans only after process identity validation, and status never mutates stale
PID files.

Run `bash release/dist/synology/tests/start-stop-definitions-test.sh` and confirm
RED against the r2 paths and cleanup behaviour.

- [ ] **Step 2: Add and verify failing logger tests**

Add a mock logger that records tag, priority and message. Assert INFO, NOTICE,
WARNING and ERROR mappings, no `tailscale-netfilter-reconciler.log` creation,
and successful reconciliation when logger exits nonzero.

Run `bash release/dist/synology/tests/netfilter-reconciler-test.sh` and confirm
RED because r2 prints to redirected stdout.

- [ ] **Step 3: Split upstream socket storage from downstream control storage**

In both scripts, keep `PKGVAR` only for daemon paths and socket. Define the
runtime directory independently and derive reconciler PID/pending paths from it.
Create/validate it only in root start. Root stop removes exact validated files
and the empty directory. Non-root lifecycle paths never mutate it.

- [ ] **Step 4: Make status observation-only**

Change `reconciler_status` to return state without deleting a stale PID. Add a
root-only cleanup function used by start/stop. When called non-root, status may
report daemon/bootstrap state but must report reconciler detail as privileged
without changing files.

- [ ] **Step 5: Route reconciler messages through logger**

Add an overridable `LOGGER_BIN` and map levels to `daemon.info`,
`daemon.notice`, `daemon.warning` and `daemon.err`. A failed logger call emits a
single stderr diagnostic and returns success to the reconciliation loop; it
must never fall back to a package-data log.

- [ ] **Step 6: Preserve interrupted-repair semantics**

Keep same-boot recovery from `repair.pending`. Add a fixture representing a
fresh boot with no marker and incomplete hooks; it must take the ordinary
off/on repair path and restore hooks.

- [ ] **Step 7: Run Task 3 verification**

```bash
bash release/dist/synology/tests/start-stop-definitions-test.sh
bash release/dist/synology/tests/netfilter-reconciler-test.sh
bash release/dist/synology/tests/netfilter-reconciler-shutdown-test.sh
bash release/dist/synology/tests/netfilter-preflight-test.sh
shellcheck -S error release/dist/synology/files/scripts/start-stop-status \
  release/dist/synology/files/scripts/tailscale-netfilter-reconciler
```

Expected: PASS; the existing no-progress and existence-first iptables cleanup
tests remain unchanged and green.

- [ ] **Step 8: Commit Task 3**

```bash
git add release/dist/synology/files/scripts/start-stop-status \
  release/dist/synology/files/scripts/tailscale-netfilter-reconciler \
  release/dist/synology/tests/start-stop-definitions-test.sh \
  release/dist/synology/tests/netfilter-reconciler-test.sh \
  release/dist/synology/tests/netfilter-reconciler-shutdown-test.sh
git commit -S -s -m "synology: isolate reconciliation control state"
```

---

### Task 4: Enforce the manifest in the control-tree static SPK inspector

**Files:**
- Modify on a separate control branch based on the approved Task 5 design: `scripts/release/inspect-spk.sh`
- Modify: `tests/quality/inspect-spk.sh`

**Interfaces:**
- Consumes: exact manifest format fixed by source Task 1.
- Produces: static rejection of missing, malformed, duplicate, unsafe, mode-mismatched, hash-mismatched or incomplete root-payload records.

- [ ] **Step 1: Add failing malformed-SPK fixtures**

Extend the synthetic fixture builder with a valid root-payload manifest and add
fixtures for missing manifest, malformed header, duplicate record, traversal
path, hash mismatch, mode mismatch, missing covered file and extra target file.

Run:

```bash
bash tests/quality/inspect-spk.sh
```

Expected: the valid fixture fails until inspector support exists, or malformed
fixtures incorrectly pass.

- [ ] **Step 2: Parse and verify the manifest without extracting**

Extend the embedded Python inspector to parse strict ASCII records, map
`target/` records to inner members and other records to outer members, validate
canonical installed modes, stream SHA-256 values, and compare the covered roots
exactly. Retain all existing archive traversal, duplicate-member, INFO, JSON and
script-syntax checks.

- [ ] **Step 3: Run control-tree verification**

```bash
bash tests/quality/inspect-spk.sh
bash scripts/validate-repository.sh \
  --source-environment /home/ateight/development/tailscale-synology-unjailed/tailscale-synology-dsm-task5-implementation \
  --fast
```

Expected: zero failures and no regression in existing malformed fixtures.

- [ ] **Step 4: Commit Task 4 on its control branch**

```bash
git add scripts/release/inspect-spk.sh tests/quality/inspect-spk.sh
git commit -S -s -m "test: verify Synology root payload manifests"
```

---

### Task 5: Complete source regression, documentation and commit review

**Files:**
- Modify: `docs/product/unjailed-synology-contract.md`
- Modify: `docs/superpowers/plans/2026-08-24-dsm741-bootstrap-hardening.md`

**Interfaces:**
- Produces: source-branch documentation matching the implemented r3 command/path contract.
- Preserves: historical r2 plan as a completed record, with a short supersession note rather than rewritten checkboxes.

- [ ] **Step 1: Update living source documentation**

Document outer-script-only mutations, manifest promotion order, new control
paths, system logging, unchanged upstream daemon paths, accepted residual risk
and the required UAT matrix. Add only a supersession pointer to the historical
r2 hardening plan.

- [ ] **Step 2: Run the complete source test suite**

```bash
./tool/go test -count=1 ./release/dist/synology
find release/dist/synology/tests -maxdepth 1 -type f -name '*-test.sh' \
  -print -exec bash {} \;
```

Then run ShellCheck error-level validation for all files under
`release/dist/synology/files/scripts` and `release/dist/synology/tests`, shfmt
diff validation for those files, `git diff --check`, `git verify-commit`, and
exactly-one-sign-off checks for every new commit.

- [ ] **Step 3: Commit documentation**

```bash
git add docs/product/unjailed-synology-contract.md \
  docs/superpowers/plans/2026-08-24-dsm741-bootstrap-hardening.md
git commit -S -s -m "docs: define Synology r3 root-control acceptance"
```

- [ ] **Step 4: Review the complete branch**

Use direct endpoint comparison from accepted r2:

```bash
git diff --check 0fad8b81a3e0eb86c457bc79c474bcc213834c43..HEAD
git log --show-signature --format=fuller \
  0fad8b81a3e0eb86c457bc79c474bcc213834c43..HEAD
```

Confirm no upstream daemon path, socket, logrotate or iptables cleanup semantics
changed outside the approved contract.

---

### Task 6: Produce and inspect two byte-identical candidate builds

**Files:**
- Create outside Git: two explicit candidate output roots and sanitised evidence.
- Do not modify: accepted r2 evidence, tag, release assets or sealed archive.

**Interfaces:**
- Consumes: clean signed source branch and Task 4 control inspector.
- Produces: two sideload SPKs and two Package Center reference SPKs with pairwise-identical SHA-256 values.
- Produces: static inspection reports and a sanitised candidate manifest.

- [ ] **Step 1: Build candidate A from a clean state**

Use a short workspace-backed `TMPDIR`/`GOCACHE`, the repository-pinned Go tool
and fixed `SOURCE_DATE_EPOCH` derived from the signed source HEAD:

```bash
bash tool/build-synology-root-bootstrap.sh \
  /home/ateight/development/tailscale-synology-unjailed/build/task5-candidate-a
```

- [ ] **Step 2: Build candidate B independently**

Use a separate empty output/temp root with the same signed HEAD and epoch:

```bash
bash tool/build-synology-root-bootstrap.sh \
  /home/ateight/development/tailscale-synology-unjailed/build/task5-candidate-b
```

- [ ] **Step 3: Compare and inspect all SPKs**

Require byte-identical A/B hashes for each package variant. Run the control-tree
inspector against all four files, then inspect outer metadata, inner member
inventory, manifest records, modes, script syntax and package revision.

- [ ] **Step 4: Record sanitised candidate evidence**

Record source commit/tree, Go version, epoch, package filenames and SHA-256
values without workstation names, usernames, private paths, environment dumps
or unsanitised filesystem inventories.

---

### Task 7: Prepare the exact-artifact DSM UAT handoff

**Files:**
- Create in sanitised candidate evidence: `UAT.md` and expected-results record.

**Interfaces:**
- Produces: attended commands for the maintainer; performs no NAS mutation automatically.

- [ ] **Step 1: Define fresh-install and r2-upgrade gates**

Include package installation, package-account pre-bootstrap status, rejection of
target-linked mutation, outer-script install, root state/manifest verification,
UID 0, target ownership, UI/LocalAPI, and absence of downstream control files
under `@appdata`.

- [ ] **Step 2: Define lifecycle and failure gates**

Cover idempotent install, remove/re-bootstrap, restart, reboot, upgrade,
rollback, uninstall, volume migration, hostile path fixtures where safe,
interrupted repair plus reboot, and logger visibility.

- [ ] **Step 3: Define network acceptance gates**

Cover TUN, IPv4/IPv6 netfilter, subnet routing, `--accept-routes`, exit-node
operation and the existing existence-first/no-progress iptables cleanup
semantics.

- [ ] **Step 4: Stop for attended UAT approval**

Report exact SPK path and SHA-256. Do not install, bootstrap, reboot or mutate
production networking from the implementation session.
