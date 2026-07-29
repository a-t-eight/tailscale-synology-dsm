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

MANIFEST=""
SPK=""

usage() {
  cat << 'USAGE'
Usage:
  bash scripts/release/inspect-spk.sh \
    --spk /path/to/package.spk \
    [--control-worktree /path/to/control-worktree] \
    [--manifest /path/to/release/manifest.yaml]

The inspector is static and non-installing. It does not source INFO, execute
package lifecycle scripts, invoke DSM tools or extract package content onto
the host filesystem.
USAGE
}

while [ "$#" -gt 0 ]; do
  case "$1" in
    --control-worktree)
      if [ "$#" -lt 2 ]; then
        release_fail "--control-worktree requires a path"
        exit 2
      fi

      CONTROL_WORKTREE="$2"
      shift
      ;;
    --manifest)
      if [ "$#" -lt 2 ]; then
        release_fail "--manifest requires a path"
        exit 2
      fi

      MANIFEST="$2"
      shift
      ;;
    --spk)
      if [ "$#" -lt 2 ]; then
        release_fail "--spk requires a path"
        exit 2
      fi

      SPK="$2"
      shift
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

if [ -z "$SPK" ]; then
  release_fail "--spk is required"
  usage >&2
  exit 2
fi

if [ -z "$MANIFEST" ]; then
  MANIFEST="${CONTROL_WORKTREE}/release/manifest.yaml"
fi

release_require_command bash || exit 1
release_require_command python3 || exit 1
release_require_worktree "$CONTROL_WORKTREE" || exit 1
release_validate_manifest "$MANIFEST" || exit 1

if [ ! -f "$SPK" ] ||
  [ ! -r "$SPK" ]; then
  release_fail "SPK is unavailable or unreadable: ${SPK}"
  exit 1
fi

printf '=== Static SPK inspection ===\n'
printf 'SPK:              %s\n' "$SPK"
printf 'Control worktree: %s\n' "$CONTROL_WORKTREE"
printf 'Manifest:         %s\n' "$MANIFEST"

python3 \
  - \
  "$SPK" \
  "$MANIFEST" << 'PY'
from __future__ import annotations

import io
import json
import re
import shlex
import shutil
import subprocess
import sys
import tarfile
import tempfile
from pathlib import Path, PurePosixPath

spk_path = Path(sys.argv[1]).expanduser().resolve()
manifest_path = Path(sys.argv[2]).expanduser().resolve()
manifest = json.loads(manifest_path.read_text(encoding="utf-8"))

required_members = manifest["validation"]["spk_required_members"]
required_info_fields = manifest["validation"]["spk_required_info_fields"]

if not isinstance(required_members, list) or not required_members:
    raise SystemExit("validation.spk_required_members must be a non-empty array")

if not isinstance(required_info_fields, list) or not required_info_fields:
    raise SystemExit(
        "validation.spk_required_info_fields must be a non-empty array"
    )

expected_info = {
    "package": manifest["package"]["identifier"],
    "version": manifest["package"]["full_version"],
    "arch": manifest["package"]["architecture"],
    "os_min_ver": manifest["synology"]["minimum_dsm"],
}


def normalise_member(name: str, label: str) -> str:
    if not isinstance(name, str) or not name:
        raise SystemExit(f"{label} contains an empty member name")

    if "\x00" in name or "\\" in name:
        raise SystemExit(f"{label} contains an unsafe member name: {name!r}")

    pure = PurePosixPath(name)

    if pure.is_absolute() or ".." in pure.parts:
        raise SystemExit(f"{label} contains path traversal: {name!r}")

    parts = [part for part in pure.parts if part not in ("", ".")]

    return "/".join(parts)


def validate_link_target(
    member_name: str,
    link_name: str,
    label: str,
    hard_link: bool,
) -> None:
    if not link_name:
        raise SystemExit(f"{label} contains an empty link target: {member_name}")

    if "\\" in link_name:
        raise SystemExit(
            f"{label} contains an unsafe link target: {member_name} -> {link_name}"
        )

    link = PurePosixPath(link_name)

    if link.is_absolute():
        raise SystemExit(
            f"{label} contains an absolute link target: "
            f"{member_name} -> {link_name}"
        )

    if hard_link:
        candidate = link
    else:
        candidate = PurePosixPath(member_name).parent / link

    normalise_member(str(candidate), f"{label} link target")


def inventory_archive(
    handle: tarfile.TarFile,
    label: str,
    allow_links: bool,
    maximum_members: int,
    maximum_regular_bytes: int,
) -> dict[str, tarfile.TarInfo]:
    inventory: dict[str, tarfile.TarInfo] = {}
    regular_bytes = 0

    members = handle.getmembers()

    if len(members) > maximum_members:
        raise SystemExit(
            f"{label} contains {len(members)} members, limit {maximum_members}"
        )

    for member in members:
        name = normalise_member(member.name, label)

        if not name:
            continue

        if name in inventory:
            raise SystemExit(
                f"{label} contains duplicate normalised member: {name}"
            )

        if member.ischr() or member.isblk() or member.isfifo():
            raise SystemExit(
                f"{label} contains a device or FIFO member: {member.name}"
            )

        if member.isfile():
            regular_bytes += member.size

            if regular_bytes > maximum_regular_bytes:
                raise SystemExit(
                    f"{label} regular-file size exceeds "
                    f"{maximum_regular_bytes} bytes"
                )

        if member.issym() or member.islnk():
            if not allow_links:
                raise SystemExit(
                    f"{label} contains a link member: {member.name}"
                )

            validate_link_target(
                name,
                member.linkname,
                label,
                member.islnk(),
            )

        inventory[name] = member

    return inventory


def read_member(
    handle: tarfile.TarFile,
    member: tarfile.TarInfo,
    label: str,
    maximum: int,
) -> bytes:
    if not member.isfile():
        raise SystemExit(f"{label} is not a regular file")

    if member.size < 0 or member.size > maximum:
        raise SystemExit(
            f"{label} size {member.size} exceeds the limit {maximum}"
        )

    extracted = handle.extractfile(member)

    if extracted is None:
        raise SystemExit(f"{label} could not be read")

    data = extracted.read(maximum + 1)

    if len(data) > maximum:
        raise SystemExit(f"{label} exceeds the read limit")

    return data


def parse_info(data: bytes) -> dict[str, str]:
    try:
        text = data.decode("utf-8")
    except UnicodeDecodeError as error:
        raise SystemExit(f"INFO is not valid UTF-8: {error}") from error

    values: dict[str, str] = {}

    for number, raw_line in enumerate(text.splitlines(), start=1):
        line = raw_line.strip()

        if not line or line.startswith("#"):
            continue

        match = re.fullmatch(
            r"([A-Za-z_][A-Za-z0-9_]*)=(.*)",
            line,
        )

        if not match:
            continue

        key = match.group(1)
        raw_value = match.group(2).strip()

        if "$(" in raw_value or "`" in raw_value or "${" in raw_value:
            if key in required_info_fields:
                raise SystemExit(
                    f"INFO field {key} uses dynamic shell expansion"
                )
            continue

        lexer = shlex.shlex(raw_value, posix=True)
        lexer.whitespace_split = True
        lexer.commenters = ""

        try:
            tokens = list(lexer)
        except ValueError as error:
            raise SystemExit(
                f"INFO field {key} has invalid quoting on line {number}: {error}"
            ) from error

        if len(tokens) != 1:
            if key in required_info_fields:
                raise SystemExit(
                    f"INFO field {key} is not one static value"
                )
            continue

        if key in values:
            raise SystemExit(f"INFO contains duplicate field {key}")

        values[key] = tokens[0]

    return values


with tarfile.open(spk_path, mode="r:*") as outer:
    outer_inventory = inventory_archive(
        outer,
        "SPK archive",
        allow_links=False,
        maximum_members=10_000,
        maximum_regular_bytes=4 * 1024 * 1024 * 1024,
    )

    missing = sorted(
        member
        for member in required_members
        if member not in outer_inventory
    )

    if missing:
        raise SystemExit(
            "SPK is missing required members: " + ", ".join(missing)
        )

    info = parse_info(
        read_member(
            outer,
            outer_inventory["INFO"],
            "INFO",
            2 * 1024 * 1024,
        )
    )

    missing_info = sorted(
        field
        for field in required_info_fields
        if field not in info
    )

    if missing_info:
        raise SystemExit(
            "INFO is missing required fields: " + ", ".join(missing_info)
        )

    for field, expected in expected_info.items():
        observed = info[field]

        if field == "arch":
            observed_arches = observed.split()

            if expected not in observed_arches:
                raise SystemExit(
                    f"INFO arch {observed!r} does not include {expected!r}"
                )
        elif observed != expected:
            raise SystemExit(
                f"INFO {field} is {observed!r}, expected {expected!r}"
            )

    lifecycle_members = sorted(
        (
            name,
            member,
        )
        for name, member in outer_inventory.items()
        if name.startswith("scripts/") and member.isfile()
    )

    if not lifecycle_members:
        raise SystemExit("SPK contains no lifecycle scripts")

    with tempfile.TemporaryDirectory(
        prefix="tailscale-spk-scripts-"
    ) as temporary_scripts:
        script_root = Path(temporary_scripts)

        for index, (name, member) in enumerate(lifecycle_members):
            data = read_member(
                outer,
                member,
                name,
                4 * 1024 * 1024,
            )
            target = script_root / f"{index:03d}-{PurePosixPath(name).name}"
            target.write_bytes(data)

            result = subprocess.run(
                ["bash", "-n", str(target)],
                check=False,
                capture_output=True,
                text=True,
            )

            if result.returncode != 0:
                detail = (result.stderr or result.stdout).strip()
                raise SystemExit(
                    f"lifecycle shell syntax failed for {name}: {detail}"
                )

    json_members = sorted(
        (
            name,
            member,
        )
        for name, member in outer_inventory.items()
        if name.startswith("conf/")
        and member.isfile()
        and PurePosixPath(name).name in {"privilege", "resource"}
    )

    for name, member in json_members:
        data = read_member(
            outer,
            member,
            name,
            4 * 1024 * 1024,
        )

        try:
            json.loads(data.decode("utf-8"))
        except (UnicodeDecodeError, json.JSONDecodeError) as error:
            raise SystemExit(
                f"configuration JSON is invalid for {name}: {error}"
            ) from error

    package_member = outer_inventory["package.tgz"]

    if not package_member.isfile():
        raise SystemExit("package.tgz is not a regular file")

    if package_member.size > 2 * 1024 * 1024 * 1024:
        raise SystemExit("package.tgz exceeds the 2 GiB inspection limit")

    with tempfile.NamedTemporaryFile(
        prefix="tailscale-package-",
        suffix=".tgz",
    ) as package_file:
        extracted = outer.extractfile(package_member)

        if extracted is None:
            raise SystemExit("package.tgz could not be read")

        shutil.copyfileobj(extracted, package_file)
        package_file.flush()

        try:
            with tarfile.open(package_file.name, mode="r:*") as inner:
                inner_inventory = inventory_archive(
                    inner,
                    "package.tgz",
                    allow_links=True,
                    maximum_members=100_000,
                    maximum_regular_bytes=16 * 1024 * 1024 * 1024,
                )
        except tarfile.TarError as error:
            raise SystemExit(
                f"package.tgz is not a readable archive: {error}"
            ) from error

        if not any(member.isfile() for member in inner_inventory.values()):
            raise SystemExit("package.tgz contains no regular payload file")

print(f"PASS: INFO package matches {expected_info['package']!r}.")
print(f"PASS: INFO version matches {expected_info['version']!r}.")
print(f"PASS: INFO architecture includes {expected_info['arch']!r}.")
print(f"PASS: INFO minimum DSM matches {expected_info['os_min_ver']!r}.")
print(f"PASS: validated {len(outer_inventory)} outer SPK members.")
print(f"PASS: validated {len(inner_inventory)} package.tgz members.")
print(f"PASS: validated {len(lifecycle_members)} lifecycle shell scripts.")
print(f"PASS: validated {len(json_members)} package configuration files.")
PY

INSPECTION_RC=$?
printf 'SPK inspection status: %s\n' "$INSPECTION_RC"

if [ "$INSPECTION_RC" -ne 0 ]; then
  echo "STOP: static SPK inspection failed."
  exit "$INSPECTION_RC"
fi

release_pass "static SPK inspection completed without executing package content."
release_notice "no package was installed, started, published or transferred to DSM."
