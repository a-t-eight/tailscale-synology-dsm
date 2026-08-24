# Agent upgrade workflow design

## Status

Approved for implementation on `codex/agent-upgrade-workflow`, based on the
clean candidate commit `8c9fe5239ee57a89ce687fc8c7608d3df91f6ede`.

## Problem

The working Tailscale 1.98.9 Synology implementation has a reviewed source
history and release evidence, but preparing a later upstream version still
requires an operator to coordinate several lower-level scripts manually. That
leaves room for selecting a floating upstream ref, applying changes out of
order, working in the wrong checkout, emitting incomplete artifacts, or
crossing a publication boundary accidentally.

The repository needs one deep, agent-facing command that turns exact local Git
identities into an isolated adaptation worktree and reviewable artifacts. It
must remain useful without network access and must stop safely when a logical
change conflicts with the selected upstream commit.

## Immutable baseline

The implementation starts from candidate commit
`8c9fe5239ee57a89ce687fc8c7608d3df91f6ede`, tree
`6d171c2a01c0fafb9567f3f4bc49bdd4f7ff7392`.

The following seven blobs are protected. This feature may inspect and validate
them but must not recreate, format, regenerate, or semantically alter them:

| Path | Candidate Git blob | Candidate SHA-256 |
| --- | --- | --- |
| `cmd/tailscale/cli/up.go` | `ace6ac3dbdcc42f18e3dadfacbc65cee1b1df311` | `5da19848c5a76a2242c300b8accf6ae2100d96589d66869eb374fc12337e31c1` |
| `cmd/tailscaled/tailscaled.go` | `6f0dcede86551dfb142f5a2a6944de92c1ecd756` | `684e79377cbbe79dc3d3ad7bc8400f26101d1d958ce78a9a724ab4a3d1571990` |
| `ipn/ipnlocal/local.go` | `b84205d914f2e47e4cefda1a4a0ce98202cd552f` | `dbbec62dd501abb1262593e19b70868d3b5ca478d6a9d9e7848d1cfb1256a570` |
| `util/linuxfw/iptables_runner.go` | `03d9b87a8c0c35d655e60b4456ba136116b6afd2` | `96d2122b8929433cb0ac987587ebf969406fb3d64067378b2b3975b810aeb137` |
| `wgengine/router/osrouter/router_linux.go` | `c48749734c5618bfe3973afbb2d00f75b34e0d13` | `54339503f0d7e5598aa3b507a7c685408bcd84d6580bde69acf19a5e60154da0` |
| `patches/v1.98.9/synology-netfilter.patch` | `b0a9474448b0f5bac5b24229ffe6827c4eebe897` | `ad577d4032e3c14fa37b284b7e5116c364122471b1d9fdc2c906bf8ae198920f` |
| `patches/v1.98.9/synology-netfilter.patch.sha256` | `5b88bba7a6ac4b8cea5d307bee5cdc9769e70ad4` | `b0a7641e8297c79ea2c40ffddc82632cfbdaf83029b4552e42572b227a2b7fe4` |

The r2/new-lineage Synology product contract is also fixed:

- dependency declaration: exactly `[iptables-netfilter-extensions]`;
- dependency minimum: exactly `pkg_min_ver=1.1.0-3`;
- dependency DSM floor: exactly `os_min_ver=7.3-86009`;
- Tailscale DSM floor: exactly `7.3-86009`;
- production r2 and later lineage: no `os_max_ver`.

## Selected architecture

Deepen the existing `scripts/release/prepare-worktree.sh` interface promoted
from `synology/main`. Preserve its manifest-driven worktree mode and add a
separate `prepare-version` mode with explicit, pinned inputs. Do not introduce
a second entry command.

The new mode accepts:

- `--source-repo PATH`;
- `--upstream-tag vN.N.N`;
- `--upstream-commit` as a full 40-character lowercase commit ID;
- `--previous-upstream-commit` as the exact old base;
- `--previous-release-commit` as the exact tip of the ordered logical stack;
- `--new-version N.N.N` and `--downstream-revision rN`;
- `--target-branch work/vN.N.N-synology-rN`;
- `--target-worktree PATH` and `--output-root PATH`;
- `--plan-only` for a read-only preflight or `--confirm-create` for mutation.

All identities must already exist locally. The command never fetches and the
explicit tag must peel to the explicit upstream commit. The old base must be an
ancestor of the old release tip. The old downstream range must be non-empty,
linear, and ordered oldest-to-newest. Target branch, worktree, and artifact
paths must not already exist.

After preflight, the command creates a Git worktree at the exact new upstream
commit. It replays each logical commit with `git cherry-pick --no-commit`,
removes inherited `Signed-off-by` trailers from the copied message, and creates
one signed commit with one current-identity sign-off. This preserves logical
order while making the new stack auditable under the current commit policy.
Commit signing must already be configured; a missing or failing signer stops
the operation.

Only after every commit succeeds does the command export mail patches with
`git format-patch`, write an ordered `series` file, write SHA-256 checksums, and
emit a schema-validated JSON preparation manifest plus a standard Markdown
evidence/PR report. It creates a temporary detached round-trip worktree at the
new upstream commit, applies the exported mail series, and requires its tree to
equal the prepared tree. Temporary round-trip state is removed on success.

If replay, signing, export, or round-trip validation fails, the command exits
nonzero and does not publish an artifact set. A replay conflict is aborted so
the target worktree is left free of Git conflict state for review. It never
removes a pre-existing path or ref.

## Manifest and artifact contract

`release/version-preparation.schema.json` defines the emitted JSON artifact.
The manifest records schema version, exact source and upstream identities,
ordered source commits, prepared branch/commit/tree, ordered mail patch names,
the fixed Synology contract, validation results, and all safety capabilities as
`false`.

The output directory is committed atomically by renaming a same-parent staging
directory only after validation. Its reviewable contents are:

```text
<output-root>/
  manifest.json
  SHA256SUMS
  patches/
    series
    0001-*.patch
    0002-*.patch
  preparation-report.md
```

The report uses the same identities as the JSON manifest and includes sections
for change summary, ordered logical history, validation evidence, fixed product
contract, risk/review notes, and explicit prohibited side effects.

## Control assets promoted without rewriting

The minimum coherent source-worktree control layer is promoted as exact blobs
from the accepted control worktree where possible:

- `AGENTS.md` and `CLAUDE.md`;
- repository-owned hooks and `scripts/setup-worktree.sh`;
- the existing `patches/v1.98.9` lineage files, added alongside the protected
  canonical source patch/checksum without replacing either;
- `release/manifest.yaml` as the immutable accepted r1 operational record;
- `scripts/release/common.sh` and `scripts/release/prepare-worktree.sh`;
- the existing version-update runbook, then a focused edit describing the new
  mode;
- only tests directly needed to prove the promoted and new interface.

Frozen r1 closure validators, build/publish scripts, retained runtime evidence,
and unrelated governance material are not copied merely for completeness.

## Test strategy

The primary test is an offline Bash integration test. It creates a temporary
Git repository with:

1. an old upstream commit;
2. two ordered downstream commits;
3. a distinct new upstream commit and explicit local tag;
4. an SSH signing key generated in the fixture and configured only in that
   repository;
5. a local bare `origin` whose refs are snapshotted before invocation.

The success case runs the real script and asserts the isolated worktree base,
logical commit order, one sign-off per generated commit, valid signatures,
schema-valid manifest, ordered patches, matching round-trip tree, fixed product
contract, and unchanged origin/tag refs.

The conflict case creates a new upstream commit that conflicts with the first
downstream logical change. It asserts a nonzero exit, an explanatory failure,
no final artifact directory, no conflict state in the target worktree, and
unchanged local tags and remote refs.

The preflight case supplies a tag/commit mismatch and asserts failure before
any branch, worktree, staging directory, or artifact is created.

The test is written and observed failing before implementation. Each added
behavior follows its own red-green cycle.

## Safety boundary

The interface may create local branches, local worktrees, signed local commits,
temporary round-trip worktrees, and review artifacts under exact caller paths.
It must not fetch, push, create a pull request, create or alter a tag, build an
SPK, build the dependency SPK, publish, release, install on a NAS, run root
bootstrap, alter firewall/netfilter state, or reboot DSM.

## Cleanup boundary

Cleanup happens only after feature verification. A pre-cleanup report must name
every proposed target, classification, evidence, and decision. Detached dirty
evidence worktrees may be removed only when their staged trees equal the
accepted candidate tree and no untracked or unstaged product change exists.
Top-level patch copies may be removed only after recording equality or
distinction from the canonical in-repository patch and confirming the canonical
checksum. Ambiguous targets remain untouched.
