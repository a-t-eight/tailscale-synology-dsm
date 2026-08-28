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
OUTPUT_ROOT=""
ROLE="release"
CONFIRM_BUILD=0
DRY_RUN=0

usage() {
  cat << 'USAGE'
Usage:
  bash scripts/release/build-candidate.sh \
    --source-worktree PATH \
    [--control-worktree PATH] \
    [--manifest PATH] \
    [--output-root PATH] \
    [--role release|accepted] \
    [--confirm-build]

Use --dry-run to validate and print the exact build command without building.
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
    --output-root)
      OUTPUT_ROOT="$2"
      shift
      ;;
    --role)
      ROLE="$2"
      shift
      ;;
    --confirm-build)
      CONFIRM_BUILD=1
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

if [ "$ROLE" != "release" ] &&
  [ "$ROLE" != "accepted" ]; then
  release_fail "--role must be release or accepted"
  exit 2
fi

if [ -z "$SOURCE_WORKTREE" ]; then
  release_fail "--source-worktree is required"
  exit 2
fi

if [ -z "$MANIFEST" ]; then
  MANIFEST="${CONTROL_WORKTREE}/release/manifest.yaml"
fi

release_require_worktree "$CONTROL_WORKTREE" || exit 1
release_require_worktree "$SOURCE_WORKTREE" || exit 1
release_validate_manifest "$MANIFEST" || exit 1
release_require_clean_worktree "$SOURCE_WORKTREE" || exit 1

if [ -d /usr/syno ] ||
  [ -f /etc.defaults/VERSION ]; then
  release_fail "candidate builds must not run on a Synology DSM host"
  exit 1
fi

PACKAGE_VERSION="$(release_manifest_get "$MANIFEST" package.version)"
BUILD_RELATIVE="$(release_manifest_get "$MANIFEST" paths.build_entrypoint)"
OUTPUT_RELATIVE="$(release_manifest_get "$MANIFEST" paths.build_output)"
INSPECTOR_RELATIVE="$(release_manifest_get "$MANIFEST" paths.spk_inspector)"
BUILD_ENTRYPOINT="$(release_resolve_path "$SOURCE_WORKTREE" "$BUILD_RELATIVE")"
SPK_INSPECTOR="$(release_resolve_path "$CONTROL_WORKTREE" "$INSPECTOR_RELATIVE")"

if [ -z "$OUTPUT_ROOT" ]; then
  OUTPUT_ROOT="$(release_resolve_path "$SOURCE_WORKTREE" "$OUTPUT_RELATIVE")"
else
  OUTPUT_ROOT="$(
    python3 \
      - "$OUTPUT_ROOT" << 'PY'
import sys
from pathlib import Path

print(Path(sys.argv[1]).expanduser().resolve())
PY
  )"
fi

if [ ! -x "$BUILD_ENTRYPOINT" ]; then
  release_fail "build entrypoint is missing or not executable: ${BUILD_ENTRYPOINT}"
  exit 1
fi

if [ ! -x "$SPK_INSPECTOR" ]; then
  release_fail "SPK inspector is missing or not executable: ${SPK_INSPECTOR}"
  exit 1
fi

printf '=== Candidate build plan ===\n'
printf 'Source worktree: %s\n' "$SOURCE_WORKTREE"
printf 'Control worktree: %s\n' "$CONTROL_WORKTREE"
printf 'Role:             %s\n' "$ROLE"
printf 'Package version:  %s\n' "$PACKAGE_VERSION"
printf 'Build entrypoint: %s\n' "$BUILD_ENTRYPOINT"
printf 'Output root:      %s\n' "$OUTPUT_ROOT"
printf 'Pinned Go:        %s\n' "$SOURCE_WORKTREE/tool/go"
printf 'Pinned Go version:%s\n' " $(
  "$SOURCE_WORKTREE/tool/go" \
    version
)"

if [ "$DRY_RUN" -eq 1 ]; then
  bash \
    "$CONTROL_WORKTREE/scripts/release/validate-release.sh" \
    --control-worktree \
    "$CONTROL_WORKTREE" \
    --source-worktree \
    "$SOURCE_WORKTREE" \
    --manifest \
    "$MANIFEST" \
    --role \
    "$ROLE" \
    --fast

  validate_rc=$?

  if [ "$validate_rc" -ne 0 ]; then
    echo "STOP: candidate build plan validation failed."
    exit "$validate_rc"
  fi

  release_pass "candidate build plan is valid."
  release_notice "no build command was executed."
  exit 0
fi

if [ "$CONFIRM_BUILD" -ne 1 ]; then
  release_fail "--confirm-build is required for a candidate build"
  exit 2
fi

bash \
  "$CONTROL_WORKTREE/scripts/release/validate-release.sh" \
  --control-worktree \
  "$CONTROL_WORKTREE" \
  --source-worktree \
  "$SOURCE_WORKTREE" \
  --manifest \
  "$MANIFEST" \
  --role \
  "$ROLE" \
  --round-trip

validate_rc=$?

if [ "$validate_rc" -ne 0 ]; then
  echo "STOP: candidate build validation failed."
  exit "$validate_rc"
fi

mkdir -p \
  "$OUTPUT_ROOT"

TS_VERSION_OVERRIDE="$PACKAGE_VERSION" \
  bash \
  "$BUILD_ENTRYPOINT" \
  "$OUTPUT_ROOT"

build_rc=$?

printf 'Candidate build status: %s\n' "$build_rc"

if [ "$build_rc" -ne 0 ]; then
  echo "STOP: candidate build failed."
  exit "$build_rc"
fi

printf '\n=== Static candidate SPK inspection ===\n'

if ! release_inspect_candidate_artifacts \
  "$MANIFEST" \
  "$CONTROL_WORKTREE" \
  "$OUTPUT_ROOT" \
  "$SPK_INSPECTOR"; then
  release_fail "candidate SPK inspection failed"
  exit 1
fi

spk_files=("${RELEASE_CANDIDATE_ARTIFACTS[@]}")

CHECKSUM_FILE="${OUTPUT_ROOT}/candidate-SHA256SUMS"

(
  cd \
    "$OUTPUT_ROOT" &&
    sha256sum \
      "${spk_files[@]#"$OUTPUT_ROOT"/}"
) > "$CHECKSUM_FILE"

python3 \
  - \
  "$MANIFEST" \
  "$SOURCE_WORKTREE" \
  "$OUTPUT_ROOT" \
  "$CHECKSUM_FILE" << 'PY'
import json
import sys
from datetime import datetime, timezone
from pathlib import Path
import subprocess

manifest_path = Path(sys.argv[1])
source = Path(sys.argv[2])
output = Path(sys.argv[3])
checksums = Path(sys.argv[4])

manifest = json.loads(manifest_path.read_text(encoding="utf-8"))

metadata = {
    "schema_version": 1,
    "created_at_utc": datetime.now(timezone.utc).isoformat(),
    "source_commit": subprocess.check_output(
        ["git", "-C", str(source), "rev-parse", "HEAD"],
        text=True,
    ).strip(),
    "source_tree": subprocess.check_output(
        ["git", "-C", str(source), "rev-parse", "HEAD^{tree}"],
        text=True,
    ).strip(),
    "pinned_go_version": subprocess.check_output(
        [str(source / "tool/go"), "version"],
        text=True,
    ).strip(),
    "package": manifest["package"],
    "checksums_file": checksums.name,
}

(output / "candidate-build-metadata.json").write_text(
    json.dumps(metadata, indent=2, sort_keys=True) + "\n",
    encoding="utf-8",
)
PY

release_pass "candidate build completed and checksums were recorded."
release_notice "no package was installed, published or transferred to DSM."
