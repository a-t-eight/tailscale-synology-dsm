# Repository instructions

## Branch invariants

- Never commit downstream files or patches to `main`.
- `main` must remain a fast-forward mirror of `tailscale/tailscale`.
- Downstream control assets belong on `synology/main`.
- Applied source changes belong on `release/*-synology` or temporary
  `work/*-synology` branches.
- Production releases must be represented by a signed tag.

## Commit and patch rules

- Sign every downstream commit.
- Include exactly one `Signed-off-by` trailer.
- Keep each logical change in a separate commit.
- The signed commit stack is authoritative.
- Generate numbered patches with `git format-patch`.
- Never manually edit generated patch files.
- Correct the commit stack and regenerate the complete patch export.
- Use `git range-diff` when adapting the stack to a new upstream release.

## Source build rules

- Use the repository-pinned Go tool through `./tool/go`.
- Resolve `gofmt` through `$(./tool/go env GOROOT)/bin/gofmt`.
- Run Go, shell, package and patch round-trip tests before publishing a
  candidate build.
- Validate both the outer SPK metadata and inner package payload.

## Shell rules

- Scripts must be non-interactive unless explicitly documented.
- Do not use interactive `set -e` instructions.
- Do not depend on Bash-only `PIPESTATUS` in zsh operator instructions.
- Capture command exit status explicitly.
- Destructive operations require an explicit confirmation option.

## Production safety

Agents and automation may adapt patches, run tests, review changes and
build candidate artifacts.

Agents and automation must not:

- install or upgrade packages on the production NAS;
- run the root bootstrap;
- alter production firewall state;
- remove `/dev/net/tun`;
- reboot DSM;
- publish a stable production release;
- approve their own changes.
