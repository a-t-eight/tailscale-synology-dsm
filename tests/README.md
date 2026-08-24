# Tests

Source-owned Synology regression tests remain under
`release/dist/synology/tests/` on each downstream release branch. They are not
duplicated on the control branch.

Control-branch test content records:

- patch-series round-trip validation;
- release asset and shell syntax audits;
- isolated shell regression results;
- SPK metadata and privilege-manifest inspection;
- NAS runtime and netfilter acceptance evidence.

Source-worktree workflow checks are:

- `releases/version-preparation-contract.sh` — validates the accepted r2
  candidate, seven protected blobs, exact package dependency/DSM contract,
  output schema and disabled safety capabilities;
- `releases/prepare-version-workflow.sh all` — creates real offline Git
  fixtures and proves signed ordered replay, review artifacts, patch round
  trip, identity mismatch rejection, conflict cleanup and absence of remote,
  tag or SPK side effects.
- `releases/shellcheck.sh` — is the canonical changed-shell static-analysis
  command. It runs ShellCheck with `--severity=style`, so error, warning,
  information, and style diagnostics are all visible and enforced.
- `releases/diff-check.sh` — runs the complete
  `git diff --check 8c9fe5239ee57a89ce687fc8c7608d3df91f6ede..HEAD`
  gate. Git attributes suppress only `blank-at-eol`, `blank-at-eof`, and
  `space-before-tab` diagnostics inside checksum-locked historical `.patch`
  payloads under `patches/v1.98.9/`; all Markdown, scripts, source, and other
  paths remain strict. Its disposable negative fixture proves a real Markdown
  defect fails.

Run the canonical command from the repository root:

```text
bash tests/releases/shellcheck.sh
bash tests/releases/diff-check.sh
```

`releases/validate-production-contract.sh` builds disposable local fixtures for
the accepted release identity. It distinguishes living accepted identity from
historical patch lineage, rejects structured metadata and evidence drift, and
does not inspect mutable build output.

## Release evidence

- `releases/v1.98.9/` — accepted validation evidence for the v1.98.9 Synology
  release.

Generated evidence must identify the exact tested release commit and include
checksums for retained logs and machine-readable results.
