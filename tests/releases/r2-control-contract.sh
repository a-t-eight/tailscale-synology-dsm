#!/usr/bin/env bash
set -u

REPO_ROOT="$(
  cd \
    "$(dirname "${BASH_SOURCE[0]}")/../.." &&
    pwd
)"
IDENTITY="${REPO_ROOT}/tests/releases/v1.98.9-r2/release-identity.json"
LEGACY_MANIFEST="${REPO_ROOT}/tests/releases/v1.98.9-r2/manifest.json"

# shellcheck source=scripts/release/common.sh
. "${REPO_ROOT}/scripts/release/common.sh"

if [ -e "$LEGACY_MANIFEST" ]; then
  echo "FAIL: duplicated full r2 manifest must not be retained" >&2
  exit 1
fi

python3 \
  - \
  "$IDENTITY" << 'PY' || exit 1
import json
import re
import sys
from pathlib import Path

path = Path(sys.argv[1])
if not path.is_file():
    raise SystemExit("FAIL: privacy-safe r2 release identity snapshot is absent")

identity = json.loads(path.read_text(encoding="utf-8"))
allowed_top_level = {
    "schema_version",
    "historical_release",
    "package",
    "patch_series",
    "evidence",
    "safety",
}
if set(identity) != allowed_top_level:
    raise SystemExit("FAIL: r2 release identity snapshot exposes unapproved fields")

expected = {
    "historical_release.revision": "r2",
    "historical_release.upstream_tag": "v1.98.9",
    "historical_release.upstream_commit": "6c167d40fa37aeb51afa7ff336730670ea4762bf",
    "historical_release.release_commit": "0fad8b81a3e0eb86c457bc79c474bcc213834c43",
    "historical_release.release_tree": "33f5c5927ae4db54b9d582650ed31cc6a2eb7161",
    "historical_release.release_branch": "release/v1.98.9-r2-synology",
    "historical_release.release_tag": "release/synology-v1.98.96-r2",
    "historical_release.release_record": "docs/releases/v1.98.96-r2/README.md",
    "package.build_number": "700098097",
    "package.full_version": "1.98.96-700098097",
    "package.filename": "tailscale-x86_64-1.98.96-700098097-dsm7.spk",
    "package.sha256": "f947a1747521c50edf49baf597cc18b512b3bb009c3b7afe963fa326ef2d6c16",
    "patch_series.path": "patches/v1.98.9-r2",
    "patch_series.format": "mail",
    "patch_series.patch_count": 58,
    "evidence.path": "tests/releases/v1.98.9-r2",
}

def get(expression):
    value = identity
    for part in expression.split("."):
        if not isinstance(value, dict) or part not in value:
            return "<absent>"
        value = value[part]
    return value

failures = [
    f"{expression}: got={get(expression)!r} want={want!r}"
    for expression, want in expected.items()
    if get(expression) != want
]
for field, value in identity["safety"].items():
    if value is not False:
        failures.append(f"safety.{field}: got={value!r} want=False")

encoded = path.read_text(encoding="utf-8")
for marker in (
    '"control"',
    '"validation"',
    "ssh_",
    "a-t-eight",
    "@",
    "SHA256:",
    "/home/",
):
    if marker in encoded:
        failures.append(f"privacy marker is present: {marker}")

if failures:
    print("FAIL: retained r2 release identity differs or discloses private control data")
    print("\n".join(f"  {item}" for item in failures))
    raise SystemExit(1)

print("PASS: reduced r2 release identity is complete and privacy-safe.")
PY

PATCH_ROOT="${REPO_ROOT}/$(
  python3 - "$IDENTITY" << 'PY'
import json
import sys
from pathlib import Path
print(json.loads(Path(sys.argv[1]).read_text(encoding="utf-8"))["patch_series"]["path"])
PY
)"
EVIDENCE_ROOT="${REPO_ROOT}/$(
  python3 - "$IDENTITY" << 'PY'
import json
import sys
from pathlib import Path
print(json.loads(Path(sys.argv[1]).read_text(encoding="utf-8"))["evidence"]["path"])
PY
)"
RELEASE_RECORD="${REPO_ROOT}/$(
  python3 - "$IDENTITY" << 'PY'
import json
import sys
from pathlib import Path
print(json.loads(Path(sys.argv[1]).read_text(encoding="utf-8"))["historical_release"]["release_record"])
PY
)"

actual_patch_count="$(find "$PATCH_ROOT" -maxdepth 1 -type f -name "*.patch" -printf . | wc -c)"
expected_patch_count="$(
  python3 - "$IDENTITY" << 'PY'
import json
import sys
from pathlib import Path
print(json.loads(Path(sys.argv[1]).read_text(encoding="utf-8"))["patch_series"]["patch_count"])
PY
)"
if [ "$actual_patch_count" != "$expected_patch_count" ]; then
  printf 'FAIL: retained r2 patch count differs: got=%s want=%s\n' "$actual_patch_count" "$expected_patch_count" >&2
  exit 1
fi

series_patch_count="$(grep -Ec "^[0-9]{4}-.*\.patch$" "${PATCH_ROOT}/series")"
if [ "$series_patch_count" != "$expected_patch_count" ]; then
  printf 'FAIL: retained r2 series count differs: got=%s want=%s\n' "$series_patch_count" "$expected_patch_count" >&2
  exit 1
fi

while IFS= read -r patch; do
  [ -n "$patch" ] || continue
  [ -f "${PATCH_ROOT}/${patch}" ] || {
    echo "FAIL: retained r2 series patch is absent: ${patch}" >&2
    exit 1
  }
done < "${PATCH_ROOT}/series"

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

echo "PASS: retained r2 patch inventory and evidence checksums are complete."
