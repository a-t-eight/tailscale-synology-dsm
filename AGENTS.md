# Repository instructions

## Branch invariants

- Never commit downstream files or patches to `main`.
- `main` must remain a fast-forward mirror of `tailscale/tailscale`.
- Downstream control assets belong on `synology/main`.
- Applied source changes belong on `release/*-synology` or temporary
  `work/*-synology` branches.
- Production releases must be represented by a signed tag.
- A closed release is immutable.

## Release manifest contract

- `release/manifest.yaml` is the canonical operational release identity.
- Never select an upstream version from an implicit `latest` reference.
- Require an explicit upstream tag and full commit SHA.
- Derive branch names, build paths, evidence paths and package identity from the
  manifest.
- Stop if manifest values conflict with Git objects, patches, packages or
  retained evidence.
- Examples in documentation must be clearly labelled and must not override the
  manifest.

## Runtime architecture invariants

The downstream product deliberately promotes the installed DSM package into a
persistent root runtime through an attended administrator bootstrap. Security
work must harden what that privileged runtime trusts; it must not reduce the
runtime privilege required by the product.

After successful bootstrap, future changes must preserve:

- `tailscaled` running as UID 0;
- effective `run-as: root` package execution;
- the promoted package target owned `root:root`;
- kernel TUN operation;
- subnet routing and `--accept-routes` support;
- exit-node operation;
- the normal Linux netfilter backend;
- use of the required Synology netfilter-extension package;
- downstream removal of upstream Synology feature gates that conflict with
  these capabilities;
- upstream `SYNOPKG_PKGVAR` locations for daemon state, LocalAPI socket, PID and
  stdout log;
- upstream logrotate, DSM web-interface and package-data ownership semantics.

Do not reinterpret trust-boundary hardening as a mandate to return to the
ordinary DSM package-user or Package Center capability model. Do not re-enable
upstream Synology restrictions merely to reduce privilege. Any proposal that
changes one of these invariants requires an explicit architecture decision and
must be treated as a product regression risk.

Task 5 is defined by
`docs/adr/0002-privileged-bootstrap-trust-boundary.md` and the authoritative
`docs/superpowers/specs/2026-08-28-upstream-compatible-root-control-design.md`.
Do not relocate or recursively re-own upstream daemon application state as part
of that task. Only downstream bootstrap/reconciliation control material may
move to the approved `conf/root-control` and `/run/tailscale-synology`
boundaries. Task 5 `install` and `remove` operations must enter through the
root-owned package-script bootstrap; the target-linked command is status-only.

## Commit and patch rules

- Sign every downstream commit.
- Include exactly one `Signed-off-by` trailer.
- The immutable accepted baseline may enumerate exact historical commits that
  predate the sign-off rule in
  `validation.accepted_legacy_no_signoff_commits`.
- That exception applies only to the exact accepted release commit and tree.
  New, rebased or regenerated commits must not inherit the exception.
- Keep each logical change in a separate commit.
- The signed commit stack is authoritative.
- The manifest declares the canonical patch-series format and exact applied
  patch filenames.
- The accepted baseline uses `release-tree.patch` as its aggregate raw diff.
  `maintenance.patch` is a separately validated contained reference subset and
  must not be applied sequentially before or after the aggregate.
- New release series must be generated as signed-commit mail patches with
  `git format-patch` and set `validation.patch_series_format` to `mail`.
- Never manually edit generated patch files.
- Correct the commit stack and regenerate the complete patch export.
- Use `git range-diff` when adapting the stack to a new upstream release.

## Source build rules

- Use the source worktree's repository-pinned Go tool through `./tool/go`.
- Resolve `gofmt` through `$(./tool/go env GOROOT)/bin/gofmt`.
- Do not use a host Go installation for release work.
- Run Go, shell, package and patch round-trip tests before publishing a
  candidate build.
- Validate both the outer SPK metadata and inner package payload.
- Record the source commit, source tree, pinned Go version and package
  checksums.

## Worktree rules

- Configure hooks and signing explicitly for each control, work and release
  worktree.
- Do not rely on a branch-relative `.githooks` path that is absent from source
  branches.
- Use `scripts/setup-worktree.sh` for worktree-specific configuration.
- Stop when more than one worktree could satisfy a source-environment
  selection.

## Shell rules

- Scripts must be non-interactive unless explicitly documented.
- Do not use interactive `set -e` instructions.
- Do not depend on Bash-only `PIPESTATUS` in zsh operator instructions.
- Capture command exit status explicitly.
- Destructive operations require an explicit confirmation option.
- Long procedures must be complete child Bash scripts checked with `bash -n`.

## Agent and automation permissions

Agents and automation may:

- audit release inputs;
- create temporary adaptation worktrees after exact guards pass;
- adapt source commits and regenerate patches;
- run tests and patch round-trip validation;
- inspect packages;
- build non-production candidates;
- prepare sanitised evidence;
- draft pull requests and release records.

Agents and automation must not:

- install or upgrade packages on the production NAS;
- run the root bootstrap;
- alter production firewall or netfilter state;
- remove `/dev/net/tun`;
- reboot DSM;
- collect or commit unsanitised runtime archives;
- publish a stable production release;
- approve their own changes;
- bypass a failed required validation.
