#!/bin/bash

set -euo pipefail

SCRIPT_DIR="$(
    cd -- "$(dirname -- "${BASH_SOURCE[0]}")" &&
        pwd
)"

REPO_ROOT="$(
    cd -- "${SCRIPT_DIR}/../../../.." &&
        pwd
)"

START_STOP_SOURCE="${REPO_ROOT}/release/dist/synology/files/scripts/start-stop-status"

TEST_ROOT="$(
    mktemp -d
)"

cleanup() {
    rm -rf -- "${TEST_ROOT}"
}

trap cleanup EXIT

DEFINITIONS="${TEST_ROOT}/start-stop-definitions.sh"
STDOUT_FILE="${TEST_ROOT}/stdout"
STDERR_FILE="${TEST_ROOT}/stderr"

mkdir -p \
    "${TEST_ROOT}/pkgvar" \
    "${TEST_ROOT}/pkgdest/bin"

awk '
    /^case \$1 in/ {
        exit
    }

    {
        print
    }
' "${START_STOP_SOURCE}" >"${DEFINITIONS}"

set +e

env \
    SYNOPKG_DSM_VERSION_MAJOR=7 \
    SYNOPKG_PKGVAR="${TEST_ROOT}/pkgvar" \
    SYNOPKG_PKGDEST="${TEST_ROOT}/pkgdest" \
    SYNOPKG_PKGNAME=Tailscale \
    bash -u -c '
        source "$1"

        printf "%s\n" \
            "$NETFILTER_LOCALAPI_ATTEMPTS" \
            "$NETFILTER_BACKEND_ATTEMPTS" \
            "$NETFILTER_REPAIR_ATTEMPTS" \
            "$NETFILTER_SETTLE_SECONDS" \
            "$NETFILTER_POST_REPAIR_SETTLE_SECONDS"
    ' bash "${DEFINITIONS}" \
    >"${STDOUT_FILE}" \
    2>"${STDERR_FILE}"

STATUS=$?

set -e

if [ "${STATUS}" -ne 0 ]; then
    printf 'ERROR: loading start-stop definitions failed with status %s\n' \
        "${STATUS}" >&2

    sed -n '1,200p' "${STDERR_FILE}" >&2
    exit 1
fi

if [ -s "${STDERR_FILE}" ]; then
    printf 'ERROR: loading start-stop definitions produced stderr:\n' >&2
    sed -n '1,200p' "${STDERR_FILE}" >&2
    exit 1
fi

EXPECTED="${TEST_ROOT}/expected"

printf '%s\n' \
    30 \
    45 \
    15 \
    8 \
    3 \
    >"${EXPECTED}"

if ! cmp -s \
    "${EXPECTED}" \
    "${STDOUT_FILE}"
then
    printf 'ERROR: unexpected reconciliation defaults\n' >&2

    printf 'Expected:\n' >&2
    sed -n '1,20p' "${EXPECTED}" >&2

    printf 'Actual:\n' >&2
    sed -n '1,20p' "${STDOUT_FILE}" >&2

    exit 1
fi

printf 'TEST: start-stop definitions load cleanly ... PASS\n'
