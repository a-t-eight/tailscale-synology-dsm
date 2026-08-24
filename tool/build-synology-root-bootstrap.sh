#!/usr/bin/env bash
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
VERSION_OVERRIDE="${TS_VERSION_OVERRIDE:-1.98.96}"
OUT_ROOT="${1:-${REPO_ROOT}/build/synology/v1.98.9-final}"

SOURCE_DATE_EPOCH="${SOURCE_DATE_EPOCH:-}"

if [ -z "${SOURCE_DATE_EPOCH}" ]; then
    if ! SOURCE_DATE_EPOCH="$(
        git -C "${REPO_ROOT}" \
            show \
            -s \
            --format='%ct' \
            HEAD
    )"
    then
        printf 'ERROR: unable to derive SOURCE_DATE_EPOCH from HEAD\n' >&2
        exit 1
    fi
fi

case "${SOURCE_DATE_EPOCH}" in
    ''|*[!0-9]*)
        printf 'ERROR: SOURCE_DATE_EPOCH must be a non-negative integer: %s\n' \
            "${SOURCE_DATE_EPOCH}" >&2
        exit 1
        ;;
esac

export SOURCE_DATE_EPOCH

printf 'SOURCE_DATE_EPOCH=%s\n' \
    "${SOURCE_DATE_EPOCH}"

SIDELOAD_OUT="${OUT_ROOT}/sideload"
PACKAGE_CENTER_OUT="${OUT_ROOT}/package-center-reference"
REFERENCE_OUT="${OUT_ROOT}/reference-metadata"

rm -rf -- "${OUT_ROOT}"

mkdir -p \
    "${SIDELOAD_OUT}" \
    "${PACKAGE_CENTER_OUT}" \
    "${REFERENCE_OUT}"

(
    cd "${REPO_ROOT}"

    TS_VERSION_OVERRIDE="${VERSION_OVERRIDE}" \
        ./tool/go run ./cmd/dist build \
        --out "${SIDELOAD_OUT}" \
        synology/dsm7/x86_64

    TS_VERSION_OVERRIDE="${VERSION_OVERRIDE}" \
        ./tool/go run ./cmd/dist build \
        --synology-package-center \
        --out "${PACKAGE_CENTER_OUT}" \
        synology/dsm7-2/x86_64
)

shopt -s nullglob

sideload_spks=("${SIDELOAD_OUT}"/*.spk)
package_center_spks=("${PACKAGE_CENTER_OUT}"/*.spk)

if ((${#sideload_spks[@]} != 1)); then
    printf 'ERROR: expected one sideload SPK, found %d\n' \
        "${#sideload_spks[@]}" >&2
    exit 1
fi

if ((${#package_center_spks[@]} != 1)); then
    printf 'ERROR: expected one Package Center SPK, found %d\n' \
        "${#package_center_spks[@]}" >&2
    exit 1
fi

SIDELOAD_SPK="${sideload_spks[0]}"
PACKAGE_CENTER_SPK="${package_center_spks[0]}"

WORK="$(mktemp -d)"
trap 'rm -rf -- "${WORK}"' EXIT

SIDE="${WORK}/sideload"
CENTER="${WORK}/package-center"

mkdir -p "${SIDE}" "${CENTER}"

tar -xf "${SIDELOAD_SPK}" -C "${SIDE}"
tar -xf "${PACKAGE_CENTER_SPK}" -C "${CENTER}"

for file in \
    conf/resource \
    conf/PKG_DEPS \
    scripts/start-stop-status \
    scripts/tailscale-netfilter-reconciler \
    scripts/preupgrade \
    scripts/postupgrade \
    scripts/tailscale-synology-bootstrap
do
    cmp "${SIDE}/${file}" "${CENTER}/${file}" || {
        printf 'ERROR: package variants differ unexpectedly: %s\n' \
            "${file}" >&2
        exit 1
    }
done

python3 - \
    "${SIDE}/package.tgz" \
    "${CENTER}/package.tgz" <<'PYTAR'
import hashlib
import itertools
import sys
import tarfile
from pathlib import Path

sideload_path = Path(sys.argv[1])
package_center_path = Path(sys.argv[2])


def file_digest(archive: tarfile.TarFile, member: tarfile.TarInfo) -> str:
    stream = archive.extractfile(member)

    if stream is None:
        raise RuntimeError(
            f"cannot extract {member.name!r} from {archive.name}"
        )

    digest = hashlib.sha256()

    while True:
        chunk = stream.read(1024 * 1024)
        if not chunk:
            break
        digest.update(chunk)

    return digest.hexdigest()


def archive_manifest(path: Path):
    rows = []

    with tarfile.open(path, mode="r:gz") as archive:
        members = sorted(
            archive.getmembers(),
            key=lambda member: (
                member.name,
                member.type,
                member.linkname,
            ),
        )

        for member in members:
            digest = None

            if member.isfile():
                digest = file_digest(archive, member)

            rows.append(
                (
                    member.name,
                    member.type,
                    member.mode,
                    member.uid,
                    member.gid,
                    member.uname,
                    member.gname,
                    member.size,
                    member.linkname,
                    member.devmajor,
                    member.devminor,
                    digest,
                )
            )

    return rows


sideload = archive_manifest(sideload_path)
package_center = archive_manifest(package_center_path)

if sideload != package_center:
    print(
        "ERROR: inner package payloads differ",
        file=sys.stderr,
    )

    for index, pair in enumerate(
        itertools.zip_longest(
            sideload,
            package_center,
            fillvalue=None,
        )
    ):
        left, right = pair

        if left == right:
            continue

        print(
            f"  entry {index}:",
            file=sys.stderr,
        )
        print(
            f"    sideload:       {left!r}",
            file=sys.stderr,
        )
        print(
            f"    package-center: {right!r}",
            file=sys.stderr,
        )

    raise SystemExit(1)

print("Inner package payload validation passed.")
PYTAR

if cmp -s \
    "${SIDE}/conf/privilege" \
    "${CENTER}/conf/privilege"
then
    printf 'ERROR: privilege manifests should differ\n' >&2
    exit 1
fi

if cmp -s "${SIDE}/INFO" "${CENTER}/INFO"; then
    printf 'ERROR: INFO files should have different package metadata\n' >&2
    exit 1
fi

python3 - \
    "${SIDE}/INFO" \
    "${CENTER}/INFO" <<'PYINFO'
import sys
from pathlib import Path

expected_versions = {
    "sideload": 'version="1.98.96-700098097"',
    "Package Center": 'version="1.98.96-720098097"',
}
expected_minimum = 'os_min_ver="7.3-86009"'

for label, value in zip(
    ("sideload", "Package Center"),
    sys.argv[1:],
):
    path = Path(value)

    if not path.is_file():
        raise RuntimeError(
            f"{label} package is missing outer INFO metadata"
        )

    lines = path.read_text(
        encoding="utf-8",
    ).splitlines()
    version_matches = [
        line
        for line in lines
        if line.startswith("version=")
    ]

    if version_matches != [expected_versions[label]]:
        raise RuntimeError(
            "{} INFO has unexpected version entries: {!r}".format(
                label,
                version_matches,
            )
        )

    minimum_matches = [
        line
        for line in lines
        if line.startswith("os_min_ver=")
    ]

    if minimum_matches != [expected_minimum]:
        raise RuntimeError(
            "{} INFO has unexpected os_min_ver entries: {!r}".format(
                label,
                minimum_matches,
            )
        )

    maximum_matches = [
        line
        for line in lines
        if line.startswith("os_max_ver=")
    ]

    if maximum_matches:
        raise RuntimeError(
            "{} INFO has unexpected os_max_ver entries: {!r}".format(
                label,
                maximum_matches,
            )
        )

print("Outer package metadata validation passed.")
PYINFO

bash -n "${SIDE}/scripts/start-stop-status"
bash -n "${SIDE}/scripts/tailscale-netfilter-reconciler"
bash -n "${SIDE}/scripts/tailscale-synology-bootstrap"

if [ ! -x "${SIDE}/scripts/tailscale-netfilter-reconciler" ]; then
    printf 'ERROR: packaged netfilter reconciler is not executable\n' >&2
    exit 1
fi

python3 - \
    "${SIDE}/conf/privilege" \
    "${SIDE}/conf/privilege.bootstrap-package" \
    "${SIDE}/conf/privilege.bootstrap-root" \
    "${CENTER}/conf/privilege" \
    "${SIDE}/conf/resource" \
    "${SIDE}/package.tgz" \
    "${SIDE}/scripts/tailscale-synology-bootstrap" <<'PYJSON'
import json
import sys
import tarfile
from pathlib import Path

(
    active_sideload_path,
    safe_template_path,
    root_template_path,
    package_center_path,
    resource_path,
    inner_package_path,
    outer_bootstrap_path,
) = map(Path, sys.argv[1:])

active_sideload = json.loads(active_sideload_path.read_text())
safe_template = json.loads(safe_template_path.read_text())
root_template = json.loads(root_template_path.read_text())
package_center = json.loads(package_center_path.read_text())
resource = json.loads(resource_path.read_text())

assert active_sideload == safe_template
assert active_sideload["defaults"]["run-as"] == "package"
assert "tool" not in active_sideload
assert root_template["defaults"]["run-as"] == "root"

assert package_center["defaults"]["run-as"] == "package"
assert package_center["tool"] == [{
    "relpath": "bin/tailscaled",
    "user": "package",
    "group": "package",
    "capabilities": "cap_net_admin,cap_chown,cap_net_raw",
}]

assert resource["usr-local-linker"]["bin"] == [
    "bin/tailscale",
    "bin/tailscale-synology-bootstrap",
]

with tarfile.open(inner_package_path, mode="r:gz") as archive:
    bootstrap_member = archive.getmember(
        "bin/tailscale-synology-bootstrap"
    )
    assert bootstrap_member.isfile()
    assert bootstrap_member.mode == 0o755

    stream = archive.extractfile(bootstrap_member)
    assert stream is not None
    assert stream.read() == outer_bootstrap_path.read_bytes()

print("Bootstrap packaging and privilege validation passed.")
PYJSON

python3 - \
    "${SIDE}/conf/PKG_DEPS" \
    "${CENTER}/conf/PKG_DEPS" <<'PYDEPS'
import sys
from pathlib import Path

expected = b"[iptables-netfilter-extensions]\npkg_min_ver=1.1.0-2\nos_min_ver=7.3-86009\n"

for label, value in zip(
    ("sideload", "Package Center"),
    sys.argv[1:],
):
    path = Path(value)

    if not path.is_file():
        raise RuntimeError(
            f"{label} package is missing conf/PKG_DEPS"
        )

    actual = path.read_bytes()

    if actual != expected:
        raise RuntimeError(
            "{} PKG_DEPS has unexpected contents:\n{!r}".format(
                label,
                actual,
            )
        )

print("Package dependency validation passed.")
PYDEPS

cp \
    "${CENTER}/conf/privilege" \
    "${REFERENCE_OUT}/privilege-package-center"

cp \
    "${CENTER}/conf/resource" \
    "${REFERENCE_OUT}/resource-package-center"

cp \
    "${CENTER}/conf/PKG_DEPS" \
    "${REFERENCE_OUT}/PKG_DEPS-package-center"

cp \
    "${CENTER}/INFO" \
    "${REFERENCE_OUT}/INFO-package-center"

(
    cd "${SIDELOAD_OUT}"
    sha256sum ./*.spk >SHA256SUMS
    sha256sum --check SHA256SUMS
)

(
    cd "${PACKAGE_CENTER_OUT}"
    sha256sum ./*.spk >SHA256SUMS
    sha256sum --check SHA256SUMS
)

printf '\nSideload package:\n  %s\n' "${SIDELOAD_SPK}"
printf '\nPackage Center reference:\n  %s\n' "${PACKAGE_CENTER_SPK}"
printf '\nReference metadata:\n  %s\n' "${REFERENCE_OUT}"
