#!/usr/bin/env bash
set -u

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
MANIFEST_TEMPLATE="${REPO_ROOT}/release/manifest.yaml"
TEMP_ROOT="$(mktemp -d "${TMPDIR:-/tmp}/tailscale-reference-patches.XXXXXX")"

# shellcheck source=scripts/release/common.sh
. "${REPO_ROOT}/scripts/release/common.sh"

cleanup() {
  rm -rf -- "$TEMP_ROOT"
}
trap cleanup EXIT

SOURCE="${TEMP_ROOT}/source"
CONTROL="${TEMP_ROOT}/control"
mkdir -p "$SOURCE" "${CONTROL}/patches/current"

release_clean_git -C "$SOURCE" init -q
release_clean_git -C "$SOURCE" config user.name 'Reference patch contract'
release_clean_git -C "$SOURCE" config user.email 'reference-contract@localhost.invalid'
printf 'root\none\ntwo\nthree\nfour\nfive\nsix\n' > "${SOURCE}/state"
release_clean_git -C "$SOURCE" add state
release_clean_git -C "$SOURCE" commit -q -m upstream
UPSTREAM_COMMIT="$(release_clean_git -C "$SOURCE" rev-parse HEAD)"

printf 'reference\none\ntwo\nthree\nfour\nfive\nsix\n' > "${SOURCE}/state"
release_clean_git -C "$SOURCE" diff > "${CONTROL}/patches/current/reference.patch"
cp "${CONTROL}/patches/current/reference.patch" "${CONTROL}/valid-reference.patch"
printf 'reference\none\ntwo\nthree\nfour\nfive\nsix\naggregate\n' > "${SOURCE}/state"
release_clean_git -C "$SOURCE" diff > "${CONTROL}/full-apply.patch"
release_clean_git -C "$SOURCE" add state
release_clean_git -C "$SOURCE" commit -q -m accepted
ACCEPTED_TREE="$(release_clean_git -C "$SOURCE" rev-parse 'HEAD^{tree}')"

release_clean_git -C "$SOURCE" checkout -q --detach "$UPSTREAM_COMMIT"
printf 'root\none\ntwo\nthree\nfour\nfive\nsix\naggregate\n' > "${SOURCE}/state"
release_clean_git -C "$SOURCE" diff > "${CONTROL}/patches/current/apply.patch"
release_clean_git -C "$SOURCE" reset --hard -q "$UPSTREAM_COMMIT"

python3 - "$MANIFEST_TEMPLATE" "${TEMP_ROOT}/manifest.json" "$UPSTREAM_COMMIT" << 'PYTHON'
import json
import sys
from pathlib import Path

source = json.loads(Path(sys.argv[1]).read_text(encoding="utf-8"))
source["upstream"]["commit"] = sys.argv[3]
source["paths"]["patch_series"] = "patches/current"
source["validation"].pop("patch_base", None)
source["validation"]["patch_series_format"] = "raw-diff"
source["validation"]["patch_apply_files"] = ["apply.patch"]
source["validation"]["patch_reference_files"] = ["reference.patch"]
Path(sys.argv[2]).write_text(json.dumps(source), encoding="utf-8")
PYTHON
MANIFEST="${TEMP_ROOT}/manifest.json"
release_validate_manifest "$MANIFEST" || exit 1

printf 'not a patch\n' > "${CONTROL}/patches/current/reference.patch"
if release_apply_patch_layers "$SOURCE" "$MANIFEST" "$CONTROL" round-trip; then
  echo 'FAIL: invalid forward reference patch was accepted' >&2
  exit 1
fi
release_clean_git -C "$SOURCE" diff --quiet || {
  echo 'FAIL: forward reference failure modified the source worktree' >&2
  exit 1
}

release_clean_git -C "$SOURCE" reset --hard -q "$UPSTREAM_COMMIT"
cp "${CONTROL}/valid-reference.patch" "${CONTROL}/patches/current/reference.patch"
if release_apply_patch_layers "$SOURCE" "$MANIFEST" "$CONTROL" round-trip; then
  echo 'FAIL: reference patch absent from the aggregate result was accepted' >&2
  exit 1
fi

release_clean_git -C "$SOURCE" reset --hard -q "$UPSTREAM_COMMIT"
cp "${CONTROL}/full-apply.patch" "${CONTROL}/patches/current/apply.patch"
release_apply_patch_layers "$SOURCE" "$MANIFEST" "$CONTROL" round-trip || {
  echo 'FAIL: accepted unlayered raw-diff reference path was rejected' >&2
  exit 1
}
OBSERVED_TREE="$(release_clean_git -C "$SOURCE" write-tree)"
[ "$OBSERVED_TREE" = "$ACCEPTED_TREE" ] || {
  echo "FAIL: unlayered raw-diff tree differs: got=${OBSERVED_TREE} want=${ACCEPTED_TREE}" >&2
  exit 1
}

echo 'PASS: forward, reverse, and unlayered raw-diff reference checks are enforced.'
