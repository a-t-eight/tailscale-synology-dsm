#!/usr/bin/env bash
set -u

REPO_ROOT="$(
  cd \
    "$(dirname "${BASH_SOURCE[0]}")/../.." &&
    pwd
)"
MANIFEST_TEMPLATE="${REPO_ROOT}/release/manifest.yaml"
TEMP_ROOT="$(mktemp -d "${TMPDIR:-/tmp}/tailscale-patch-base-identity.XXXXXX")"

# shellcheck source=scripts/release/common.sh
. "${REPO_ROOT}/scripts/release/common.sh"

cleanup() {
  rm -rf -- "$TEMP_ROOT"
}
trap cleanup EXIT

SOURCE="${TEMP_ROOT}/source"
mkdir -p "$SOURCE"

release_clean_git -C "$SOURCE" init -q
release_clean_git -C "$SOURCE" config user.name 'Patch base contract'
release_clean_git -C "$SOURCE" config user.email 'patch-base-contract@localhost.invalid'

printf 'upstream\n' > "${SOURCE}/state"
release_clean_git -C "$SOURCE" add state
release_clean_git -C "$SOURCE" commit -q -m upstream
UPSTREAM_COMMIT="$(release_clean_git -C "$SOURCE" rev-parse HEAD)"
UPSTREAM_TREE="$(release_clean_git -C "$SOURCE" rev-parse 'HEAD^{tree}')"

printf 'base\n' > "${SOURCE}/state"
release_clean_git -C "$SOURCE" add state
release_clean_git -C "$SOURCE" commit -q -m base
BASE_COMMIT="$(release_clean_git -C "$SOURCE" rev-parse HEAD)"
BASE_TREE="$(release_clean_git -C "$SOURCE" rev-parse 'HEAD^{tree}')"

printf 'r3\n' > "${SOURCE}/state"
release_clean_git -C "$SOURCE" add state
release_clean_git -C "$SOURCE" commit -q -m r3
R3_COMMIT="$(release_clean_git -C "$SOURCE" rev-parse HEAD)"
R3_TREE="$(release_clean_git -C "$SOURCE" rev-parse 'HEAD^{tree}')"

release_clean_git -C "$SOURCE" checkout -q --detach "$UPSTREAM_COMMIT"
printf 'side\n' > "${SOURCE}/side"
release_clean_git -C "$SOURCE" add side
release_clean_git -C "$SOURCE" commit -q -m side
SIDE_COMMIT="$(release_clean_git -C "$SOURCE" rev-parse HEAD)"
SIDE_TREE="$(release_clean_git -C "$SOURCE" rev-parse 'HEAD^{tree}')"

python3 - \
  "$MANIFEST_TEMPLATE" \
  "${TEMP_ROOT}/valid.json" \
  "$UPSTREAM_COMMIT" \
  "$BASE_COMMIT" \
  "$BASE_TREE" \
  "$R3_COMMIT" \
  "$R3_TREE" << 'PYTHON'
import json
import sys
from pathlib import Path

source = json.loads(Path(sys.argv[1]).read_text(encoding="utf-8"))
target = Path(sys.argv[2])
upstream, base_commit, base_tree, r3_commit, r3_tree = sys.argv[3:]
source["upstream"]["commit"] = upstream
source["downstream"]["release_commit"] = r3_commit
source["downstream"]["release_tree"] = r3_tree
source["validation"]["patch_base"]["release_commit"] = base_commit
source["validation"]["patch_base"]["release_tree"] = base_tree
target.write_text(json.dumps(source), encoding="utf-8")
PYTHON

VALID_MANIFEST="${TEMP_ROOT}/valid.json"
release_validate_manifest "$VALID_MANIFEST" || exit 1

release_validate_patch_base_identity "$SOURCE" "$VALID_MANIFEST" || {
  echo 'FAIL: valid base commit/tree ancestry was rejected' >&2
  exit 1
}

python3 - "$VALID_MANIFEST" "${TEMP_ROOT}/wrong-commit.json" "$UPSTREAM_COMMIT" << 'PYTHON'
import json
import sys
from pathlib import Path

data = json.loads(Path(sys.argv[1]).read_text(encoding="utf-8"))
data["validation"]["patch_base"]["release_commit"] = sys.argv[3]
Path(sys.argv[2]).write_text(json.dumps(data), encoding="utf-8")
PYTHON

if release_validate_patch_base_identity "$SOURCE" "${TEMP_ROOT}/wrong-commit.json"; then
  echo 'FAIL: mismatched base commit and tree were accepted' >&2
  exit 1
fi

python3 - "$VALID_MANIFEST" "${TEMP_ROOT}/wrong-tree.json" "$UPSTREAM_TREE" << 'PYTHON'
import json
import sys
from pathlib import Path

data = json.loads(Path(sys.argv[1]).read_text(encoding="utf-8"))
data["validation"]["patch_base"]["release_tree"] = sys.argv[3]
Path(sys.argv[2]).write_text(json.dumps(data), encoding="utf-8")
PYTHON

if release_validate_patch_base_identity "$SOURCE" "${TEMP_ROOT}/wrong-tree.json"; then
  echo 'FAIL: mismatched base tree was accepted' >&2
  exit 1
fi

python3 - "$VALID_MANIFEST" "${TEMP_ROOT}/side.json" "$SIDE_COMMIT" "$SIDE_TREE" << 'PYTHON'
import json
import sys
from pathlib import Path

data = json.loads(Path(sys.argv[1]).read_text(encoding="utf-8"))
data["validation"]["patch_base"]["release_commit"] = sys.argv[3]
data["validation"]["patch_base"]["release_tree"] = sys.argv[4]
Path(sys.argv[2]).write_text(json.dumps(data), encoding="utf-8")
PYTHON

if release_validate_patch_base_identity "$SOURCE" "${TEMP_ROOT}/side.json"; then
  echo 'FAIL: non-ancestor base commit was accepted' >&2
  exit 1
fi

echo 'PASS: patch base commit/tree identity and ancestry are fail-closed.'
