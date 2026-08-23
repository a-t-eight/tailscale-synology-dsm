#!/usr/bin/env bash
set -u

REPO_ROOT="$(
  cd \
    "$(dirname "${BASH_SOURCE[0]}")/../.." &&
    pwd
)"
MANIFEST="${REPO_ROOT}/release/manifest.yaml"
PATCH_ROOT="${REPO_ROOT}/patches/v1.98.9"

# shellcheck source=scripts/release/common.sh
. "${REPO_ROOT}/scripts/release/common.sh"

release_validate_manifest "$MANIFEST" || exit 1
release_validate_patch_inventory "$MANIFEST" "$PATCH_ROOT" || exit 1

mapfile -t APPLIED_PATCHES < <(
  release_patch_paths "$MANIFEST" "$PATCH_ROOT" validation.patch_apply_files
)

if [ "${#APPLIED_PATCHES[@]}" -ne 1 ] ||
  [ "$(basename "${APPLIED_PATCHES[0]}")" != "release-tree.patch" ]; then
  release_fail "accepted applied patch sequence changed while classifying the adjunct"
  exit 1
fi

(
  cd "$PATCH_ROOT" || exit 1
  sha256sum -c synology-netfilter.patch.sha256
) > /dev/null || {
  release_fail "protected canonical patch checksum failed"
  exit 1
}

release_pass "applied, reference and protected adjunct patch roles are coherent"
