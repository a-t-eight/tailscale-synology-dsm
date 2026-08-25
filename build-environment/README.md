# Build environments

The downstream project uses separate environments for Tailscale source and DSM
netfilter modules. Do not merge their toolchains or infer that one validates
the other.

## Tailscale source and SPK environment

The selected source, work or release worktree is the build environment.

Every Go operation must use:

```text
./tool/go
```

The worktree and `release/manifest.yaml` provide:

- pinned upstream and downstream commits;
- repository-pinned Go acquisition and version selection;
- Synology package sources;
- build entrypoint;
- package version and architecture;
- build-output and evidence paths.

Host `go`, npm and pip installations are not release dependencies.

The accepted `1.98.96-r2` production baseline is identified by:

```text
commit: 0fad8b81a3e0eb86c457bc79c474bcc213834c43
tree:   33f5c5927ae4db54b9d582650ed31cc6a2eb7161
```

The earlier r1 identity is retained in its release record and historical
manifest. A future release must replace the current manifest values with its
own reviewed identity; it must not silently reuse r2.

## DSM netfilter-module environment

The `iptables-netfilter-extensions` package uses the corresponding
[SynoCommunity `spksrc` toolchain](https://github.com/SynoCommunity/spksrc)
and Synology kernel/toolchain inputs for the target DSM platform. The Tailscale
SPK declares it as a hard package dependency.

Its outputs must be validated separately for:

- kernel and DSM version;
- Synology platform and architecture;
- module dependency order;
- package metadata;
- loader and lifecycle behaviour;
- production hardware acceptance.

A successful Tailscale SPK build does not validate the netfilter-module
package, and a successful module build does not validate the Tailscale SPK.

## Candidate and production boundary

Candidate builds may run locally or in CI with read-only repository
credentials. Stable publication and production DSM operations remain manual.

Never place production DSM credentials in a build environment or GitHub
Actions.
