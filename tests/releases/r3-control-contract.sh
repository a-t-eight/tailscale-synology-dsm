#!/usr/bin/env bash
set -u

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
MANIFEST="${REPO_ROOT}/release/manifest.yaml"
VALIDATOR="${REPO_ROOT}/scripts/validate-repository.sh"
WORKFLOW="${REPO_ROOT}/.github/workflows/validate.yml"
BUILD_CANDIDATE_ROLE_CONTRACT="${REPO_ROOT}/tests/releases/build-candidate-role-contract.sh"
EVIDENCE_MANIFEST="${REPO_ROOT}/tests/releases/v1.98.9-r3/reproducible-build/manifest.json"

# shellcheck source=scripts/release/common.sh
. "${REPO_ROOT}/scripts/release/common.sh"

release_validate_manifest "$MANIFEST" || exit 1

python3 - "$MANIFEST" "$VALIDATOR" "$WORKFLOW" "$BUILD_CANDIDATE_ROLE_CONTRACT" "$EVIDENCE_MANIFEST" << 'PY' || exit 1
import json
import re
import sys
from pathlib import Path

manifest = json.loads(Path(sys.argv[1]).read_text(encoding="utf-8"))
validator = Path(sys.argv[2]).read_text(encoding="utf-8")
workflow = Path(sys.argv[3]).read_text(encoding="utf-8")
build_candidate_role_contract = Path(sys.argv[4])
evidence = json.loads(Path(sys.argv[5]).read_text(encoding="utf-8"))

expected = {
    "downstream.revision": "r3",
    "downstream.release_commit": "f49613eccf9350583cc328183f192a591cd76348",
    "downstream.release_tree": "44c0bc3cd3bbcd3eb70cacf34e9611909a38bd10",
    "package.full_version": "1.98.96-700098098",
    "package.filename": "tailscale-x86_64-1.98.96-700098098-dsm7.spk",
    "package.sha256": "a8323d98c318c210ce9c3c467ae6ece9a3bf3e13735ee77efc1b855820ddc41d",
    "package.artifacts.package_center_reference.filename": "tailscale-x86_64-1.98.96-720098098-dsm7-2.spk",
    "package.artifacts.package_center_reference.sha256": "9f507a8336471fe9990e94f7c23276ad5cb40c477d6f2a3763faa4d3f32b818c",
    "package.artifacts.package_center_reference.build_number": "720098098",
    "package.artifacts.package_center_reference.full_version": "1.98.96-720098098",
    "branches.release": "release/v1.98.9-r3-synology",
    "tags.release": "release/synology-v1.98.96-r3",
    "paths.patch_series": "patches/v1.98.9-r3",
    "paths.evidence": "tests/releases/v1.98.9-r3",
    "paths.release_record": "docs/releases/v1.98.96-r3/README.md",
    "validation.patch_base.path": "patches/v1.98.9-r2",
    "validation.patch_base.release_commit": "0fad8b81a3e0eb86c457bc79c474bcc213834c43",
    "validation.patch_base.release_tree": "33f5c5927ae4db54b9d582650ed31cc6a2eb7161",
}

def get(path):
    value = manifest
    for part in path.split("."):
        if not isinstance(value, dict) or part not in value:
            return "<absent>"
        value = value[part]
    return value

failures = [f"{path}: got={get(path)!r} want={want!r}" for path, want in expected.items() if get(path) != want]
if len(manifest["validation"]["patch_base"]["patch_apply_files"]) != 58:
    failures.append("r2 base patch count differs")
if len(manifest["validation"]["patch_apply_files"]) != 7:
    failures.append("r3 delta patch count differs")
if any(value is not False for value in manifest["safety"].values()):
    failures.append("a release safety policy is enabled")

commit = expected["downstream.release_commit"]
tree = expected["downstream.release_tree"]
if re.search(r'^SOURCE_ENV_COMMIT="([0-9a-f]{40})"$', validator, re.M).group(1) != commit:
    failures.append("validator source commit is not r3")
if re.search(r'^SOURCE_ENV_TREE="([0-9a-f]{40})"$', validator, re.M).group(1) != tree:
    failures.append("validator source tree is not r3")
if re.findall(r'^\s+ref: ([0-9a-f]{40})$', workflow, re.M) != [commit]:
    failures.append("workflow source ref is not r3")
required_contracts = (
    "tests/releases/patch-base-identity-contract.sh",
    "tests/releases/layered-patch-contract.sh",
    "tests/releases/reference-patch-contract.sh",
    "tests/releases/temporary-git-isolation-contract.sh",
    "tests/releases/r2-control-contract.sh",
    "tests/releases/r3-control-contract.sh",
    "tests/releases/build-candidate-role-contract.sh",
)
for contract in required_contracts:
    if contract not in validator:
        failures.append(f"canonical validator does not invoke {contract}")
if not build_candidate_role_contract.is_file():
    failures.append("build candidate role contract is absent")
expected_evidence = {
    "original_payload_inspection_commit": "932c74d40db66304c04908cd0e287cdb5a357e36",
    "canonical_role_validation_head": "b9c9582acd1fdb6c02d0593610837e475da9b773",
}
if "static_inspection_commit" in evidence:
    failures.append("evidence retains the ambiguous static_inspection_commit name")
for field, value in expected_evidence.items():
    if evidence.get(field) != value:
        failures.append(f"evidence {field} differs")
if failures:
    print("FAIL: living r3 release contract differs")
    print("\n".join(f"  {item}" for item in failures))
    raise SystemExit(1)
PY

mapfile -t layers < <(release_manifest_patch_layers "$MANIFEST")
[ "${layers[*]}" = "base current" ] || {
  echo "FAIL: r3 patch layers are unordered" >&2
  exit 1
}
release_validate_patch_layers "$MANIFEST" "$REPO_ROOT" || exit 1

for layer in "${layers[@]}"; do
  root="$(release_patch_layer_root "$MANIFEST" "$REPO_ROOT" "$layer")" || exit 1
  (cd "$root" && sha256sum -c SHA256SUMS) || exit 1
done

EVIDENCE_ROOT="${REPO_ROOT}/$(release_manifest_get "$MANIFEST" paths.evidence)"
RELEASE_RECORD="${REPO_ROOT}/$(release_manifest_get "$MANIFEST" paths.release_record)"
[ -s "$RELEASE_RECORD" ] || {
  echo "FAIL: r3 release record is absent" >&2
  exit 1
}
(cd "$EVIDENCE_ROOT" && sha256sum -c SHA256SUMS) || exit 1

echo "PASS: living r3 identity, layered patches, evidence, and safety policy are complete."
