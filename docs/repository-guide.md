# Repository guide

## Overview

This repository maintains a downstream Synology DSM distribution of Tailscale.
It combines an upstream source mirror, downstream source releases, and the
control material required to build, validate, and document those releases.

The repository uses multiple Git branch roots. Source code and release-control
material are intentionally separated so that upstream history remains
unmodified and downstream releases remain reproducible.

## Repository topology

```text
tailscale/tailscale
        |
        +-- main                         upstream source mirror
        |
        +-- release/<version>-synology   accepted downstream source
                    |
                    +-- release/synology-* signed release tag

synology/main                           downstream control branch
        |
        +-- temporary control branches  reviewed control changes

work/*                                  temporary source adaptation
```

### Branch and reference roles

| Reference | Purpose | Lifecycle |
| --- | --- | --- |
| `main` | Fast-forward mirror of upstream Tailscale | Contains no downstream commits or control files |
| `synology/main` | Default branch containing manifests, patch exports, validation, release evidence indexes, governance, and documentation | Updated through reviewed, signed commits |
| `release/<version>-synology` | Pinned upstream source with the accepted downstream commit stack applied | Retained without functional changes after release acceptance |
| `work/*` | Source adaptation, validation, or release preparation | Removed after integration and retention checks |
| Temporary control branches | Documentation, governance, and release-control changes based on `synology/main` | Removed after protected integration |
| `release/synology-*` | Signed identity for an accepted release commit | Permanent; tags are not moved or reused |

`synology/main` is the default branch because it presents the downstream
project, release metadata, and operating procedures. The `main` branch remains
an upstream source mirror and is not the project landing branch.

## Release identity and provenance

The current operational release is defined by
[`release/manifest.yaml`](../release/manifest.yaml). The manifest records the
upstream source, downstream revision, accepted commit and tree, package
identity, branch and tag names, validation inputs, and evidence locations.

Release-specific acceptance and publication information is maintained under
[`docs/releases/`](releases/). The root [README](../README.md) provides a
summary for package users; it does not replace the manifest or release
records.

### Authoritative records

| Record | Authority |
| --- | --- |
| Accepted SPK and independently verified checksum | Distributed package identity |
| Signed release tag, commit, and tree | Accepted source identity |
| Release branch and signed downstream commit stack | Maintained downstream source history |
| `release/manifest.yaml` | Current operational release configuration |
| Generated patch series and patch manifest | Reproduction of the downstream source stack |
| Machine-readable validation and reproducibility evidence | Results of automated release verification |
| Sanitised DSM acceptance evidence | Results observed on supported hardware |
| Acceptance closeout and publication record | Human release decision and publication event |

These records are expected to agree. A mismatch is a release-integrity failure
and must be reconciled before building, publishing, or modifying release state.
Historical release records and evidence remain unchanged when the current
manifest advances to a later release.

## Using the repository

### Package installation

Package users should obtain the SPK and checksum from a published GitHub
release and follow its release-specific installation instructions. Cloning the
repository is not required for normal installation.

### Control and documentation changes

Control changes start from the current remote `synology/main` branch and use a
dedicated worktree configured with the `control` role. Every downstream commit
must be signed, contain one matching sign-off, and pass the repository
validation suite before protected integration.

Downstream control files are never merged into `main`.

### Source development

Source development uses a separate worktree based on the upstream commit or
work branch declared by the manifest. Each logical downstream change is
recorded as a signed and signed-off commit.

The release patch series is generated from the final commit stack with
`git format-patch`. Generated patches are not edited manually; corrections are
made in the source commits and the complete patch series is regenerated.

### Release operations

Release operators follow the version-update, release-checklist, and
release-closeout runbooks. A successful build produces a candidate, not an
accepted release. Reproducibility, package inspection, DSM hardware
acceptance, release approval, and publication are separate gates.

Production package installation, administrator bootstrap, firewall changes,
reboot testing, and stable publication require explicit maintainer approval.

## Worktree configuration

Operations that require both downstream control files and Tailscale source use
separate Git worktrees:

```text
control worktree   synology/main or a temporary control branch
source worktree    release/<version>-synology or work/*
```

Configure each worktree with the repository entrypoint:

```text
bash scripts/setup-worktree.sh \
  --worktree /path/to/worktree \
  --control-worktree /path/to/control-worktree \
  --role control|accepted|work|release
```

The selected role configures the appropriate hooks and signing behavior.
Linked worktrees must be managed through `git worktree`; copying `.git` files
or moving linked worktrees as ordinary directories can invalidate their common
Git metadata.

## Release lifecycle

1. Pin an upstream tag and commit in the release manifest.
2. Prepare an isolated source worktree.
3. Adapt and validate the signed downstream commit stack.
4. Promote the accepted stack to a release branch.
5. Generate and validate the patch series and control records.
6. Build and inspect reproducible package candidates.
7. Complete DSM hardware acceptance with the exact candidate.
8. Integrate the acceptance closeout into `synology/main`.
9. Create the signed release tag and publish the reviewed assets after
   maintainer approval.
10. Record publication without modifying the frozen acceptance record.

Functional changes after acceptance require a new downstream revision or a new
pinned upstream release.

## Repository integrity requirements

- Build and validation commands use the explicit source worktree selected by
  the manifest.
- The workspace container and `synology/main` are not Tailscale source trees.
- Directory names and modification times do not establish release authority.
- Build success does not substitute for package inspection or DSM acceptance.
- Evidence is retained according to its recorded disposition before temporary
  branches, worktrees, or build outputs are removed.
