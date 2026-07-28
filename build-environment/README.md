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

The accepted `v1.98.96-r1` worked baseline is identified by:

```text
commit: 20c86229955a3d03de01901aee1499cab87c571d
tree:   6d022c18f27a42aab553697c69c852bebd8594b8
```

A future release must replace those manifest values with its own reviewed
identity. It must not silently reuse the current release identity.

## DSM netfilter-module environment

The netfilter-module package uses the corresponding `spksrc` cross-compilation
environment and Synology kernel/toolchain inputs for the target DSM platform.

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
