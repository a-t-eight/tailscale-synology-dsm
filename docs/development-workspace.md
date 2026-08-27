# Development workspace

## Overview

The release workflow uses multiple Git worktrees and produces build outputs,
validation reports, caches, review material, and retained evidence. A
structured local workspace keeps those assets distinguishable and prevents a
temporary checkout or regenerable cache from being mistaken for an accepted
release input.

This guide defines a recommended local operating model. It does not prescribe
a host-specific filesystem path, and it does not make local directory names
authoritative release metadata.

## Recommended topology

```text
workspace/
  repositories/
    source/                       primary Git repository and upstream mirror
  worktrees/
    control/                      downstream control worktree
    accepted/<release>/           accepted release source worktree
    work/<task>/                  active source-development worktrees
    review/<task>/                temporary control and review worktrees
  artifacts/
    candidates/<release>/<run>/   build candidates and intermediate output
  evidence/
    releases/<release>/<run>/     retained validation and release evidence
    superseded/<release>/<run>/   retained evidence from replaced candidates
  cache/
    go-build/                     regenerable build cache
    go-mod/                       regenerable module cache
  archive/                        sealed historical material
  WORKSPACE-INVENTORY.md          host-local workspace register
```

Existing workspaces may adopt the model incrementally. The migration process
must preserve Git worktree registration, release evidence, checksums, and any
records that contain historical absolute paths.

## Workspace roles

| Role | Description | Authority |
| --- | --- | --- |
| Source repository | Owns the common Git object database and upstream mirror | Git object and worktree authority |
| Control worktree | Clean checkout of `synology/main` or a temporary control branch | Downstream manifests, tooling, and documentation |
| Accepted worktree | Clean checkout at the manifest's accepted release commit and tree | Source input for validation and reproduction |
| Development worktree | Active source or control change associated with a defined task | Temporary working state |
| Candidate artifacts | Outputs from a specific build run | Non-production until accepted |
| Release evidence | Checksums, reports, and sanitised acceptance evidence | Retained validation record |
| Cache | Reproducible, regenerable tool or build data | No release authority |
| Archive | Sealed historical material with recorded provenance | Retained according to project policy |

## Host-local inventory

Each development host should maintain a workspace inventory outside all Git
worktrees. The inventory is operational metadata and may contain local paths or
storage information that is unsuitable for the public repository.

The inventory should record the following fields for every top-level entry:

| Field | Description |
| --- | --- |
| Path | Exact local path |
| Type | Repository, worktree, evidence, candidate artifacts, cache, archive, tooling, or unknown |
| Git identity | Branch, commit, tree, common Git directory, and registration state where applicable |
| Working state | Clean, modified, untracked, detached, ahead, behind, broken, or not applicable |
| Release or task | Associated release revision, build identifier, or work item |
| Authority | Canonical, derived, evidence, cache, superseded, or unknown |
| Retention | Keep, archive, regenerate, review, or approved removal |
| Verification | Remote reference, checksum manifest, evidence seal, or other verifier |
| Notes | Dependencies, replacement location, or unresolved conditions |

### Disposition values

| Disposition | Meaning |
| --- | --- |
| `canonical-active` | Current control or accepted source worktree |
| `active-temporary` | Active task state with an identified owner and purpose |
| `retained-evidence` | Authoritative or supporting evidence retained for a release |
| `superseded-retained` | Replaced material retained for audit or provenance |
| `regenerable-cache` | Data that can be recreated from authoritative inputs |
| `archive-candidate` | Complete, sealed material eligible for archival storage |
| `cleanup-candidate` | Redundant material that has passed the cleanup assessment |
| `unknown-stop` | Unclassified material that must not be moved or removed |

## Inventory procedure

An initial inventory is read-only and records:

1. every top-level entry and its disk usage;
2. every Git repository and linked-worktree marker;
3. the complete `git worktree list --porcelain` output;
4. branch, commit, tree, upstream, and working-tree status;
5. remote branch identities without selecting a branch by name or timestamp;
6. unique commits, untracked files, candidate outputs, and evidence seals;
7. caches separately from candidate artifacts and release evidence;
8. an `unknown-stop` disposition for every unresolved entry.

A misplaced or incomplete `.git` directory is recorded as a topology defect.
It is not repaired or removed as part of the inventory phase.

## Worktree management

- Create and remove linked worktrees with `git worktree` commands.
- Move a linked worktree only with `git worktree move`, after confirming that
  it is clean and registered with the expected common repository.
- Configure hooks and signing for each worktree with
  `scripts/setup-worktree.sh` and the appropriate role.
- Maintain one clearly identified control worktree and one accepted source
  worktree for the current release.
- Associate every temporary worktree with an active task and planned
  disposition.
- Do not remove a worktree solely because its branch has been merged or deleted
  remotely; verify unique commits and untracked files first.

## Evidence and artifact management

Build candidates and release evidence have different retention semantics.
Candidate output may be regenerated, while accepted evidence must remain tied
to the package, source commit, and validation event it records.

Retained evidence should use release and run identifiers and include a checksum
manifest at the evidence root. Superseded evidence remains distinguishable
from the accepted release and is not overwritten by a later build.

Caches do not provide release provenance. They may be removed only after they
are positively identified as regenerable and are not referenced as retained
evidence.

## Workspace migration

Reorganising an existing workspace is performed in controlled phases:

1. capture and review the host-local inventory;
2. identify the canonical repository, control worktree, and accepted source
   worktree from Git and manifest identities;
3. classify all remaining entries and resolve `unknown-stop` items;
4. establish destination paths without overwriting existing content;
5. move registered worktrees with Git-aware operations;
6. move or archive evidence only after verifying checksums and recording the
   destination;
7. re-run repository and release validation from the new paths;
8. remove only the exact paths that have a recorded cleanup approval.

The inventory records old and new paths so that retained reports containing
historical paths remain interpretable.

## Cleanup criteria

An entry is eligible for removal only when all applicable conditions are met:

- the working tree contains no modified or untracked files;
- the entry contains no unique unpushed commit;
- no active task or registered worktree depends on it;
- it is not the canonical repository or accepted source worktree;
- it contains no unsealed or uniquely retained release evidence;
- an archived replacement and checksum are recorded when required;
- the removal target is explicit and narrowly scoped;
- the maintainer has approved the removal.

Workspace cleanup is independent of release acceptance. Publishing a release
does not itself authorise removal of source worktrees, build artifacts,
caches, or evidence.
