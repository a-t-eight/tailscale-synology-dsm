# Repository guide

## Purpose

This repository combines an upstream Tailscale source mirror, downstream
Synology source releases, and the control material used to reproduce and
validate those releases. These histories intentionally occupy different Git
branch roots.

The repository is not a conventional application repository where every file
exists on every branch. A missing downstream file on `main`, or missing
Tailscale source on `synology/main`, is expected.

## Branch model

```text
tailscale/tailscale
        |
        +-- main                         exact upstream mirror
        |
        +-- release/<version>-synology   pinned source plus signed patches
                    |
                    +-- release/synology-* signed release tag

synology/main                           downstream control and documentation
        |
        +-- codex/*, docs/*, operations/* reviewed control changes

work/*                                  temporary source adaptation
```

| Branch or ref | Contains | Does not contain |
| --- | --- | --- |
| `main` | Upstream Tailscale history | Downstream manifests, patches, evidence, or documentation |
| `synology/main` | Release manifest, generated patches, validation, evidence indexes, runbooks, and governance | A buildable Tailscale source tree |
| `release/*-synology` | Pinned Tailscale source and the applied signed downstream commit stack | Control-branch documentation and orchestration |
| `work/*` | Temporary source adaptation or release preparation | A durable production identity |
| Signed release tag | One accepted release commit | Mutable development state |

`synology/main` is the GitHub default branch because it explains and controls
the downstream project. `main` remains available for upstream synchronisation
without downstream contamination.

## Current r2 mapping

| Role | Ref |
| --- | --- |
| Control branch | `synology/main` |
| Upstream mirror | `main` |
| Pinned upstream source | `v1.98.9` at `6c167d40fa37aeb51afa7ff336730670ea4762bf` |
| Accepted source branch | `release/v1.98.9-r2-synology` |
| Accepted source commit | `0fad8b81a3e0eb86c457bc79c474bcc213834c43` |
| Accepted source tree | `33f5c5927ae4db54b9d582650ed31cc6a2eb7161` |
| Signed release tag | `release/synology-v1.98.96-r2` |
| Control identity | `release/manifest.yaml` on `synology/main` |

Never infer the current release from a directory name, most recently modified
worktree, or floating upstream reference. Read `release/manifest.yaml` and
verify its values against Git objects and retained evidence.

## Sources of truth

When two records disagree, use this order:

1. accepted SPK bytes and independently calculated checksum;
2. signed release tag, release commit, and Git tree;
3. canonical release branch and signed source stack;
4. `release/manifest.yaml` and generated patch-series manifest;
5. machine-readable validation and reproducibility evidence;
6. sanitised DSM acceptance evidence;
7. release closeout and publication records;
8. summary documentation and conversation history.

Historical records are not silently rewritten when a newer release supersedes
them. Living summaries, such as the root README and current manifest, move to
the new production baseline while release-specific evidence remains frozen.

## How to use the repository

### Package user

Do not build from a source branch unless you are reproducing the release.
Download the SPK and checksum from the published GitHub release and follow its
installation notes. The release notes are authoritative for the first
administrator-bootstrap command and known runtime limitations.

### Documentation or control contributor

Start from the latest remote `synology/main`, create a temporary branch, and
change only control-branch content. Use the repository hook setup with role
`control`, run the complete repository validator, create a signed and
signed-off commit, and submit it through the protected pull-request workflow.

Never merge downstream control files into `main`.

### Source developer

Use a separate worktree based on the manifest's pinned upstream commit or
declared `work/*` branch. Configure it with role `work`. Keep each logical
source change in a signed and signed-off commit. Regenerate the complete mail
patch series from the source stack; do not edit generated patches manually.

### Release operator

Use the version-update, release-checklist, and release-closeout runbooks. A
candidate build is not a production release. Package publication, DSM
installation, administrator bootstrap, firewall changes, and reboot testing
remain separate human-approved gates.

## Worktrees

Operations that require both control files and Tailscale source use distinct
Git worktrees. A normal release operation therefore has at least:

```text
control worktree   synology/main
source worktree    release/<version>-synology or work/*
```

Configure each worktree explicitly:

```text
bash scripts/setup-worktree.sh \
  --worktree /path/to/worktree \
  --control-worktree /path/to/control-worktree \
  --role control|accepted|work|release
```

The role selects the correct hook behavior. Do not copy `.git` files, move a
linked worktree with an ordinary filesystem move, or reuse hook configuration
from a different role.

## Release lifecycle

1. Pin an explicit upstream tag and commit in the manifest.
2. Prepare a `work/*` source worktree.
3. Adapt and validate the signed source stack.
4. Promote the exact accepted stack to a release branch.
5. Regenerate and validate the control-branch patch series and evidence.
6. Build reproducibly and inspect package contents.
7. Complete DSM hardware acceptance.
8. Merge the acceptance closeout record into `synology/main`.
9. Create the signed release tag and publish exact reviewed assets after human
   approval.
10. Record publication separately and direct all future functional changes to
    a new revision or upstream baseline.

## Common mistakes

- Treating the workspace root as a Git repository.
- Building from `synology/main`, which is not the Tailscale source tree.
- Editing `main` with downstream files.
- Selecting whichever worktree has the newest timestamp.
- Treating a clean build as DSM runtime acceptance.
- Replacing or deleting superseded evidence before its retention disposition is
  recorded.
- Running a package-owned script through `sudo` and treating elevation as proof
  that the script is trusted.
