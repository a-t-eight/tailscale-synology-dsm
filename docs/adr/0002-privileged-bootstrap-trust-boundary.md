# ADR 0002: Privileged bootstrap trust boundary

- Status: Accepted limitation for r2; redesign required for a future revision
- Date: 2026-08-25

## Context

Tailscale's full Linux networking behavior on Synology DSM requires privileged
TUN, routing, and netfilter operations. The downstream package therefore uses
an attended bootstrap to change the package runtime to root.

The initial package target is owned by `tailscale:tailscale`. Running a target
script through `sudo` would elevate the process but would not make the
package-owned script trustworthy. The package account could alter or replace
the content that root executes.

Root-owned state, PID, backup, log, and reconciliation files also remain at
predictable locations beneath the Synology package variable directory. File
ownership and restrictive modes do not fully protect those entries if a
package-writable ancestor permits rename, replacement, or symlink manipulation.

## r2 decision

Revision r2:

- retains the stock package-account manifest at installation;
- requires the initial privileged operation to use the root-owned script under
  `/var/packages/Tailscale/scripts`;
- rejects the `/usr/local/bin` target copy as an initial privileged entry point
  while that target is not root-owned;
- compares the target bootstrap with the trusted package-script copy;
- changes the package target to `root:root` during bootstrap;
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

## Future requirement

The next functional revision that changes this boundary should separate:

- a root control plane containing privileged entry points, approval state,
  process-control files, reconciliation state, logs, and backups; and
- package-owned application data that the unprivileged package account must
  legitimately update.

The root control plane must have root-owned, non-package-writable ancestors and
must reject symlinks, unexpected file types, unsafe modes, and ownership drift.
The design must account for DSM package upgrade, uninstall, volume migration,
backup, log rotation, and rollback semantics before selecting a final path.

Changing ownership of the complete package variable directory to root is not
automatically safe because DSM or Tailscale may require package-account access
to application state. The implementation must classify each path by owner and
writer rather than applying one recursive ownership rule.

## Validation required

Any redesign requires a new downstream release revision and must repeat:

- bootstrap and removal regression tests;
- malicious symlink, replacement, and ownership-drift tests;
- package upgrade and rollback tests;
- reproducible builds and static SPK inspection;
- exact-artifact DSM lifecycle and reboot acceptance;
- IPv4 and IPv6 routing and netfilter acceptance.

No functional ownership or path change is included in the r2 documentation
closeout.
