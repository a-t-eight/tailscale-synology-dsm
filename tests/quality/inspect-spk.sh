#!/usr/bin/env bash
set -u

REPO_ROOT="$(
  cd \
    "$(dirname "${BASH_SOURCE[0]}")/../.." &&
    pwd
)"

INSPECTOR="${REPO_ROOT}/scripts/release/inspect-spk.sh"
MANIFEST="${REPO_ROOT}/release/manifest.yaml"

TEMP_ROOT=""
FAILURES=0

fail_check() {
  printf 'FAIL: %s\n' "$1"
  FAILURES=$((FAILURES + 1))
}

pass_check() {
  printf 'PASS: %s\n' "$1"
}

cleanup() {
  if [ -n "$TEMP_ROOT" ] &&
    [ -d "$TEMP_ROOT" ]; then
    rm -rf -- "$TEMP_ROOT"
  fi
}

trap cleanup EXIT

if [ ! -x "$INSPECTOR" ]; then
  fail_check "SPK inspector is unavailable: ${INSPECTOR}"
fi

if [ ! -s "$MANIFEST" ]; then
  fail_check "release manifest is unavailable: ${MANIFEST}"
fi

if ! command -v python3 > /dev/null 2>&1; then
  fail_check "python3 is unavailable"
fi

if [ "$FAILURES" -ne 0 ]; then
  echo "STOP: SPK inspector tests did not begin."
  exit 1
fi

TEMP_ROOT="$(
  mktemp -d "${TMPDIR:-/tmp}/tailscale-inspect-spk-tests.XXXXXX"
)"

python3 \
  - \
  "$MANIFEST" \
  "$TEMP_ROOT" << 'PY'
from __future__ import annotations

import hashlib
import io
import json
import sys
import tarfile
from pathlib import Path

manifest = json.loads(Path(sys.argv[1]).read_text(encoding="utf-8"))
root = Path(sys.argv[2])

info_values = {
    "package": manifest["package"]["identifier"],
    "version": manifest["package"]["full_version"],
    "arch": manifest["package"]["architecture"],
    "os_min_ver": manifest["synology"]["minimum_dsm"],
}

payload_files = {
    "bin/tailscale": (0o755, b"synthetic tailscale\n"),
    "bin/tailscale-synology-bootstrap": (
        0o755,
        b"#!/bin/bash\nexit 0\n",
    ),
    "bin/tailscaled": (0o755, b"synthetic tailscaled\n"),
}

outer_root_files = {
    "conf/PKG_DEPS": (0o644, b"[iptables-netfilter-extensions]\n"),
    "conf/privilege.bootstrap-package": (
        0o644,
        b'{"defaults":{"run-as":"package"}}\n',
    ),
    "conf/privilege.bootstrap-root": (
        0o644,
        b'{"defaults":{"run-as":"root"}}\n',
    ),
    "conf/resource": (0o600, b'{"usr-local-linker": {}}\n'),
    "scripts/postupgrade": (0o755, b"#!/bin/bash\nexit 0\n"),
    "scripts/preupgrade": (0o755, b"#!/bin/bash\nexit 0\n"),
    "scripts/start-stop-status": (0o755, b"#!/bin/bash\nexit 0\n"),
    "scripts/tailscale-netfilter-reconciler": (
        0o755,
        b"#!/bin/bash\nexit 0\n",
    ),
    "scripts/tailscale-synology-bootstrap": (
        0o755,
        b"#!/bin/bash\nexit 0\n",
    ),
}


def add_bytes(
    archive: tarfile.TarFile,
    name: str,
    data: bytes,
    mode: int = 0o644,
) -> None:
    member = tarfile.TarInfo(name=name)
    member.size = len(data)
    member.mode = mode
    archive.addfile(member, io.BytesIO(data))


def package_payload(
    *,
    unsafe: bool = False,
    missing: str | None = None,
    extra: bool = False,
) -> bytes:
    buffer = io.BytesIO()

    with tarfile.open(fileobj=buffer, mode="w:gz") as archive:
        if unsafe:
            add_bytes(archive, "../escape", b"unsafe\n", 0o755)
        else:
            for name, (mode, data) in payload_files.items():
                if name != missing:
                    add_bytes(archive, name, data, mode)
            if extra:
                add_bytes(archive, "bin/unmanifested", b"extra\n", 0o755)

    return buffer.getvalue()


def root_payload_manifest(variant: str = "valid") -> bytes:
    rows: list[tuple[str, int, str]] = []

    for name, (mode, data) in outer_root_files.items():
        if name != "conf/resource":
            rows.append((name, mode, hashlib.sha256(data).hexdigest()))

    for name, (mode, data) in payload_files.items():
        rows.append((f"target/{name}", mode, hashlib.sha256(data).hexdigest()))

    rows.sort(key=lambda row: row[0])
    header = "tailscale-synology-root-payload-v1"

    if variant == "malformed-header":
        header = "tailscale-synology-root-payload-v0"
    elif variant == "duplicate":
        rows.insert(1, rows[0])
    elif variant == "traversal":
        rows[0] = ("../escape", rows[0][1], rows[0][2])
    elif variant == "hash-mismatch":
        path, mode, _ = rows[-1]
        rows[-1] = (path, mode, "0" * 64)
    elif variant == "mode-mismatch":
        index = next(
            index
            for index, row in enumerate(rows)
            if row[0] == "target/bin/tailscale"
        )
        path, _, digest = rows[index]
        rows[index] = (path, 0o644, digest)

    lines = [header]
    lines.extend(
        f"file {mode:04o} {digest} {path}"
        for path, mode, digest in rows
    )
    return ("\n".join(lines) + "\n").encode("ascii")


def info_text(version: str | None = None) -> bytes:
    values = dict(info_values)
    if version is not None:
        values["version"] = version

    return (
        "\n".join(
            [
                f'package="{values["package"]}"',
                f'version="{values["version"]}"',
                f'arch="{values["arch"]}"',
                f'os_min_ver="{values["os_min_ver"]}"',
                'displayname="Synthetic Tailscale fixture"',
                'description="Static inspector test fixture"',
            ]
        )
        + "\n"
    ).encode()


def write_spk(
    name: str,
    *,
    outer_traversal: bool = False,
    duplicate_info: bool = False,
    version: str | None = None,
    unsafe_inner: bool = False,
    invalid_json: bool = False,
    invalid_script: bool = False,
    manifest_variant: str = "valid",
    missing_manifest: bool = False,
    missing_payload: str | None = None,
    extra_target: bool = False,
) -> None:
    target = root / name

    with tarfile.open(target, mode="w") as archive:
        add_bytes(archive, "INFO", info_text(version))
        if duplicate_info:
            add_bytes(archive, "./INFO", info_text(version))

        add_bytes(
            archive,
            "package.tgz",
            package_payload(
                unsafe=unsafe_inner,
                missing=missing_payload,
                extra=extra_target,
            ),
        )

        for path, (mode, data) in outer_root_files.items():
            if invalid_script and path == "scripts/start-stop-status":
                data = b"#!/bin/sh\nif then\n"
            add_bytes(archive, path, data, mode)

        privilege = (
            b"{invalid json\n"
            if invalid_json
            else b'{"defaults":{"run-as":"package"}}\n'
        )
        add_bytes(archive, "conf/privilege", privilege)

        if not missing_manifest:
            add_bytes(
                archive,
                "conf/root-payload.manifest",
                root_payload_manifest(manifest_variant),
            )

        if outer_traversal:
            add_bytes(archive, "../escape", b"unsafe\n")


write_spk("valid.spk")
write_spk("outer-traversal.spk", outer_traversal=True)
write_spk("duplicate-member.spk", duplicate_info=True)
write_spk("info-mismatch.spk", version="0.0.0-0")
write_spk("inner-traversal.spk", unsafe_inner=True)
write_spk("invalid-json.spk", invalid_json=True)
write_spk("invalid-script.spk", invalid_script=True)
write_spk("missing-manifest.spk", missing_manifest=True)
write_spk("malformed-manifest.spk", manifest_variant="malformed-header")
write_spk("duplicate-record.spk", manifest_variant="duplicate")
write_spk("manifest-traversal.spk", manifest_variant="traversal")
write_spk("hash-mismatch.spk", manifest_variant="hash-mismatch")
write_spk("mode-mismatch.spk", manifest_variant="mode-mismatch")
write_spk("missing-covered-file.spk", missing_payload="bin/tailscaled")
write_spk("extra-target-file.spk", extra_target=True)
PY

FIXTURE_RC=$?
printf 'Fixture generation status: %s\n' "$FIXTURE_RC"

if [ "$FIXTURE_RC" -ne 0 ]; then
  echo "STOP: synthetic SPK fixtures could not be generated."
  exit "$FIXTURE_RC"
fi

python3 \
  - \
  "$MANIFEST" \
  "$TEMP_ROOT" << 'PY'
from __future__ import annotations

import copy
import hashlib
import io
import json
import sys
import tarfile
from pathlib import Path

manifest = json.loads(Path(sys.argv[1]).read_text(encoding="utf-8"))
root = Path(sys.argv[2])
fixture_root = root / "artifact-role-fixtures"
manifest_root = root / "artifact-role-manifests"
manifest_root.mkdir()


def sha256(path: Path) -> str:
    digest = hashlib.sha256()
    with path.open("rb") as handle:
        for chunk in iter(lambda: handle.read(1024 * 1024), b""):
            digest.update(chunk)
    return digest.hexdigest()


def clone_spk(source: Path, target: Path, *, version: str | None = None, extra: bool = False) -> None:
    target.parent.mkdir(parents=True, exist_ok=True)
    with tarfile.open(source, mode="r:*") as original, tarfile.open(target, mode="w") as copied:
        for member in original.getmembers():
            output = copy.copy(member)
            if member.name == "INFO" and version is not None:
                extracted = original.extractfile(member)
                if extracted is None:
                    raise SystemExit("synthetic INFO could not be read")
                data = extracted.read().decode("utf-8")
                data = data.replace(
                    f'version="{manifest["package"]["full_version"]}"',
                    f'version="{version}"',
                ).encode("utf-8")
                output.size = len(data)
                copied.addfile(output, io.BytesIO(data))
            elif member.isfile():
                extracted = original.extractfile(member)
                if extracted is None:
                    raise SystemExit(f"synthetic member could not be read: {member.name}")
                copied.addfile(output, extracted)
            else:
                copied.addfile(output)
        if extra:
            output = tarfile.TarInfo("README")
            data = b"synthetic harmless outer member\n"
            output.size = len(data)
            output.mode = 0o644
            copied.addfile(output, io.BytesIO(data))


def write_manifest(name: str, sideload_digest: str, package_center: dict[str, str] | None = None) -> None:
    candidate = copy.deepcopy(manifest)
    candidate["package"]["sha256"] = sideload_digest
    candidate["package"]["artifacts"]["sideload"] = {
        "filename": candidate["package"]["filename"],
        "sha256": sideload_digest,
    }
    if package_center is not None:
        candidate["package"]["artifacts"]["package_center_reference"] = package_center
    (manifest_root / f"{name}.json").write_text(
        json.dumps(candidate, indent=2) + "\n",
        encoding="utf-8",
    )


sideload_name = manifest["package"]["filename"]
sideload = fixture_root / "sideload" / sideload_name
clone_spk(root / "valid.spk", sideload)
sideload_digest = sha256(sideload)
write_manifest("sideload", sideload_digest)

for legacy_label in (
    "outer-traversal",
    "duplicate-member",
    "info-mismatch",
    "inner-traversal",
    "invalid-json",
    "invalid-script",
    "missing-manifest",
    "malformed-manifest",
    "duplicate-record",
    "manifest-traversal",
    "hash-mismatch",
    "mode-mismatch",
    "missing-covered-file",
    "extra-target-file",
):
    legacy_spk = fixture_root / "legacy" / legacy_label / sideload_name
    clone_spk(root / f"{legacy_label}.spk", legacy_spk)
    write_manifest(f"legacy-{legacy_label}", sha256(legacy_spk))

wrong_basename = fixture_root / "wrong-basename" / "wrong-name.spk"
clone_spk(root / "valid.spk", wrong_basename)
write_manifest("wrong-basename", sha256(wrong_basename))

wrong_digest = fixture_root / "wrong-digest" / sideload_name
clone_spk(root / "valid.spk", wrong_digest, extra=True)
write_manifest("wrong-digest", sideload_digest)

package_center = {
    "filename": "tailscale-x86_64-1.98.96-720098098-dsm7-2.spk",
    "sha256": "",
    "build_number": "720098098",
    "full_version": "1.98.96-720098098",
}
package_center_spk = fixture_root / "package-center" / package_center["filename"]
clone_spk(root / "valid.spk", package_center_spk, version=package_center["full_version"])
package_center["sha256"] = sha256(package_center_spk)
write_manifest("package-center", sideload_digest, package_center)

missing_metadata = copy.deepcopy(package_center)
del missing_metadata["full_version"]
write_manifest("package-center-missing", sideload_digest, missing_metadata)

malformed_metadata = copy.deepcopy(package_center)
malformed_metadata["build_number"] = "not-a-build"
write_manifest("package-center-malformed", sideload_digest, malformed_metadata)
PY

ROLE_FIXTURE_RC=$?
printf 'Artifact-role fixture generation status: %s\n' "$ROLE_FIXTURE_RC"

if [ "$ROLE_FIXTURE_RC" -ne 0 ]; then
  echo "STOP: artifact-role fixtures could not be generated."
  exit "$ROLE_FIXTURE_RC"
fi

expect_pass() {
  label="$1"
  fixture="$2"
  fixture_manifest="${3:-$MANIFEST}"
  log="${TEMP_ROOT}/${label}.log"

  if bash \
    "$INSPECTOR" \
    --control-worktree "$REPO_ROOT" \
    --manifest "$fixture_manifest" \
    --spk "$fixture" \
    > "$log" \
    2>&1; then
    pass_check "${label} fixture passed."
  else
    printf 'Inspector output for %s:\n' "$label"
    sed -n '1,240p' "$log"
    fail_check "${label} fixture unexpectedly failed"
  fi
}

expect_legacy_fail() {
  label="$1"
  fixture="$2"
  fixture_manifest="$3"
  expected="$4"
  log="${TEMP_ROOT}/${label}.log"

  if bash \
    "$INSPECTOR" \
    --control-worktree "$REPO_ROOT" \
    --manifest "$fixture_manifest" \
    --spk "$fixture" \
    > "$log" \
    2>&1; then
    printf 'Inspector output for %s:\n' "$label"
    sed -n '1,240p' "$log"
    fail_check "${label} fixture unexpectedly passed"
  elif grep -Eq 'SPK basename|SPK SHA-256|artifact (filename|sha256|build_number|full_version)' "$log"; then
    printf 'Inspector output for %s:\n' "$label"
    sed -n '1,240p' "$log"
    fail_check "${label} fixture was rejected before archive inspection"
  elif grep -Fq "$expected" "$log"; then
    pass_check "${label} fixture was rejected for its archive defect."
  else
    printf 'Inspector output for %s:\n' "$label"
    sed -n '1,240p' "$log"
    fail_check "${label} fixture did not report its expected archive defect"
  fi
}

printf '=== Static SPK inspector synthetic tests ===\n'

expect_pass \
  valid \
  "$TEMP_ROOT/artifact-role-fixtures/sideload/tailscale-x86_64-1.98.96-700098098-dsm7.spk" \
  "$TEMP_ROOT/artifact-role-manifests/sideload.json"

for label in \
  outer-traversal \
  duplicate-member \
  info-mismatch \
  inner-traversal \
  invalid-json \
  invalid-script \
  missing-manifest \
  malformed-manifest \
  duplicate-record \
  manifest-traversal \
  hash-mismatch \
  mode-mismatch \
  missing-covered-file \
  extra-target-file; do
  case "$label" in
    outer-traversal)
      expected='SPK archive contains path traversal'
      ;;
    duplicate-member)
      expected='SPK archive contains duplicate normalised member'
      ;;
    info-mismatch)
      expected='INFO version is'
      ;;
    inner-traversal)
      expected='package.tgz contains path traversal'
      ;;
    invalid-json)
      expected='configuration JSON is invalid for conf/privilege'
      ;;
    invalid-script)
      expected='lifecycle shell syntax failed for scripts/start-stop-status'
      ;;
    missing-manifest)
      expected='SPK is missing conf/root-payload.manifest'
      ;;
    malformed-manifest)
      expected='root payload manifest header is invalid'
      ;;
    duplicate-record)
      expected='root payload manifest paths are not strictly sorted and unique'
      ;;
    manifest-traversal)
      expected='root payload manifest contains path traversal'
      ;;
    hash-mismatch)
      expected='root payload SHA-256 mismatch'
      ;;
    mode-mismatch)
      expected='root payload mode mismatch for target/bin/tailscale'
      ;;
    missing-covered-file | extra-target-file)
      expected='root payload target coverage differs'
      ;;
  esac
  expect_legacy_fail \
    "$label" \
    "$TEMP_ROOT/artifact-role-fixtures/legacy/${label}/tailscale-x86_64-1.98.96-700098098-dsm7.spk" \
    "$TEMP_ROOT/artifact-role-manifests/legacy-${label}.json" \
    "$expected"
done

expect_artifact_pass() {
  label="$1"
  fixture="$2"
  fixture_manifest="$3"
  role="${4:-}"
  log="${TEMP_ROOT}/${label}.log"

  command=(bash "$INSPECTOR" --control-worktree "$REPO_ROOT" --manifest "$fixture_manifest" --spk "$fixture")
  if [ -n "$role" ]; then
    command+=(--artifact-role "$role")
  fi

  if "${command[@]}" > "$log" 2>&1; then
    pass_check "${label} fixture passed."
  else
    printf 'Inspector output for %s:\n' "$label"
    sed -n '1,240p' "$log"
    fail_check "${label} fixture unexpectedly failed"
  fi
}

expect_artifact_fail() {
  label="$1"
  fixture="$2"
  fixture_manifest="$3"
  role="${4:-}"
  log="${TEMP_ROOT}/${label}.log"

  command=(bash "$INSPECTOR" --control-worktree "$REPO_ROOT" --manifest "$fixture_manifest" --spk "$fixture")
  if [ -n "$role" ]; then
    command+=(--artifact-role "$role")
  fi

  if "${command[@]}" > "$log" 2>&1; then
    printf 'Inspector output for %s:\n' "$label"
    sed -n '1,240p' "$log"
    fail_check "${label} fixture unexpectedly passed"
  else
    pass_check "${label} fixture was rejected."
  fi
}

expect_artifact_pass \
  default-sideload \
  "$TEMP_ROOT/artifact-role-fixtures/sideload/tailscale-x86_64-1.98.96-700098098-dsm7.spk" \
  "$TEMP_ROOT/artifact-role-manifests/sideload.json"

expect_artifact_fail \
  wrong-basename \
  "$TEMP_ROOT/artifact-role-fixtures/wrong-basename/wrong-name.spk" \
  "$TEMP_ROOT/artifact-role-manifests/wrong-basename.json"

expect_artifact_fail \
  wrong-digest \
  "$TEMP_ROOT/artifact-role-fixtures/wrong-digest/tailscale-x86_64-1.98.96-700098098-dsm7.spk" \
  "$TEMP_ROOT/artifact-role-manifests/wrong-digest.json"

expect_artifact_pass \
  package-center \
  "$TEMP_ROOT/artifact-role-fixtures/package-center/tailscale-x86_64-1.98.96-720098098-dsm7-2.spk" \
  "$TEMP_ROOT/artifact-role-manifests/package-center.json" \
  package-center-reference

for label in package-center-wrong-role package-center-missing package-center-malformed; do
  fixture_manifest="$TEMP_ROOT/artifact-role-manifests/package-center.json"
  if [ "$label" = package-center-missing ]; then
    fixture_manifest="$TEMP_ROOT/artifact-role-manifests/package-center-missing.json"
  elif [ "$label" = package-center-malformed ]; then
    fixture_manifest="$TEMP_ROOT/artifact-role-manifests/package-center-malformed.json"
  fi
  expect_artifact_fail \
    "$label" \
    "$TEMP_ROOT/artifact-role-fixtures/sideload/tailscale-x86_64-1.98.96-700098098-dsm7.spk" \
    "$fixture_manifest" \
    package-center-reference
done

printf '\nSPK inspector test failures: %s\n' "$FAILURES"

if [ "$FAILURES" -eq 0 ]; then
  echo "PASS: valid synthetic SPK passed and all malformed fixtures failed."
else
  echo "STOP: one or more static SPK inspector tests failed."
fi

exit "$FAILURES"
