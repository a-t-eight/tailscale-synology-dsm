# ADR 0002: Persistent UID-0 runtime trust boundary

- Status: Accepted r2 limitation; replacement design approved for the next revision
- Date: 2026-08-25
- Clarified: 2026-08-28

## Context

Tailscale's full Linux networking behaviour on this downstream Synology DSM
build requires privileged TUN, routing, accept-routes, exit-node and Linux
netfilter operations. The project therefore intentionally uses an attended
administrator bootstrap to promote the installed package into a persistent
root runtime.

The initial package target is owned by `tailscale:tailscale`. Running a target
script through `sudo` would elevate the process but would not make the
package-owned script trustworthy. The package account could alter or replace
the content that root executes.

Root-owned state, PID, backup, log and reconciliation files also remain at
predictable locations beneath the Synology package variable directory. File
ownership and restrictive modes do not fully protect those entries if a
package-writable ancestor permits rename, replacement or symlink manipulation.

The residual risk is therefore a trust-boundary problem, not a requirement to
reduce Tailscale's runtime privilege.

## Non-regression architecture invariants

Any future redesign of this boundary MUST preserve the following behaviour
after successful attended bootstrap:

- `tailscaled` runs as UID 0;
- the active privilege configuration remains effectively `run-as: root`;
- the promoted package target remains `root:root`;
- kernel TUN operation remains enabled;
- subnet routing and `--accept-routes` remain supported;
- exit-node operation remains supported;
- the normal Linux netfilter backend remains enabled;
- the separate Synology netfilter-extension package remains available to supply
  the required kernel modules;
- upstream Synology policy gates that disable those features must not be
  reintroduced;
- upstream `SYNOPKG_PKGVAR` paths for daemon state, socket, PID and stdout log
  must remain unchanged;
- upstream logrotate, DSM web-interface and package-data ownership semantics
  must remain unchanged;
- the design must not regress to the ordinary DSM package-user or Package
  Center capability model as a substitute for the project's intentional root
  runtime.

A change that violates any of these invariants is an architectural regression,
not completion of this trust-boundary task.

## r2 decision

Revision r2:

- retains the stock package-account manifest at installation;
- requires the initial privileged operation to use the root-owned script under
  `/var/packages/Tailscale/scripts`;
- rejects the `/usr/local/bin` target copy as an initial privileged entry point
  while that target is not root-owned;
- compares the target bootstrap with the trusted package-script copy;
- changes the package target to `root:root` during bootstrap;
- changes the active privilege configuration to effective `run-as: root`;
- verifies `tailscaled` is running as UID 0;
- requires the target bootstrap to be root-owned, mode `0755`, and not
  group/other-writable before later privileged use;
- restores package-account ownership and leaves the package stopped when root
  bootstrap is removed.

Root control files remain under the existing package variable-directory
boundary. This is accepted residual risk for r2, not a claim that the boundary
is safe against a compromised package account.

## Why package ownership plus `sudo` was rejected

`sudo` authenticates and authorises the caller, then runs the selected content
as root. It does not authenticate that content. If `tailscale` owns the script,
or can replace it through a writable parent, compromise of the package account
can become arbitrary root execution at the next attended invocation.

The same reasoning applies to root-owned control files beneath a
package-writable ancestor: replacing the directory entry may bypass the
protection provided by the file's owner and mode.

## Approved next-revision design

Task 5 hardens only downstream privileged control material. It deliberately
does not relocate or recursively re-own the upstream Synology package's daemon
state.

The approved persistent trust anchors are the DSM-installed, root-owned package
`scripts` and `conf` directories. The next revision adds:

- `/var/packages/Tailscale/conf/root-payload.manifest` for build-generated
  expected payload identities;
- `/var/packages/Tailscale/conf/root-control/` for bootstrap approval state and
  private promotion transactions; and
- `/run/tailscale-synology/` for volatile reconciler PID and interrupted-repair
  state.

The reconciler sends messages through DSM's system logger instead of opening a
predictable privileged log beneath package-writable storage.

The outer package-script bootstrap remains the only authoritative `install` and
`remove` entrypoint. The target copy exposed through `/usr/local/bin` is
status-only, so the initial trust decision never depends on package-owned code.

The following remain in `SYNOPKG_PKGVAR` with their upstream paths and
semantics: `tailscaled.state`, `tailscaled.sock`, `tailscaled.pid`,
`tailscaled.stdout.log` and `STATE_DIRECTORY`. The LocalAPI and web interface
continue using the same socket. Upstream logrotate and package-data ownership
remain unchanged.

The authoritative detailed contract, including the customization review,
migration and validation requirements, is
[the upstream-compatible root-control design](../superpowers/specs/2026-08-28-upstream-compatible-root-control-design.md).

Moving upstream application state or changing package-data permissions is not
Task 5. Such a change would require a separate architecture decision because it
would make this port materially diverge from the upstream package.

## Payload authentication before promotion

The attended bootstrap is a privilege-promotion boundary. It must not simply
hash whatever package-owned payload happens to exist and accept that hash as a
new baseline.

Before ownership is promoted or any package payload is executed as UID 0, the
bootstrap should authenticate the exact inspected SPK payload against
root-trusted expected identities. At minimum this includes:

- `tailscaled`;
- `tailscale`;
- privileged lifecycle scripts;
- bootstrap/controller code;
- reconciler helpers and privileged templates.

The expected manifest must originate from the exact reviewed build/release
process and be stored where the package account cannot replace it. Promotion
must fail closed on any mismatch.

## Filesystem and lifecycle boundary

Trusted persistent paths must have root-owned, non-package-writable ancestor
chains. Privileged code validates resolved ancestors and final objects, rejects
symlinks, multiple hard links, unsafe types, modes and owners, and creates
temporary objects only inside the validated root-control transaction directory.

The design intentionally accepts the upstream-compatible application-data
boundary, including the residual replacement risk around the upstream daemon
PID and root-opened stdout log beneath package-writable `@appdata`. New
bootstrap approval, payload identity, privileged rollback and reconciler
process-control material is not stored there. Existing r2 control files there
are not trusted during migration.

Upgrade, rollback, removal, uninstall, reboot and volume migration must preserve
daemon state semantics. A changed or missing manifest identity requires a fresh
attended bootstrap; it must never be inferred from a legacy r2 state file.

## Validation required

Any redesign requires a new downstream release revision and must repeat:

- bootstrap and removal regression tests;
- malicious symlink, replacement, unsafe-type and ownership-drift tests;
- payload-tampering and manifest-mismatch tests;
- explicit tests that daemon state, socket, PID, stdout log and logrotate paths
  remain unchanged;
- reconciler `/run` lifecycle, pending-repair and system-logging tests;
- package upgrade and rollback tests;
- reboot and lifecycle tests;
- reproducible builds and static SPK inspection;
- exact-artifact DSM acceptance;
- verification that `tailscaled` remains UID 0 after bootstrap;
- IPv4 and IPv6 routing, accept-routes, exit-node and netfilter acceptance.

No functional ownership or path change is included in the r2 documentation
closeout. The accepted r2 release remains unchanged.
