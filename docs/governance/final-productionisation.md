# Final productionisation status

This document is the canonical status list for the remaining productionisation
work after the accepted `v1.98.96-r2` release and the August 2026 governance
closeout.

The accepted r2 release is closed and must not be rewritten. Remaining work
applies to a new downstream revision and/or a newer explicitly pinned upstream
Tailscale release.

## Product architecture invariant

The supported downstream architecture deliberately uses an attended
administrator bootstrap to promote the DSM package into a persistent root
runtime.

After successful bootstrap:

- `tailscaled` MUST run as UID 0;
- effective package execution MUST remain `run-as: root`;
- the promoted package target MUST remain `root:root`;
- kernel TUN MUST remain enabled;
- subnet routing and `--accept-routes` MUST remain supported;
- exit-node operation MUST remain supported;
- the Linux netfilter backend MUST remain enabled;
- the required Synology netfilter extensions MUST remain usable;
- upstream Synology policy gates that disable those capabilities MUST NOT be
  reintroduced.

Security hardening must therefore protect what the privileged runtime trusts;
it must not reduce Tailscale's runtime privilege. See
[ADR 0002](../adr/0002-privileged-bootstrap-trust-boundary.md).

## Completed productionisation work

### 1. Repository and release governance — complete

- downstream/upstream branch roles are documented and enforced;
- signed downstream commits and protected integration are required;
- release/control branches and release tags are protected;
- release identity is pinned in `release/manifest.yaml`;
- release automation and validation lanes are documented and contract-tested.

### 2. r2 reproducibility and acceptance — complete

- accepted r2 source and package identities are frozen;
- the 58-patch round trip reproduces the accepted source tree;
- independent builds produced byte-identical r2 SPKs;
- exact-artifact DS920+/DSM 7.4.1 installation, bootstrap, lifecycle, routing,
  IPv4/IPv6 and netfilter acceptance is retained;
- the published r2 release remains unchanged.

### 3. Publication and supply-chain governance — complete for policy

- signed release tags are required;
- future releases require a detached OpenSSH signature for `SHA256SUMS`;
- publication evidence and closeout are separate records;
- immutable releases remain intentionally deferred unless separately approved.

### 4. Workspace, archive and automation closeout — complete

- temporary governance worktrees and branches were removed;
- the retained development workspace is documented;
- the sealed r2 archive was copied to independent macOS storage and verified;
- automation governance and offline workflow validation are integrated.

## Remaining productionisation work

### 5. Harden the persistent UID-0 runtime trust boundary — required

This task replaces the ambiguous phrase "redesign the root-control trust
boundary". It does **not** mean dropping root privileges or returning to the
ordinary DSM package-user/Package Center capability model.

#### 5.1 Collect DSM path and lifecycle evidence

Before selecting a permanent control location, collect read-only evidence for:

- `/var/packages/Tailscale/scripts`;
- package `conf` and `var` locations;
- resolved `@appconf` and `@appdata` locations;
- package target and volume-dependent paths;
- prospective system/root-control locations.

Record `realpath`, owner/group, modes, ancestor permissions, mount behaviour and
lifecycle behaviour across install, upgrade, reboot, rollback, uninstall and
volume migration.

#### 5.2 Establish a root-only control plane

Move authoritative privileged control material beneath a root-owned,
non-package-writable ancestor chain. This includes, where applicable:

- authoritative bootstrap/controller entry points;
- bootstrap approval/current-state records;
- privileged backups;
- reconciler PID and pending/control state;
- privileged lifecycle logs;
- privileged temporary files;
- root-trusted payload-integrity metadata.

The `tailscale` package account may continue to exist for DSM compatibility but
must not be a security authority after bootstrap.

#### 5.3 Authenticate the payload before privilege promotion

Before package ownership is promoted or any package payload executes as UID 0,
validate the exact inspected SPK payload against root-trusted expected
identities.

At minimum authenticate:

- `tailscaled`;
- `tailscale`;
- bootstrap/controller code;
- privileged lifecycle scripts;
- reconciler helpers;
- privileged templates.

The trusted expected manifest must be generated from the exact reviewed build
and stored where the package account cannot replace it. Promotion fails closed
on any mismatch.

#### 5.4 Harden privileged filesystem operations

Privileged code must:

- validate the resolved path and every relevant ancestor using
  `lstat`/equivalent checks;
- reject symlinks and unexpected file types;
- reject unsafe modes or ownership drift;
- create temporary objects exclusively inside trusted root-controlled
  directories;
- use safe atomic replacement only after validating the temporary object;
- reject unexpected pre-existing backup/destination entries.

#### 5.5 Preserve application-state semantics

Do not recursively change ownership of the complete package variable directory
without evidence. Classify each persistent path by required owner, writer,
reader and lifecycle semantics. Preserve any legitimate DSM/Tailscale state
access while preventing the package account from modifying privileged control
material.

#### 5.6 Implement migration and lifecycle handling

Cover:

- existing r2 installations;
- fresh installation;
- upgrade;
- rollback;
- bootstrap removal/re-application;
- uninstall;
- reboot;
- DSM volume migration;
- log rotation;
- backup retention/recovery.

#### 5.7 Validate the exact implementation

Require automated fixtures for:

- malicious symlink substitution;
- directory-entry replacement;
- unsafe file types;
- ownership/mode drift;
- payload tampering;
- trusted-manifest mismatch;
- unexpected pre-existing destinations/backups.

Then require exact-artifact DSM UAT proving that after the hardening change:

- `tailscaled` remains UID 0;
- target ownership remains `root:root`;
- TUN works;
- subnet routing works;
- `--accept-routes` works;
- exit-node behaviour works;
- IPv4 and IPv6 routing/netfilter work;
- reboot, upgrade and rollback work.

Task 5 is complete only after those gates pass in a new downstream revision.

### 6. Close agent/release-tool safety defects — required before autonomous port work

- pin the version-preparation signing fixture to an explicit `ssh-keygen`
  implementation rather than inheriting the host's global SSH signing program;
- isolate fixture Git configuration;
- redact private-key material from failure logs;
- verify build-output cleanup cannot delete an unsafe or ambiguously resolved
  path;
- enforce expected signer identity where signatures are used as a release gate.

These are repository/tooling controls and should land on `synology/main` before
an agent is allowed to perform a largely autonomous version port.

### 7. Pin complete netfilter-extension provenance — required for whole-product reproducibility

The Tailscale SPK currently records a minimum dependency version. Before the
next stable release, pin and retain the exact netfilter-extension provenance,
including:

- package source revision;
- `spksrc` revision;
- Synology kernel/toolchain inputs;
- architecture and DSM floor;
- accepted SPK SHA-256;
- matching hardware acceptance evidence.

Only then can reproducibility be claimed for the complete Tailscale plus
netfilter-extension product rather than the Tailscale SPK alone.

### 8. Port to the next explicitly selected upstream release — planned

For the currently assessed `v1.102.3` candidate, use the standard version-update
runbook with these additional constraints:

1. start from the exact verified upstream tag and commit;
2. create an isolated worktree;
3. compare the old/new upstream snapshots and use `git range-diff` for the
   downstream commit stack;
4. adapt Linux router/netfilter changes individually rather than replaying the
   old patches mechanically;
5. establish a port-only compile/test checkpoint before adding new trust-boundary
   implementation work;
6. implement task 5 as separate logical signed commits;
7. regenerate the complete mail patch series;
8. perform two clean byte-identical builds and static SPK inspection;
9. validate the pinned netfilter-extension dependency;
10. perform exact-artifact DSM acceptance including upgrade, bootstrap, reboot,
    rollback, IPv4/IPv6, subnet routing, accept-routes, exit-node and netfilter;
11. publish only after human review and the normal release closeout;
12. publish and verify signed `SHA256SUMS` for the new stable release.

An agent may prepare, port, test and build candidates under the permissions in
`AGENTS.md`. It may not install the production NAS package, run root bootstrap,
change production networking, approve its own work or publish the stable
release.

## Definition of final production readiness for the next release

The next release is production-ready only when all applicable items above are
complete and the release has fresh evidence for:

- source identity and signed downstream history;
- patch round-trip reproducibility;
- byte-identical package builds;
- static package inspection;
- exact netfilter dependency provenance;
- persistent UID-0 trust-boundary security tests;
- exact-artifact DSM installation/upgrade/rollback/reboot acceptance;
- TUN, subnet routing, accept-routes, exit-node and IPv4/IPv6 netfilter
  functionality;
- reviewed/sanitised evidence;
- signed checksums and human-controlled stable publication.
