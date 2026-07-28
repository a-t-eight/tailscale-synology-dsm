#!/usr/bin/env bash
set -u

SCRIPT_DIR="$(
  cd \
    "$(dirname "${BASH_SOURCE[0]}")" &&
    pwd
)"

# shellcheck source=common.sh
. "${SCRIPT_DIR}/common.sh"

CONTROL_WORKTREE="$(
  cd \
    "${SCRIPT_DIR}/../.." &&
    pwd
)"
SOURCE_WORKTREE=""
MANIFEST=""
CANDIDATE_ROOT=""
EVIDENCE_ROOT=""
CONFIRM_COLLECT=0
DRY_RUN=0

usage() {
  cat << 'USAGE'
Usage:
  bash scripts/release/collect-evidence.sh \
    --source-worktree PATH \
    --candidate-root PATH \
    [--control-worktree PATH] \
    [--manifest PATH] \
    [--evidence-root PATH] \
    [--confirm-collect]

Use --dry-run to validate and print the evidence layout without creating it.
This command never collects DSM runtime data automatically.
USAGE
}

while [ "$#" -gt 0 ]; do
  case "$1" in
    --control-worktree)
      CONTROL_WORKTREE="$2"
      shift
      ;;
    --source-worktree)
      SOURCE_WORKTREE="$2"
      shift
      ;;
    --manifest)
      MANIFEST="$2"
      shift
      ;;
    --candidate-root)
      CANDIDATE_ROOT="$2"
      shift
      ;;
    --evidence-root)
      EVIDENCE_ROOT="$2"
      shift
      ;;
    --confirm-collect)
      CONFIRM_COLLECT=1
      ;;
    --dry-run)
      DRY_RUN=1
      ;;
    --help | -h)
      usage
      exit 0
      ;;
    *)
      release_fail "unsupported option: $1"
      usage >&2
      exit 2
      ;;
  esac
  shift
done

if [ -z "$SOURCE_WORKTREE" ] ||
  [ -z "$CANDIDATE_ROOT" ]; then
  release_fail "--source-worktree and --candidate-root are required"
  exit 2
fi

if [ -z "$MANIFEST" ]; then
  MANIFEST="${CONTROL_WORKTREE}/release/manifest.yaml"
fi

release_require_worktree "$CONTROL_WORKTREE" || exit 1
release_require_worktree "$SOURCE_WORKTREE" || exit 1
release_validate_manifest "$MANIFEST" || exit 1

if [ -z "$EVIDENCE_ROOT" ]; then
  evidence_relative="$(release_manifest_get "$MANIFEST" paths.evidence)"
  EVIDENCE_ROOT="$(release_resolve_path "$CONTROL_WORKTREE" "$evidence_relative")"
else
  EVIDENCE_ROOT="$(
    python3 \
      - "$EVIDENCE_ROOT" << 'PY'
import sys
from pathlib import Path

print(Path(sys.argv[1]).expanduser().resolve())
PY
  )"
fi

CANDIDATE_ROOT="$(
  python3 \
    - "$CANDIDATE_ROOT" << 'PY'
import sys
from pathlib import Path

print(Path(sys.argv[1]).expanduser().resolve())
PY
)"

printf '=== Evidence collection plan ===\n'
printf 'Source worktree: %s\n' "$SOURCE_WORKTREE"
printf 'Candidate root:  %s\n' "$CANDIDATE_ROOT"
printf 'Evidence root:   %s\n' "$EVIDENCE_ROOT"
printf 'Runtime capture: manual and sanitised only\n'

if [ "$DRY_RUN" -eq 1 ]; then
  release_pass "evidence collection plan is valid."
  release_notice "no evidence directory or file was created."
  exit 0
fi

if [ "$CONFIRM_COLLECT" -ne 1 ]; then
  release_fail "--confirm-collect is required for mutation"
  exit 2
fi

if [ ! -s "$CANDIDATE_ROOT/candidate-SHA256SUMS" ] ||
  [ ! -s "$CANDIDATE_ROOT/candidate-build-metadata.json" ]; then
  release_fail "candidate checksums or build metadata are absent"
  exit 1
fi

mkdir -p \
  "$EVIDENCE_ROOT/source-validation" \
  "$EVIDENCE_ROOT/shell-regression" \
  "$EVIDENCE_ROOT/reproducible-build" \
  "$EVIDENCE_ROOT/dsm-runtime"

install \
  -m \
  0644 \
  "$CANDIDATE_ROOT/candidate-SHA256SUMS" \
  "$EVIDENCE_ROOT/SHA256SUMS"

install \
  -m \
  0644 \
  "$CANDIDATE_ROOT/candidate-build-metadata.json" \
  "$EVIDENCE_ROOT/reproducible-build/candidate-build-metadata.json"

python3 \
  - \
  "$MANIFEST" \
  "$SOURCE_WORKTREE" \
  "$CANDIDATE_ROOT" \
  "$EVIDENCE_ROOT" << 'PY'
from __future__ import annotations

import json
import subprocess
import sys
from datetime import datetime, timezone
from pathlib import Path

manifest = json.loads(Path(sys.argv[1]).read_text(encoding="utf-8"))
source = Path(sys.argv[2])
candidate = Path(sys.argv[3])
evidence = Path(sys.argv[4])

assets = sorted(candidate.rglob("*.spk"))

rows = [
    "filename\tsha256\tstatus",
]

checksum_map = {}

for line in (candidate / "candidate-SHA256SUMS").read_text(
    encoding="utf-8"
).splitlines():
    digest, filename = line.split(maxsplit=1)
    checksum_map[filename.lstrip("*")] = digest

for asset in assets:
    relative = asset.relative_to(candidate).as_posix()
    rows.append(
        f"{relative}\t{checksum_map.get(relative, 'UNVERIFIED')}\tcandidate"
    )

(evidence / "release-assets.tsv").write_text(
    "\n".join(rows) + "\n",
    encoding="utf-8",
)

source_commit = subprocess.check_output(
    ["git", "-C", str(source), "rev-parse", "HEAD"],
    text=True,
).strip()

source_tree = subprocess.check_output(
    ["git", "-C", str(source), "rev-parse", "HEAD^{tree}"],
    text=True,
).strip()

readme = f"""# Release evidence

## Status

This directory contains candidate evidence only. Production acceptance requires
a separate reviewed DSM hardware record.

## Identity

- generated: `{datetime.now(timezone.utc).isoformat()}`;
- upstream tag: `{manifest["upstream"]["tag"]}`;
- source commit: `{source_commit}`;
- source tree: `{source_tree}`;
- package version: `{manifest["package"]["full_version"]}`.

## Evidence categories

- `source-validation/`
- `shell-regression/`
- `reproducible-build/`
- `dsm-runtime/`
- `SHA256SUMS`
- `release-assets.tsv`

Do not commit unsanitised tailnet status, authentication material, private host
inventories or complete runtime archives.
"""

(evidence / "README.md").write_text(
    readme,
    encoding="utf-8",
)

runtime = """# DSM runtime acceptance

Runtime acceptance is manual. Record only sanitised evidence reviewed for:

- installation or upgrade result;
- binary and commit identity;
- retained state and node identity;
- routing and netfilter state;
- lifecycle or reboot testing;
- rollback viability.

Do not include authentication material, tailnet names, private addressing or a
full runtime archive.
"""

(evidence / "dsm-runtime/README.md").write_text(
    runtime,
    encoding="utf-8",
)
PY

release_pass "candidate evidence skeleton and checksum index were created."
release_notice "DSM runtime acceptance remains manual and human-reviewed."
