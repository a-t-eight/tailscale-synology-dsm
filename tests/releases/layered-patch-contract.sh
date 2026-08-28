#!/usr/bin/env bash
set -u

REPO_ROOT="$(
  cd \
    "$(dirname "${BASH_SOURCE[0]}")/../.." &&
    pwd
)"
MANIFEST="${REPO_ROOT}/release/manifest.yaml"
TEMP_ROOT="$(mktemp -d "${TMPDIR:-/tmp}/tailscale-layered-contract.XXXXXX")"

# shellcheck source=scripts/release/common.sh
. "${REPO_ROOT}/scripts/release/common.sh"

cleanup() {
  rm -rf -- "$TEMP_ROOT"
}
trap cleanup EXIT

python3 - "$MANIFEST" "$TEMP_ROOT" << 'PY'
import json
import sys
from pathlib import Path

source = json.loads(Path(sys.argv[1]).read_text(encoding="utf-8"))
root = Path(sys.argv[2])

base = {
    "path": "patches/v1.98.9-r2",
    "patch_series_format": "mail",
    "patch_apply_files": ["0001-base.patch"],
    "patch_reference_files": [],
    "release_commit": "0fad8b81a3e0eb86c457bc79c474bcc213834c43",
    "release_tree": "33f5c5927ae4db54b9d582650ed31cc6a2eb7161",
}

for name, update in {
    "absent": None,
    "valid": base,
    "unsafe": {**base, "path": "../patches/v1.98.9-r2"},
    "mismatched": {**base, "path": source["paths"]["patch_series"]},
}.items():
    data = json.loads(json.dumps(source))
    if update is not None:
        data["validation"]["patch_base"] = update
    (root / f"{name}.json").write_text(json.dumps(data), encoding="utf-8")
PY

release_validate_manifest "${TEMP_ROOT}/absent.json" || exit 1

if release_validate_manifest "${TEMP_ROOT}/unsafe.json"; then
  echo "FAIL: unsafe layered patch path was accepted" >&2
  exit 1
fi

if release_validate_manifest "${TEMP_ROOT}/mismatched.json"; then
  echo "FAIL: layered patch path matching the current layer was accepted" >&2
  exit 1
fi

mapfile -t layers < <(
  release_manifest_patch_layers "${TEMP_ROOT}/valid.json"
)

if [ "${layers[*]}" != "base current" ]; then
  printf 'FAIL: layered patch order: got=%s want=base current\n' "${layers[*]}" >&2
  exit 1
fi

ALIAS_CONTROL="${TEMP_ROOT}/alias-control"
mkdir -p "${ALIAS_CONTROL}/patches/shared"
cp -a "${REPO_ROOT}/patches/v1.98.9-r3/." "${ALIAS_CONTROL}/patches/shared/"
ln -s shared "${ALIAS_CONTROL}/patches/base-alias"
ln -s shared "${ALIAS_CONTROL}/patches/current-alias"

python3 - "$MANIFEST" "${TEMP_ROOT}/symlink-alias.json" << 'PY'
import json
import sys
from pathlib import Path

source = json.loads(Path(sys.argv[1]).read_text(encoding="utf-8"))
source["paths"]["patch_series"] = "patches/current-alias"
source["validation"]["patch_base"]["path"] = "patches/base-alias"
source["validation"]["patch_base"]["patch_series_format"] = source["validation"]["patch_series_format"]
source["validation"]["patch_base"]["patch_apply_files"] = source["validation"]["patch_apply_files"]
source["validation"]["patch_base"]["patch_reference_files"] = source["validation"]["patch_reference_files"]
Path(sys.argv[2]).write_text(json.dumps(source), encoding="utf-8")
PY

if release_validate_patch_layers "${TEMP_ROOT}/symlink-alias.json" "$ALIAS_CONTROL"; then
  echo "FAIL: symlink-alias patch layer roots were accepted" >&2
  exit 1
fi

echo "PASS: absent, valid, unsafe, mismatched, and symlink-alias layered configurations are fail-closed."
