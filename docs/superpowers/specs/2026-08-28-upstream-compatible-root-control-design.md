# Upstream-compatible root-control design

## Purpose

Harden the downstream UID-0 bootstrap and reconciliation controls without
turning the Synology port into a new package architecture. The implementation
must preserve the upstream Tailscale SPK's application-state paths, DSM
lifecycle behaviour and web-interface access while authenticating every byte
that the attended bootstrap promotes to root trust.

This design applies to the next downstream revision after the accepted
`v1.98.96-r2` release. It does not modify the frozen r2 source, package, tag or
acceptance evidence.

## Decision

Use the existing root-owned Synology package `scripts` and `conf` directories
as the persistent trust anchor. Add only two root-control surfaces:

- `/var/packages/Tailscale/conf/root-payload.manifest` for build-generated
  expected payload identities; and
- `/var/packages/Tailscale/conf/root-control/` for bootstrap approval state and
  private promotion-transaction material.

Use `/run/tailscale-synology/` only for volatile, downstream reconciliation
control files. Reconciler messages go to DSM's system logger instead of a
root-opened file under package-writable application storage.

Do not relocate, recursively re-own or reinterpret upstream application state.
In particular, keep `tailscaled.state`, `tailscaled.sock`, `tailscaled.pid`,
`tailscaled.stdout.log` and `STATE_DIRECTORY` beneath `SYNOPKG_PKGVAR` exactly
as the upstream Synology package defines them. Keep the upstream logrotate
contract and the package account's access to `@appdata` and `@appconf`.

## Non-regression contract

After a successful attended bootstrap:

- `tailscaled` runs as UID 0;
- effective package execution is `run-as: root`;
- the promoted package target is `root:root`;
- kernel TUN, subnet routing, `--accept-routes`, exit-node operation and the
  Linux netfilter backend remain enabled;
- the external `iptables-netfilter-extensions` dependency remains required;
- the DSM web interface and LocalAPI keep using the upstream package socket;
- bootstrap removal restores package-account execution and target ownership;
- upgrade, rollback, uninstall and volume migration retain DSM's existing
  package-data semantics.

Moving upstream daemon state, changing its socket permissions, changing the
logrotate target, or recursively changing package-data ownership requires a
separate architecture decision. None is part of Task 5.

## Path and ownership contract

| Path | Owner and mode after install | Writer | Lifecycle and purpose |
| --- | --- | --- | --- |
| `/var/packages/Tailscale/scripts` | DSM-installed `root:root`, not group/other-writable | package installation only | Authoritative outer bootstrap, lifecycle script and reconciler executable |
| `/var/packages/Tailscale/conf/root-payload.manifest` | `root:root 0644` | package installation only | Exact expected identities for root-promoted payload |
| `/var/packages/Tailscale/conf/root-control` | `root:root 0755` | privileged controller | Trusted bootstrap-state namespace; readable so unprivileged status remains available |
| `.../root-control/root-bootstrap.state` | `root:root 0644` | privileged controller | Current manifest identity and completed bootstrap approval |
| `.../root-control/transactions` | `root:root 0700` | privileged controller | Private, bounded rollback material for the active promotion transaction |
| `/run/tailscale-synology` | `root:root 0700` | root lifecycle and reconciler processes | Volatile reconciler PID and interrupted-repair marker; recreated and validated on start |
| `SYNOPKG_PKGVAR` | Existing DSM/upstream ownership | existing package/runtime writers | Unchanged daemon state, socket, PID and stdout log |

The controller validates every relevant ancestor and final object before use.
It rejects symlinks, multiple hard links, unexpected file types, non-root
owners, and group/other write permission on trusted persistent paths. It
creates temporary objects only inside the validated transaction directory and
commits them with no-follow, same-directory atomic replacement.

The root-control directory is deliberately inside `conf`, whose installed
ownership was verified as root-controlled on the target DSM 7.4.1 system. The
implementation and UAT must re-verify that property. If a supported DSM
lifecycle makes `conf` package-writable, promotion fails closed; the design does
not fall back to trusting `@appdata`.

## Payload authentication

The build creates `root-payload.manifest` from the exact files placed in the
SPK. Entries are deterministic, sorted and relative to the package root; each
records file type, mode and SHA-256. The manifest covers every regular file
that becomes root-owned or can execute in the root package lifecycle. This
includes the complete inner target payload, every package script, the immutable
privilege templates and the static DSM resource metadata. Required entries
therefore include:

- `target/bin/tailscale`;
- `target/bin/tailscaled`;
- `target/bin/tailscale-synology-bootstrap`;
- `scripts/start-stop-status`;
- `scripts/tailscale-synology-bootstrap`;
- `scripts/tailscale-netfilter-reconciler`;
- `scripts/preupgrade`;
- `scripts/postupgrade`;
- `conf/privilege.bootstrap-package`; and
- `conf/privilege.bootstrap-root`.

The manifest does not hash itself or mutable `conf/privilege`. The controller
validates the active privilege file by exact comparison with one of the two
manifested templates.

The static SPK inspector verifies that the covered roots contain no unlisted
regular files, every required entry exists with the expected type and mode, and
every file hashes to the recorded identity. It rejects duplicate paths,
absolute paths, traversal components, control characters and unsupported
record types.

At runtime the outer root-owned bootstrap validates the trusted manifest and
the already root-owned outer package material before promotion. It then stops
the package and takes control of the resolved target directory without
following links. Each manifested target file is copied to a root-owned
same-directory temporary inode, validated against the manifest, and atomically
renamed into place. This replacement severs any writable file descriptor held
against the former package-owned inode. A final no-follow walk verifies the
complete target tree, directory ownership and absence of unmanifested or unsafe
entries before the root privilege is installed or target content can execute as
UID 0.

Small bootstrap transaction material stays under `conf/root-control`; target
file staging remains on the package volume and exists only inside target
directories whose entries have already become root-controlled. The bootstrap
must never generate or bless a new trusted baseline from the installed
package-owned target.

Bootstrap state records the manifest digest and schema version. A missing or
mismatched state is not current. Package upgrade therefore requires a fresh
attended bootstrap whenever the exact promoted payload changes, whether DSM
preserves or replaces the prior control-state directory.

## Reconciliation compatibility review

The reconciler is the only downstream customization whose current filesystem
contract must be split across trust domains.

The LocalAPI socket remains `${SYNOPKG_PKGVAR}/tailscaled.sock`; moving it would
change the daemon, CLI and web-interface contract. The reconciler's own PID and
pending-repair marker move from `SYNOPKG_PKGVAR` to
`/run/tailscale-synology/`. The lifecycle script creates and validates that
runtime directory before starting the reconciler, passes the paths explicitly,
and removes stale control files only after type and ownership checks.

The separate `tailscale-netfilter-reconciler.log` file is removed. The
reconciler logs with `/usr/bin/logger` using a stable tag and priority mapping;
stdout and stderr are not redirected to a predictable root-opened path beneath
package-writable storage. Logging failure must be visible on stderr but must not
turn a healthy firewall reconciliation into a repair loop.

Read-only DSM 7.4.1 inspection confirmed `/usr/bin/logger` is installed as a
root-owned executable. Candidate UAT must repeat that prerequisite check.

The reconciler's process identity checks, TERM/KILL shutdown sequence,
LocalAPI operations, pending-repair recovery, cooldown and netfilter-hook
verification remain otherwise unchanged.

The pending marker is intentionally volatile because the netfilter transaction
it describes is kernel state. It survives a reconciler or package restart on
the same boot. A reboot removes `/run` and restarts daemon/firewall setup;
normal root startup must rebuild and verify hooks without relying on the marker
or assuming prior rules disappeared. UAT includes a crash after netfilter mode
is disabled followed by reboot and startup verification.

## Other downstream customization review

| Customization | Task 5 impact |
| --- | --- |
| Attended root bootstrap | Change state, backups, temporary files, path validation and payload authentication as described above |
| `start-stop-status` | Read bootstrap state from `conf/root-control`; create/validate the reconciler runtime directory; keep all daemon application paths unchanged |
| Netfilter reconciler | Move only its PID and pending marker to `/run`; use system logging; keep the upstream LocalAPI socket |
| iptables preflight and guarded cleanup | No path change; retain existence checks, bounded cleanup and observed-progress guards |
| TUN creation and routing sysctls | No path or ownership change; these remain privileged lifecycle operations |
| In-daemon netfilter self-healing patches | No package-filesystem dependency; no Task 5 change |
| Netfilter-extension dependency and probes | No Task 5 change |
| `/usr/local/bin` linker entries | Remain status-only convenience links; all mutations enter through the outer root-owned bootstrap |
| DSM resource and logrotate configuration | Keep the upstream daemon log path and resource semantics unchanged |
| Package revision and branch/release metadata | Advance only as part of the later implementation release |

## Entrypoint and lifecycle authority

The root-owned outer script remains the only authoritative entrypoint for
`install` and `remove`:

```text
sudo /var/packages/Tailscale/scripts/tailscale-synology-bootstrap install
sudo /var/packages/Tailscale/scripts/tailscale-synology-bootstrap remove
```

The target copy exposed through `/usr/local/bin` is a convenience status
command only. It rejects mutating actions even after promotion. This prevents
the initial trust decision from depending on code that was package-owned when
the administrator selected it.

Lifecycle authority is explicit:

- a package-account `start` checks readable bootstrap state and reports the
  attended command without creating, inspecting or removing root runtime
  control files;
- a root `start` with current bootstrap state validates or creates
  `/run/tailscale-synology` before starting the daemon and reconciler;
- only a root `stop` may signal the reconciler or remove its PID, pending marker
  and runtime directory, and only after the existing process-identity checks;
- non-root `status` may report daemon and bootstrap state but treats reconciler
  detail as privileged and never repairs or removes a file;
- root `status` validates reconciler process state without performing cleanup;
  stale cleanup belongs to root `start` or `stop`.

During upgrade or removal, the old root lifecycle stops and cleans the
reconciler before the stock package privilege is restored. A new or rolled-back
package starts in package mode until the outer bootstrap validates its exact
manifest. Any stale `/run` directory is left untouched by package-account code
and handled by the next attended root operation.

## Upgrade and r2 migration

Existing r2 control files beneath `SYNOPKG_PKGVAR` are not trusted as approval
or process-control inputs. A Task 5 build treats the old bootstrap state as
absent and requires a fresh attended promotion against its own manifest.

After successful promotion, the controller may unlink exact legacy regular
files or symlinks that are no longer authoritative, but it must not recursively
delete package data or migrate old backup directories into the new trust
domain. Legacy logs and backup directories may remain as inert historical data
until an explicitly documented cleanup action.

Bootstrap removal stops the reconciler and daemon, restores the stock privilege
template and `tailscale:tailscale` target ownership, removes the current trusted
bootstrap state and volatile reconciliation control files, and leaves the
package stopped. It does not copy, move, delete or re-own `tailscaled.state`,
the LocalAPI socket or the upstream stdout log.

## Failure handling

Promotion is transactional and fail-closed:

1. validate DSM version, trusted paths, manifest format and all payload hashes;
2. stop the package through the existing bounded `synopkg` wrapper;
3. create a private transaction directory under `conf/root-control`;
4. capture only the privilege and bootstrap control material required for
   rollback;
5. promote and final-verify the complete target, then write bootstrap state;
6. install the root privilege only after those checks have passed;
7. start the package and verify `tailscaled` UID 0 and stable reconciliation;
8. remove the private transaction directory after successful startup.

Any validation or startup failure restores the prior privilege, target owner
and bootstrap-control state and leaves the package stopped if safe recovery
cannot be proven. A successfully rolled-back transaction is removed. A failed
rollback is retained as the sole recovery transaction and blocks later
mutations until attended recovery; transactions do not accumulate as a backup
archive. No rollback operation follows a symlink or trusts a path beneath
package-writable application storage.

## Validation contract

Implementation is not complete until automated tests cover:

- deterministic manifest generation and static SPK verification;
- missing, malformed, duplicate, extra and mismatched manifest entries;
- target payload tampering before promotion;
- concurrent target replacement and pre-existing writable file descriptors
  during promotion;
- symlink, hard-link, FIFO, directory and unsafe-mode substitutions at every
  new trusted control path;
- hostile legacy r2 entries under `SYNOPKG_PKGVAR`;
- atomic rollback at each promotion failure point;
- reconciler runtime-directory ownership and mode drift;
- pending-repair recovery and shutdown using the `/run` paths;
- logger unavailability and logging failure without unsafe file fallback;
- unchanged daemon state, socket, PID, stdout-log and logrotate paths;
- bootstrap install, idempotent reinstall, remove and re-bootstrap;
- fresh install, r2 upgrade, rollback, reboot, uninstall and volume migration.

The candidate then requires two clean byte-identical builds, static inspection
of both SPKs, and exact-artifact DSM UAT. UAT must prove the non-regression
contract, web-interface access, LocalAPI access, IPv4 and IPv6 netfilter,
subnet routing, `--accept-routes`, exit-node operation, reboot, upgrade and
rollback.

## Residual risk

This design intentionally accepts the upstream-compatible application-data
boundary. A compromised `tailscale` package account may still tamper with
application files it is expected to own under `@appdata`. In particular, the
upstream daemon PID and stdout-log paths remain beneath a package-writable
ancestor. Existing executable-identity checks constrain PID misuse, but the
predictable root-opened daemon log remains an accepted file-replacement risk.

The hardening removes the additional downstream bootstrap, rollback and
reconciler-control trust placed in `@appdata`; it does not claim to eliminate
the retained upstream risk.

Eliminating all package-account influence over daemon state would require a
larger fork of the upstream Synology package architecture and is outside this
port's scope.

## Delivery boundary

The design lands first on `synology/main` for review. Production code follows
only after the written design is approved. Implementation must use separate
signed logical commits for manifest/build support, bootstrap control-path
hardening, reconciliation changes and tests/documentation. It must not alter or
republish r2, install a package on DSM, run bootstrap, or change production
networking without the normal later approval gates.
