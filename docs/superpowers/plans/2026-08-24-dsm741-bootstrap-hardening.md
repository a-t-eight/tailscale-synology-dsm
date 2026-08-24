# DSM 7.4.1 Bootstrap Hardening Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Make the unjailed Synology startup transaction terminate safely on DSM 7.4.1, prove daemon identity before accepting or signalling PIDs, supervise the reconciler reliably, and expose the attended bootstrap at `/usr/local/bin/tailscale-synology-bootstrap`.

**Architecture:** Keep the installed package unprivileged until the attended bootstrap installs the root manifest. Package the same bootstrap source in both the root-owned outer `scripts/` metadata and package-owned `target/bin`; DSM's `usr-local-linker` exposes the target copy under `/usr/local/bin`. Initial elevation must use the root-owned outer script. The bootstrap then changes the target tree to `root:root`, making the linked copy trusted for post-bootstrap use. Keep root control files under the existing package var boundary as explicitly requested; do not mix a state-directory redesign into this fix.

**Tech Stack:** Bash, Go Synology SPK builder, tar/SPK metadata tests, DSM legacy iptables adapter.

**Spec:** `docs/product/unjailed-synology-contract.md`

## Global Constraints

- DSM minimum version remains exactly `7.3-86009`.
- `iptables-netfilter-extensions` remains exactly `1.1.0-2` or newer.
- Do not install the candidate, run bootstrap, or mutate NAS networking during implementation.
- Preserve the attended `install/status/remove` approval interface.
- The root-state directory redesign is excluded by owner direction.

---

### Task 1: Package the attended bootstrap under `/usr/local/bin`

**Files:**
- Modify: `release/dist/synology/pkgs.go`
- Modify: `release/dist/synology/pkgs_test.go`
- Modify: `release/dist/synology/files/resource`
- Modify: `release/dist/synology/files/scripts/start-stop-status`
- Modify: `release/dist/synology/files/scripts/tailscale-synology-bootstrap`

**Interfaces:**
- Produces: `target/bin/tailscale-synology-bootstrap`, mode `0755`, linked by DSM as `/usr/local/bin/tailscale-synology-bootstrap`.
- Preserves: outer `scripts/tailscale-synology-bootstrap` as the root-owned initial approval interface.
- Requires: `sudo /var/packages/Tailscale/scripts/tailscale-synology-bootstrap install` before the linked target becomes root-owned.

- [x] Add a Go test that builds the inner tar and asserts the bootstrap path, exact content, and `0755` mode.
- [x] Run the focused Go test and confirm it fails because the inner tar lacks the file.
- [x] Add the existing embedded bootstrap source to the inner tar and add the linker resource entry while preserving the stock package-user manifest.
- [x] Require the root-owned outer script for initial elevation and reject privileged use of the package-owned target copy.
- [x] Re-run the focused Go and package-contract tests.

### Task 2: Make NAT preflight cleanup bounded and observable

**Files:**
- Modify: `release/dist/synology/files/scripts/start-stop-status`
- Modify: `release/dist/synology/tests/netfilter-preflight-test.sh`

**Interfaces:**
- Produces: `cleanup_tailscale_nat_preflight CHAIN`, which returns nonzero if a successful deletion does not reduce the observable hook count.

- [x] Extend the iptables adapter so deletion can report success repeatedly without changing state.
- [x] Add regressions asserting direct and full-topology cleanup terminate after one no-progress deletion and report failure.
- [x] Run the focused shell tests and confirm the excessive-delete assertions fail.
- [x] Parse the effective parent from full `nat -S`, bound cleanup by observed hook count, and reject no-progress success.
- [x] Run success, failure, signal, existence-first, and no-progress cleanup tests.

### Task 3: Prove process identity before accepting or signalling PIDs

**Files:**
- Modify: `release/dist/synology/files/scripts/tailscale-synology-bootstrap`
- Modify: `release/dist/synology/files/scripts/start-stop-status`
- Modify: `release/dist/synology/tests/root-bootstrap-test.sh`
- Modify: `release/dist/synology/tests/start-stop-definitions-test.sh`

**Interfaces:**
- Produces: strict single-PID readers that require `/proc/PID/exe` to resolve to the packaged `tailscaled` executable.
- Produces: reconciler identity validation against its exact script argument.

- [x] Add malformed, unrelated-process, stale-PID, and valid-process fixtures.
- [x] Run the focused tests and confirm current PID existence checks accept the unrelated process.
- [x] Replace digit stripping and raw `cat` expansion with strict parsing and executable identity checks.
- [x] Revalidate identity immediately before TERM/KILL operations.
- [x] Run the focused bootstrap and lifecycle-definition tests.

### Task 4: Bound package lifecycle and establish reconciler liveness

**Files:**
- Modify: `release/dist/synology/files/scripts/tailscale-synology-bootstrap`
- Modify: `release/dist/synology/files/scripts/start-stop-status`
- Modify: `release/dist/synology/tests/root-bootstrap-test.sh`
- Modify: `release/dist/synology/tests/start-stop-definitions-test.sh`

**Interfaces:**
- Produces: bounded `synopkg start/stop` calls using DSM's `timeout` command.
- Produces: reconciler startup requiring two consecutive identity checks.

- [x] Add hung `synopkg start`/`stop` fixtures and a fast-exiting reconciler fixture.
- [x] Confirm the fixtures fail against current behavior.
- [x] Add validated DSM timeout configuration, fail a timed-out stop before mutation, and fail rollback when DSM cannot be stopped safely.
- [x] Require consecutive reconciler checks and terminate a failed child before removing its PID file.
- [x] Make package health nonzero when the daemon exists without its required reconciler.
- [x] Run the focused tests.

### Task 5: Full verification and SPK inspection

**Files:**
- Modify if required by the packaged contract: `tool/build-synology-root-bootstrap.sh`

- [x] Run `bash -n` and ShellCheck, including every extensionless package shell entry point.
- [x] Run every `release/dist/synology/tests/*.sh` test.
- [x] Run `./tool/go test ./release/dist/synology` and the focused Synology Go packages required by repository policy.
- [x] Build two non-production Synology candidates from the same source and compare checksums.
- [x] Inspect outer metadata and inner `package.tgz`; assert the linker declaration, stock/root manifests, file mode, content hash, and `/usr/local/bin` target mapping.
- [ ] Run the release-contract, patch-inventory, patch-round-trip, whitespace, and `git diff --check` gates.
- [ ] Record fresh-install DSM UAT of the root-owned outer approval command, root ownership transition, restart, reboot, rollback, reconciler, subnet, and exit-node behavior; do not mutate a NAS automatically.
