# Package runtime and administrator bootstrap

## Package roles

The release contains the Tailscale userspace binaries, Synology lifecycle
scripts, and the attended administrator bootstrap. Kernel netfilter extensions
are supplied by a separate package.

The Tailscale SPK declares a hard dependency on:

```text
iptables-netfilter-extensions >= 1.1.0-2
```

DSM Package Center must resolve that dependency before installing the Tailscale
package. `iptables-netfilter-extensions` is a separate Synology SPK built with
the [SynoCommunity `spksrc` toolchain](https://github.com/SynoCommunity/spksrc).
It provides iptables and netfilter kernel modules that stock DSM does not expose
to the package and that are required for subnet routing, exit-node operation,
and Tailscale's Linux netfilter backend.

The Tailscale and netfilter-extension packages have separate sources,
toolchains, validation, and hardware-acceptance requirements. A successful
build of one does not validate the other.

## Privilege model

The package is installed with its package-account privilege configuration and
`tailscale:tailscale` target ownership. Full project functionality requires one
attended administrator bootstrap.

The initial privileged operation must use the root-owned package-script copy:

```text
sudo /var/packages/Tailscale/scripts/tailscale-synology-bootstrap install
sudo /usr/local/bin/tailscale-synology-bootstrap status
```

The first `install` intentionally rejects the `/usr/local/bin` entry while it
resolves to the package-owned target copy. After successful bootstrap:

- the active privilege manifest uses effective `run-as: root`;
- the manifest retains the `tailscale` username and group metadata;
- the package target, including the target bootstrap, is `root:root`;
- the target bootstrap mode is `0755`;
- the package is restarted and verified as UID 0.

Expected status:

```text
Privilege mode: root
Bootstrap state: current
Runtime: running, UID=0
```

## Supported post-bootstrap runtime invariant

The UID-0 runtime is deliberate and is part of the product architecture, not a
temporary implementation detail.

A future security or trust-boundary redesign must preserve all of the following
after successful attended bootstrap:

- `tailscaled` runs as UID 0;
- the package target remains `root:root`;
- TUN operation remains enabled;
- subnet routing and `--accept-routes` remain supported;
- exit-node operation remains supported;
- the normal Linux netfilter backend remains enabled;
- required Synology netfilter kernel extensions remain usable;
- downstream removal of upstream Synology feature gates is not reversed.

The project must not be "hardened" by reverting to an ordinary DSM package-user
runtime or by reintroducing Synology-specific restrictions that nullify the
purpose of the downstream build.

## Why `sudo` is not sufficient by itself

`sudo` changes the identity of the process that executes a file. It does not
change who controls the file or its directory entries.

A `tailscale:tailscale`-owned bootstrap could technically execute as root when
passed to `sudo`, but the package account could edit or replace that file before
execution. Root would then execute package-controlled content. A root-owned file
inside a package-writable parent is also insufficient because the package
account may be able to rename or replace the directory entry.

A trusted privileged entry point therefore requires:

- root ownership;
- no group or other write permission;
- trusted, non-package-writable ancestor directories;
- validation of the resolved path rather than only the displayed symlink;
- fail-closed handling when ownership, mode, path or content differs.

The accepted r2 implementation enforces root ownership and safe file modes for
the privileged script and switches the target to `root:root`. Its remaining
directory-boundary limitation is recorded in
[ADR 0002](adr/0002-privileged-bootstrap-trust-boundary.md).

## Future trust-boundary hardening

The next functional revision should harden what the persistent UID-0 runtime is
allowed to trust, without reducing its privilege.

The intended direction is:

- keep authoritative privileged entry points and control state beneath a
  root-owned, non-package-writable ancestor chain;
- authenticate the exact inspected package payload before promotion to root;
- fail closed on symlinks, replacement, unsafe modes, unexpected file types or
  ownership drift;
- use trusted root-only locations for privileged temporary files, backups,
  reconciliation state and lifecycle control;
- classify application state separately rather than recursively changing the
  complete package variable directory.

Before a final root-control path is selected, DSM path ownership, mount and
lifecycle behaviour must be measured on target hardware. The design must cover
upgrade, rollback, bootstrap removal, uninstall, reboot, volume migration, log
rotation and backup retention.

## Runtime implications

The service and Synology package lifecycle run with full NAS root authority
after bootstrap. This enables the required TUN, routing, accept-routes,
exit-node and netfilter changes, but a compromise of the daemon, package files,
or lifecycle scripts could compromise the NAS.

Bootstrap restarts Tailscale and updates networking and firewall state. Perform
it from a LAN or out-of-band session rather than relying solely on the Tailscale
connection being restarted.

Immediately after bootstrap, `tailscale status` may briefly report
`Tailscale is starting` or `unexpected state: NoState`. Retry after startup has
settled.

## Removing administrator bootstrap

```text
sudo /usr/local/bin/tailscale-synology-bootstrap remove
```

Removal:

- stops Tailscale;
- restores the package-account privilege configuration;
- restores `tailscale:tailscale` target ownership;
- removes the current bootstrap state;
- leaves the package stopped.

Removal is a privilege-removal operation, not a supported unprivileged runtime
mode for this build. Re-enable the service through the trusted root-owned
package script:

```text
sudo /var/packages/Tailscale/scripts/tailscale-synology-bootstrap install
```
