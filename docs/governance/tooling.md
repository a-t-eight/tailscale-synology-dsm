# Governance tooling

## Canonical command

Create or reuse a clean detached worktree at the accepted release commit:

```text
0fad8b81a3e0eb86c457bc79c474bcc213834c43
```

When exactly one clean registered worktree matches that commit and tree, run:

```text
bash scripts/validate-repository.sh --bootstrap
```

For CI or an ambiguous multi-worktree environment, pass it explicitly:

```text
bash scripts/validate-repository.sh \
  --source-environment /path/to/release-worktree \
  --bootstrap
```

The source environment must have tree:

```text
33f5c5927ae4db54b9d582650ed31cc6a2eb7161
```

All Go operations use that worktree's repository-pinned:

```text
./tool/go
```

Host `go`, npm and pip installations are not used.

The `--fast` option performs no network access and is used by the pre-commit
hook after the validator cache has been populated. The hook auto-discovers the
source environment only when exactly one clean registered worktree matches the
pinned commit and tree.

## Pinned tools

| Tool | Version | Source |
| --- | --- | --- |
| Go | repository-pinned by `./tool/go` | accepted release worktree |
| ShellCheck | `0.11.0` | checksum-verified release binary |
| shfmt | `3.13.1` | built with repository-pinned Go |
| actionlint | `1.7.12` | built with repository-pinned Go |
| Gitleaks | `8.30.1` | checksum-verified official release binary |
| text and YAML validator | repository-owned Go source | run with repository-pinned Go |
| actions/checkout | `v6.0.2`, full SHA in workflow | immutable Action reference |

## Cache location

Tools are installed under:

```text
${XDG_CACHE_HOME:-$HOME/.cache}/tailscale-synology-dsm/governance-tools
```

The cache is not part of the repository and may be deleted safely. Re-run the
bootstrap command to recreate it.

## Supply-chain controls

- the exact accepted release commit and tree identify the build environment;
- every Go build and `go run` operation uses the release worktree's `./tool/go`;
- ShellCheck is verified against the SHA-256 digest from its GitHub release;
- shfmt and actionlint use exact module versions;
- Gitleaks uses an exact release version and a pinned platform-specific
  SHA-256 that must match the GitHub release asset digest;
- the repository-owned text validator uses dependencies already pinned by the
  accepted Tailscale source module;
- external GitHub Actions are pinned to full commit SHAs;
- the semantic Action release is retained as a workflow comment.

A future phase may add complete transitive dependency locks, SBOM generation
and provenance attestations.

<!-- BEGIN RELEASE WORKTREE TOOLING -->

## Release worktree tooling

Use:

```text
bash scripts/setup-worktree.sh \
  --worktree /path/to/worktree \
  --control-worktree /path/to/control-worktree \
  --role control|accepted|work|release
```

The setup command enables Git worktree-specific configuration. Control
worktrees use their committed `.githooks`; source, work and release worktrees
use generated wrappers stored in the common Git directory.

This avoids a common `core.hooksPath=.githooks` value resolving to an absent
directory on upstream-derived source branches.

Release entrypoints are under `scripts/release/` and consume
`release/manifest.yaml`. They use Python only for standard-library manifest
parsing and use the selected source worktree's `./tool/go` for all Go
operations.

<!-- END RELEASE WORKTREE TOOLING -->

## Allowed-signers bootstrap

`.github/allowed_signers` contains public key material and is intentionally
committed. It is not a secret. The one-time repository variable
`RELEASE_ALLOWED_SIGNERS_SHA256` contains only the file SHA-256 and is used only while
the protected base is `c08cb5af27701615f6180d79182d2c8559c601bf` and lacks the file. Future CI reads
the signer file directly from the protected base checkout.


<!-- BEGIN SIGNED PROTECTED INTEGRATION TOOLING -->

## Signed protected integration tooling

Use the repository-owned integration entrypoint only with checksum-pinned review
evidence:

```text
bash scripts/governance/integrate-signed-pr.sh \
  --repository OWNER/REPOSITORY \
  --pr-number NUMBER \
  --control-branch synology/main \
  --work-branch BRANCH \
  --expected-base BASE_SHA \
  --expected-head REVIEWED_SHA \
  --review-evidence /path/to/review.json \
  --review-evidence-sha256 REVIEW_SHA256 \
  --pr-worktree /path/to/pr-worktree \
  --control-worktree /path/to/control-worktree \
  --source-worktree /path/to/accepted-source-worktree \
  --evidence-dir /path/to/evidence \
  --required-check repository-governance \
  --dry-run
```

After reviewing the plan, use `--confirm-integrate`. Use `--resume` only when a
prior run wrote a post-ref-update state record.

Run the synthetic safety suite with:

```text
bash tests/governance/integrate-signed-pr.sh
```

The fixture suite proves that an exact state passes while a moved base,
unsigned head, failed required check or unresolved review thread stops before
mutation. It also verifies the expected-old lease, new-check identity, terminal
fallback and resume controls.

<!-- END SIGNED PROTECTED INTEGRATION TOOLING -->

<!-- BEGIN TARGETED QUALITY TOOLING -->

## Secret scanning

Populate the pinned validator cache with:

```text
bash scripts/validate-repository.sh --bootstrap
```

Normal local and CI validation scans the current control tree. The pre-commit
hook invokes:

```text
bash scripts/validate-repository.sh --fast --staged-secrets
```

The staged mode uses Gitleaks `git --pre-commit --staged` with redacted output.
The repository does not create a Gitleaks baseline or ignore file
automatically.

## Static SPK inspection

Inspect one package without installing it:

```text
bash scripts/release/inspect-spk.sh \
  --spk /path/to/package.spk
```

Run the synthetic positive and negative fixture suite with:

```text
bash tests/quality/inspect-spk.sh
```

Candidate builds invoke the same inspector before generating accepted candidate
checksums and metadata. The inspector uses only Python standard-library archive
and JSON parsing plus `bash -n`; it never executes package content.

<!-- END TARGETED QUALITY TOOLING -->
