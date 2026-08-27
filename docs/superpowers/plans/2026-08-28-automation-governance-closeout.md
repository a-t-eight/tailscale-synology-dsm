# Automation governance closeout implementation plan

> **For agentic workers:** Execute each task in order and stop on any failed
> gate. Do not mutate accepted r2 source, package, tag, published release, or
> DSM state.

**Goal:** Complete the outstanding automation-governance, ruleset, workspace,
and archive controls while preserving the accepted r2 release.

**Architecture:** Keep `synology/main` authoritative for repository governance
and release operations, and keep the accepted release branch authoritative for
source validation. Document that split in one public catalogue, enforce its
stable identifiers offline, correct the contradictory live merge-method rule,
and preserve all evidence through the repository's signed protected-integration
contract.

**Tech stack:** Bash, Python standard library, Markdown, GitHub Actions YAML,
Git, GitHub CLI, and SHA-256 manifests.

**Approved design:**
`docs/superpowers/specs/2026-08-27-automation-governance-design.md`

## Global constraints

- Preserve accepted r2 commit `0fad8b81a3e0eb86c457bc79c474bcc213834c43`,
  its tree, signed tag, SPK bytes, checksums, published release, and DSM state.
- Do not enable immutable releases in this phase.
- Do not add or replace assets on the closed r2 release.
- Make detached checksum signing mandatory for the next stable publication.
- Do not change the bootstrap payload ownership or r3 trust-boundary design.
- Keep `.codex-build-cache` and the retained WSL release archive.
- Use one signed and signed-off direct-child commit for protected integration.

## Task 1: Pin the automation contract with a failing test

**Files:**

- Create: `tests/governance/automation-contract.sh`
- Modify: `scripts/validate-repository.sh`

1. Add an offline test that accepts the explicit accepted-source worktree.
2. Parse a fixed-width Markdown catalogue with Python's standard library.
3. Require exactly nine unique workflow rows.
4. Verify workflow paths, display names, status names, branch roots, and trigger
   categories against the control and accepted-source trees.
5. Run the test before the guide exists and record the expected failure.

## Task 2: Publish the automation governance guide

**Files:**

- Create: `docs/governance/automation.md`
- Modify: `README.md`
- Modify: `docs/README.md`
- Modify: `docs/repository-guide.md`
- Modify: `docs/governance/repository-governance.md`

1. Document the four validation lanes and nine active workflow records.
2. Distinguish downstream-owned, downstream-modified, and upstream-inherited
   automation.
3. Record what each workflow proves and does not prove.
4. Explain that Actions UI records and live rulesets are mutable GitHub state.
5. Link the guide from all public repository entry points.
6. Run the focused contract test and require success.

## Task 3: Make checksum signing a next-release publication gate

**Files:**

- Modify: `docs/runbooks/tailscale-synology-release-checklist.md`
- Modify: `docs/runbooks/tailscale-synology-release-closeout.md`

1. Require a detached signature for the published `SHA256SUMS` file.
2. Require verification against the maintainer's documented public key before
   publication is declared complete.
3. Record the signature filename, digest, signing identity, and verification
   result in the publication record.
4. State explicitly that this control applies to future releases and does not
   retroactively modify a closed release.

## Task 4: Correct the live release-branch merge-method contract

**External state:** GitHub ruleset `21299880` in
`a-t-eight/tailscale-synology-dsm`.

1. Capture the complete pre-change ruleset JSON.
2. Construct a full update payload preserving name, target, enforcement,
   bypass actors, conditions, and every rule except the allowed merge methods.
3. Change `allowed_merge_methods` from `merge` to `squash` and `rebase`.
4. Keep the separate no-bypass product-validation ruleset unchanged.
5. Re-query both rulesets and verify the layered effective policy.
6. Retain before/after evidence without exposing credentials.

## Task 5: Validate and integrate the exact reviewed commit

**Files:** All files above plus the approved design and this plan.

1. Run the focused automation contract.
2. Run `scripts/validate-repository.sh --fast` against the explicit accepted
   source worktree.
3. Run release validation with patch round-trip enabled.
4. Amend the unpublished design commit into one signed and signed-off commit.
5. Verify its parent, signature, trailer, changed paths, and clean worktree.
6. Push the temporary branch and open a pull request.
7. Capture checksum-pinned review evidence and run the integration dry run.
8. Integrate only through `scripts/governance/integrate-signed-pr.sh` after all
   required checks pass.
9. Revalidate persistent control and accepted-source worktrees.

## Task 6: Clean the temporary WSL state

**Files:**

- Modify: `/home/ateight/development/tailscale-synology-unjailed/WORKSPACE.md`

1. Confirm the temporary worktree is clean and its commit is integrated.
2. Delete the exact remote work branch, then the registered temporary worktree
   and both superseded local automation-governance branches.
3. Do not touch the persistent control, accepted r2, common/r1, archive, or
   `.codex-build-cache` paths.
4. Refresh `WORKSPACE.md` with the verified final control commit and retained
   three-worktree layout.

## Task 7: Copy and verify the sealed archive off WSL

**Source:**
`/home/ateight/development/tailscale-synology-unjailed/archive/releases/v1.98.96-r2`

**Destination:**
`/Users/andrew/Documents/ChatGPT/tailscale-synology-unjailed/archive/releases/v1.98.96-r2`

1. Verify the retained WSL archive manifests before copying.
2. Copy the complete archive without deleting the source.
3. Verify the destination manifests, file inventory, size, and Git bundle.
4. Record any newer governance evidence as an additive archive supplement;
   never rewrite accepted package evidence.

## Definition of done

- The public automation guide is exact and repository-validated.
- The canonical validator exercises the automation contract offline.
- Future publication requires a verifiable detached `SHA256SUMS` signature.
- The live release-branch rulesets permit only squash or rebase for ordinary
  pull-request merges while retaining product validation and owner break-glass.
- The exact signed commit is integrated through the protected path.
- Temporary WSL governance worktrees and branches are absent.
- `WORKSPACE.md` describes the retained layout accurately.
- The r2 archive exists and verifies independently on macOS.
