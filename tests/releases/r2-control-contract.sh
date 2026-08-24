#!/usr/bin/env bash
set -u

REPO_ROOT="$(
  cd \
    "$(dirname "${BASH_SOURCE[0]}")/../.." &&
    pwd
)"
MANIFEST="${REPO_ROOT}/release/manifest.yaml"
VALIDATOR="${REPO_ROOT}/scripts/validate-repository.sh"
WORKFLOW="${REPO_ROOT}/.github/workflows/validate.yml"

# shellcheck source=scripts/release/common.sh
. "${REPO_ROOT}/scripts/release/common.sh"

release_validate_manifest "$MANIFEST" || exit 1

python3 \
  - \
  "$MANIFEST" \
  "$VALIDATOR" \
  "$WORKFLOW" << 'PY' || exit 1
import json
import re
import sys
from pathlib import Path

manifest = json.loads(Path(sys.argv[1]).read_text(encoding="utf-8"))
validator = Path(sys.argv[2]).read_text(encoding="utf-8")
workflow = Path(sys.argv[3]).read_text(encoding="utf-8")

expected = {
    "downstream.revision": "r2",
    "downstream.release_commit": "0fad8b81a3e0eb86c457bc79c474bcc213834c43",
    "downstream.release_tree": "33f5c5927ae4db54b9d582650ed31cc6a2eb7161",
    "package.build_number": "700098097",
    "package.full_version": "1.98.96-700098097",
    "package.filename": "tailscale-x86_64-1.98.96-700098097-dsm7.spk",
    "package.sha256": "f947a1747521c50edf49baf597cc18b512b3bb009c3b7afe963fa326ef2d6c16",
    "synology.minimum_dsm": "7.3-86009",
    "synology.netfilter_dependency": "iptables-netfilter-extensions >= 1.1.0-2",
    "branches.work": "work/v1.98.9-synology-r2",
    "branches.release": "release/v1.98.9-r2-synology",
    "tags.release": "release/synology-v1.98.96-r2",
    "paths.patch_series": "patches/v1.98.9-r2",
    "paths.evidence": "tests/releases/v1.98.9-r2",
    "paths.release_record": "docs/releases/v1.98.96-r2/README.md",
    "validation.patch_series_format": "mail",
}


def get(expression):
    value = manifest
    for part in expression.split("."):
        value = value[part]
    return value


failures = []
for expression, want in expected.items():
    got = get(expression)
    if got != want:
        failures.append(f"{expression}: got={got!r} want={want!r}")

for field, value in manifest["safety"].items():
    if value is not False:
        failures.append(f"safety.{field}: got={value!r} want=False")

release_commit = expected["downstream.release_commit"]
release_tree = expected["downstream.release_tree"]

validator_commit = re.search(r'^SOURCE_ENV_COMMIT="([0-9a-f]{40})"$', validator, re.MULTILINE)
validator_tree = re.search(r'^SOURCE_ENV_TREE="([0-9a-f]{40})"$', validator, re.MULTILINE)
workflow_refs = re.findall(r'^\s+ref: ([0-9a-f]{40})$', workflow, re.MULTILINE)

if validator_commit is None or validator_commit.group(1) != release_commit:
    failures.append("repository validator is not pinned to the r2 release commit")
if validator_tree is None or validator_tree.group(1) != release_tree:
    failures.append("repository validator is not pinned to the r2 release tree")
if workflow_refs != [release_commit]:
    failures.append(f"CI source checkout refs: got={workflow_refs!r} want={[release_commit]!r}")

if failures:
    print("FAIL: living r2 release contract differs")
    for failure in failures:
        print(f"  {failure}")
    raise SystemExit(1)

print("PASS: living r2 release identities match the accepted artifact.")
PY

PATCH_ROOT="${REPO_ROOT}/$(release_manifest_get "$MANIFEST" paths.patch_series)"
EVIDENCE_ROOT="${REPO_ROOT}/$(release_manifest_get "$MANIFEST" paths.evidence)"
RELEASE_RECORD="${REPO_ROOT}/$(release_manifest_get "$MANIFEST" paths.release_record)"

release_validate_patch_inventory "$MANIFEST" "$PATCH_ROOT" || exit 1

if [ ! -s "$RELEASE_RECORD" ]; then
  echo "FAIL: permanent r2 release record is absent: ${RELEASE_RECORD}" >&2
  exit 1
fi

(
  cd "$PATCH_ROOT" || exit 1
  sha256sum -c SHA256SUMS
) || exit 1

(
  cd "$EVIDENCE_ROOT" || exit 1
  sha256sum -c SHA256SUMS
) || exit 1

echo "PASS: r2 patch and evidence checksum manifests are complete."
