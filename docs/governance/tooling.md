# Governance tooling

## Canonical command

Create or reuse a clean detached worktree at the accepted release commit:

```text
20c86229955a3d03de01901aee1499cab87c571d
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
6d022c18f27a42aab553697c69c852bebd8594b8
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
- the repository-owned text validator uses dependencies already pinned by the
  accepted Tailscale source module;
- external GitHub Actions are pinned to full commit SHAs;
- the semantic Action release is retained as a workflow comment.

A future phase may add complete transitive dependency locks, SBOM generation
and provenance attestations.
