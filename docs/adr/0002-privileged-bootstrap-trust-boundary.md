# ADR 0002: Persistent UID-0 runtime trust boundary

- Status: Accepted limitation for r2; hardening required for a future revision
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

## Future requirement: harden the persistent UID-0 runtime trust boundary

The next functional revision that changes this boundary should harden the
content and state trusted by the intentionally privileged runtime. It should not
reduce runtime privilege.

The implementation should separate:

- a root control plane containing authoritative privileged entry points,
  bootstrap approval state, process-control files, reconciliation state,
  lifecycle logs, privileged backups, trusted temporary files and payload
  integrity metadata; and
- application data that DSM or Tailscale demonstrably requires another account
  to update.

The root control plane must:

- live beneath a root-owned, non-package-writable ancestor chain;
- validate the complete resolved path and every relevant ancestor with
  `lstat`/equivalent checks;
- reject symlinks, unexpected file types, unsafe modes and ownership drift;
- create privileged temporary files exclusively inside the trusted directory;
- use safe atomic replacement only after validating the temporary object;
- reject unexpected pre-existing backup or destination entries;
- keep authoritative install/remove/reconcile entry points outside any location
  whose directory entries the `tailscale` account can replace.

The `/usr/local/bin` bootstrap may remain a convenience or status entry point,
but privileged install/remove operations must resolve to an independently
trusted root-controlled controller.

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

## Path classification and lifecycle

Do not recursively root-own the complete package variable directory by default.
First classify every persistent path by its required owner, writer and lifecycle
semantics.

Before selecting the final root-control location, collect read-only DSM evidence
for the resolved paths, ownership, modes, mount behaviour and package lifecycle
of relevant `scripts`, `conf`, `var`, `@appconf`, `@appdata` and prospective
system locations.

The design must account for:

- migration from existing r2 installations;
- package upgrade;
- rollback;
- bootstrap removal;
- uninstall;
- reboot;
- DSM volume migration;
- log rotation;
- backup retention and recovery.

## Validation required

Any redesign requires a new downstream release revision and must repeat:

- bootstrap and removal regression tests;
- malicious symlink, replacement, unsafe-type and ownership-drift tests;
- payload-tampering and manifest-mismatch tests;
- package upgrade and rollback tests;
- reboot and lifecycle tests;
- reproducible builds and static SPK inspection;
- exact-artifact DSM acceptance;
- verification that `tailscaled` remains UID 0 after bootstrap;
- IPv4 and IPv6 routing, accept-routes, exit-node and netfilter acceptance.

No functional ownership or path change is included in the r2 documentation
closeout. The accepted r2 release remains unchanged.
