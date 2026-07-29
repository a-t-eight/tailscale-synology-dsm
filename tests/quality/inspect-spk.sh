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
    rm \
      -rf \
      -- \
      "$TEMP_ROOT"
  fi
}

trap cleanup EXIT

if [ ! -x "$INSPECTOR" ]; then
  fail_check "SPK inspector is unavailable: ${INSPECTOR}"
fi

if [ ! -s "$MANIFEST" ]; then
  fail_check "release manifest is unavailable: ${MANIFEST}"
fi

if ! command \
  -v \
  python3 \
  > /dev/null \
  2>&1; then
  fail_check "python3 is unavailable"
fi

if [ "$FAILURES" -ne 0 ]; then
  echo "STOP: SPK inspector tests did not begin."
  exit 1
fi

TEMP_ROOT="$(
  mktemp \
    -d \
    "${TMPDIR:-/tmp}/tailscale-inspect-spk-tests.XXXXXX"
)"

python3 \
  - \
  "$MANIFEST" \
  "$TEMP_ROOT" << 'PY'
from __future__ import annotations

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


def package_payload(unsafe: bool = False) -> bytes:
    buffer = io.BytesIO()

    with tarfile.open(fileobj=buffer, mode="w:gz") as archive:
        name = "../escape" if unsafe else "bin/tailscale"
        add_bytes(archive, name, b"synthetic payload\n", 0o755)

    return buffer.getvalue()


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
) -> None:
    target = root / name

    with tarfile.open(target, mode="w") as archive:
        add_bytes(archive, "INFO", info_text(version))

        if duplicate_info:
            add_bytes(archive, "./INFO", info_text(version))

        add_bytes(
            archive,
            "package.tgz",
            package_payload(unsafe_inner),
        )

        script = (
            b"#!/bin/sh\nif then\n"
            if invalid_script
            else b"#!/bin/sh\nexit 0\n"
        )
        add_bytes(
            archive,
            "scripts/start-stop-status",
            script,
            0o755,
        )

        privilege = (
            b"{invalid json\n"
            if invalid_json
            else b'{"defaults":{"run-as":"package"}}\n'
        )
        add_bytes(
            archive,
            "conf/privilege",
            privilege,
        )
        add_bytes(
            archive,
            "conf/resource",
            b'{"usr-local-linker": {}}\n',
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
PY

FIXTURE_RC=$?
printf 'Fixture generation status: %s\n' "$FIXTURE_RC"

if [ "$FIXTURE_RC" -ne 0 ]; then
  echo "STOP: synthetic SPK fixtures could not be generated."
  exit "$FIXTURE_RC"
fi

expect_pass() {
  label="$1"
  fixture="$2"
  log="${TEMP_ROOT}/${label}.log"

  if bash \
    "$INSPECTOR" \
    --control-worktree \
    "$REPO_ROOT" \
    --manifest \
    "$MANIFEST" \
    --spk \
    "$fixture" \
    > "$log" \
    2>&1; then
    pass_check "${label} fixture passed."
  else
    printf 'Inspector output for %s:\n' "$label"
    sed \
      -n \
      '1,240p' \
      "$log"
    fail_check "${label} fixture unexpectedly failed"
  fi
}

expect_fail() {
  label="$1"
  fixture="$2"
  log="${TEMP_ROOT}/${label}.log"

  if bash \
    "$INSPECTOR" \
    --control-worktree \
    "$REPO_ROOT" \
    --manifest \
    "$MANIFEST" \
    --spk \
    "$fixture" \
    > "$log" \
    2>&1; then
    printf 'Inspector output for %s:\n' "$label"
    sed \
      -n \
      '1,240p' \
      "$log"
    fail_check "${label} fixture unexpectedly passed"
  else
    pass_check "${label} fixture was rejected."
  fi
}

printf '=== Static SPK inspector synthetic tests ===\n'

expect_pass \
  valid \
  "$TEMP_ROOT/valid.spk"

expect_fail \
  outer-traversal \
  "$TEMP_ROOT/outer-traversal.spk"

expect_fail \
  duplicate-member \
  "$TEMP_ROOT/duplicate-member.spk"

expect_fail \
  info-mismatch \
  "$TEMP_ROOT/info-mismatch.spk"

expect_fail \
  inner-traversal \
  "$TEMP_ROOT/inner-traversal.spk"

expect_fail \
  invalid-json \
  "$TEMP_ROOT/invalid-json.spk"

expect_fail \
  invalid-script \
  "$TEMP_ROOT/invalid-script.spk"

printf '\nSPK inspector test failures: %s\n' "$FAILURES"

if [ "$FAILURES" -eq 0 ]; then
  echo "PASS: valid synthetic SPK passed and all malformed fixtures failed."
else
  echo "STOP: one or more static SPK inspector tests failed."
fi

exit "$FAILURES"
