# Development workspace guide

## Purpose

Release work creates control checkouts, source worktrees, candidate outputs,
caches, reproducibility pairs, review bundles, and retained evidence. Without a
recorded role and retention policy, descriptive directory names eventually
become unreliable.

The workspace root is a container for repositories and evidence. It is not
itself a Git repository and must not be used as a build source.

## Recommended layout

```text
tailscale-synology-workspace/
  control/                       clean synology/main worktree
  worktrees/
    accepted/<release>/          accepted source worktree
    work/<task>/                 active temporary source worktrees
    review/<task>/               temporary documentation/control worktrees
  evidence/
    releases/<release>/<run-id>/ retained checksums, reports, and artifacts
    superseded/<release>/<run-id>/retained superseded evidence
  cache/
    go-build/                    reproducible build cache, not evidence
    go-mod/                      module cache, not evidence
  archive/                       sealed historical bundles
  WORKSPACE-INVENTORY.md         local operational inventory
```

The names describe desired roles, not authority. Git objects, manifest values,
checksums, and evidence seals determine authority.

## Workspace inventory

Maintain one local `WORKSPACE-INVENTORY.md` outside every Git worktree. It may
contain host-specific paths and storage details that do not belong in the
public repository.

Record one row per top-level path:

| Field | Meaning |
| --- | --- |
| Path | Exact absolute or workspace-relative path |
| Type | Control worktree, source worktree, standalone clone, evidence, cache, archive, script, or unknown |
| Git identity | Branch, HEAD, tree, common Git directory, and registered-worktree state |
| Status | Clean, dirty, broken, detached, ahead, behind, or unknown |
| Size | Current disk usage |
| Release or task | Manifest revision, build ID, or task identifier |
| Authority | Canonical, derived, evidence, cache, superseded, or unknown |
| Retention | Keep, archive, regenerate, review, or approved removal |
| Verification | Checksum manifest, evidence seal, remote ref, or reason no verifier exists |
| Notes | Dependencies, replacement path, or blocking uncertainty |

Use these disposition values consistently:

- `canonical-active` — current clean control or accepted source worktree;
- `active-temporary` — current work with an owner and task;
- `retained-evidence` — authoritative or supporting evidence that must remain;
- `superseded-retained` — replaced but intentionally preserved evidence;
- `regenerable-cache` — safe to recreate after verification;
- `archive-candidate` — complete, sealed, and no longer active;
- `cleanup-candidate` — proven redundant and eligible for separate approval;
- `unknown-stop` — insufficient evidence; do not move or remove.

## Read-only inventory procedure

Before reorganising anything:

1. List every top-level entry and its size.
2. Identify every `.git` directory and linked-worktree `.git` file.
3. Record `git worktree list --porcelain` from the common repository.
4. Record branch, HEAD, tree, upstream tracking, and complete worktree status.
5. Compare local branch tips with remote refs without changing them.
6. Identify unique commits, untracked files, build outputs, and evidence seals.
7. Classify caches separately from evidence.
8. Mark every uncertain path `unknown-stop`.

An empty or misplaced `.git` directory at the workspace root must be treated as
a topology defect, not repaired or deleted during inventory.

## Reorganisation rules

- Preserve accepted and superseded evidence before convenience cleanup.
- Never move a linked Git worktree with plain `mv`; use `git worktree move`
  only after its common repository and cleanliness are verified.
- Never remove a worktree merely because its branch was merged or deleted
  remotely. Check for unique commits and untracked files first.
- Do not combine caches with evidence or use a cache checksum as release proof.
- Do not overwrite an existing build or review directory with a cleaner copy.
- Keep one clean control worktree and one explicitly identified accepted source
  worktree. Create task worktrees only for active work.
- Store large immutable evidence under release and run identifiers, with a
  checksum manifest at the evidence root.
- Record moves in the inventory so retained reports containing old absolute
  paths remain understandable.

## Cleanup gate

A path is eligible for removal only when all applicable checks pass:

- no dirty or untracked content;
- no unique unpushed commit;
- no active task or registered worktree dependency;
- no canonical branch or accepted source role;
- no unsealed release evidence;
- replacement location and checksum are recorded when content was archived;
- removal target is exact and narrow;
- the maintainer separately approves the removal.

Workspace cleanup is not part of release validation. A successful release does
not authorise deletion of its worktrees, build outputs, caches, or evidence.

## Ongoing discipline

At the end of each task, update the inventory with:

- created and retired worktrees;
- current branch and commit;
- new evidence root and seal;
- cache ownership;
- approved cleanup candidates;
- unresolved paths.

This makes the inventory the map of the local workspace while the repository
manifest remains the map of the product release.
