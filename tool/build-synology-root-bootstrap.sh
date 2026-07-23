#!/usr/bin/env bash
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
VERSION_OVERRIDE="${TS_VERSION_OVERRIDE:-1.98.90}"
OUT_ROOT="${1:-${REPO_ROOT}/build/synology/v1.98.9-final}"

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
    package.tgz \
    conf/resource \
    scripts/start-stop-status \
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

if cmp -s \
    "${SIDE}/conf/privilege" \
    "${CENTER}/conf/privilege"
then
    printf 'ERROR: privilege manifests should differ\n' >&2
    exit 1
fi

if cmp -s "${SIDE}/INFO" "${CENTER}/INFO"; then
    printf 'ERROR: INFO files should have different DSM bounds\n' >&2
    exit 1
fi

bash -n "${SIDE}/scripts/start-stop-status"
bash -n "${SIDE}/scripts/tailscale-synology-bootstrap"

python3 - \
    "${SIDE}/conf/privilege" \
    "${SIDE}/conf/privilege.bootstrap-package" \
    "${SIDE}/conf/privilege.bootstrap-root" \
    "${CENTER}/conf/privilege" <<'PYJSON'
import json
import sys
from pathlib import Path

(
    active_sideload_path,
    safe_template_path,
    root_template_path,
    package_center_path,
) = map(Path, sys.argv[1:])

active_sideload = json.loads(active_sideload_path.read_text())
safe_template = json.loads(safe_template_path.read_text())
root_template = json.loads(root_template_path.read_text())
package_center = json.loads(package_center_path.read_text())

assert active_sideload == safe_template
assert active_sideload["defaults"]["run-as"] == "package"
assert root_template["defaults"]["run-as"] == "root"

assert package_center["defaults"]["run-as"] == "package"
assert package_center["tool"] == [{
    "relpath": "bin/tailscaled",
    "user": "package",
    "group": "package",
    "capabilities": "cap_net_admin,cap_chown,cap_net_raw",
}]

print("Privilege manifest validation passed.")
PYJSON

cp \
    "${CENTER}/conf/privilege" \
    "${REFERENCE_OUT}/privilege-package-center"

cp \
    "${CENTER}/conf/resource" \
    "${REFERENCE_OUT}/resource-package-center"

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
