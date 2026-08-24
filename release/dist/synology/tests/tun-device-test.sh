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

TEST_ROOT="$(mktemp -d)"
DEFINITIONS="${TEST_ROOT}/start-stop-definitions.sh"

PASS_COUNT=0

cleanup() {
    rm -rf -- "${TEST_ROOT}"
}

trap cleanup EXIT

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

export SYNOPKG_DSM_VERSION_MAJOR=7
export SYNOPKG_PKGVAR="${TEST_ROOT}/pkgvar"
export SYNOPKG_PKGDEST="${TEST_ROOT}/pkgdest"
export SYNOPKG_PKGNAME=Tailscale

source "${DEFINITIONS}"


fail() {
    printf 'ERROR: %s\n' "$*" >&2
    exit 1
}


reset_case() {
    CASE_ROOT="${TEST_ROOT}/$1"

    rm -rf -- "${CASE_ROOT}"

    mkdir -p \
        "${CASE_ROOT}/dev" \
        "${CASE_ROOT}/pkgvar"

    TUN_DEVICE="${CASE_ROOT}/dev/net/tun"
    TUN_PROC_MISC="${CASE_ROOT}/proc-misc"
    TUN_WAIT_ATTEMPTS=2
    TUN_WAIT_SECONDS=0

    : >"${CASE_ROOT}/mknod.log"
    : >"${CASE_ROOT}/output.log"
}


printf 'TEST: existing TUN device is accepted ... '

reset_case existing

tun_device_is_ready() {
    return 0
}

tun_driver_available() {
    return 0
}

mknod() {
    printf '%s\n' "$*" >>"${CASE_ROOT}/mknod.log"
    return 1
}

chmod() {
    return 0
}

ensure_tun_created \
    >"${CASE_ROOT}/output.log" \
    2>&1 ||
    fail "existing TUN device was rejected"

[ ! -s "${CASE_ROOT}/mknod.log" ] ||
    fail "existing TUN device unexpectedly triggered mknod"

printf 'PASS\n'
PASS_COUNT=$((PASS_COUNT + 1))


printf 'TEST: missing TUN node is created with major 10 minor 200 ... '

reset_case create

tun_device_is_ready() {
    [ -e "${CASE_ROOT}/ready" ]
}

tun_driver_available() {
    return 0
}

mknod() {
    printf '%s\n' "$*" >>"${CASE_ROOT}/mknod.log"
    touch "${CASE_ROOT}/ready"
    return 0
}

chmod() {
    return 0
}

ensure_tun_created \
    >"${CASE_ROOT}/output.log" \
    2>&1 ||
    fail "missing TUN device was not created"

grep -Fq -- \
    "${TUN_DEVICE} c 10 200" \
    "${CASE_ROOT}/mknod.log" ||
    fail "mknod did not receive character-device major/minor 10:200"

grep -Fq -- \
    "created kernel TUN device ${TUN_DEVICE}" \
    "${CASE_ROOT}/output.log" ||
    fail "successful TUN creation was not logged"

printf 'PASS\n'
PASS_COUNT=$((PASS_COUNT + 1))


printf 'TEST: unavailable TUN driver fails clearly ... '

reset_case unavailable

tun_device_is_ready() {
    return 1
}

tun_driver_available() {
    return 1
}

try_load_tun_driver() {
    return 1
}

chmod() {
    return 0
}

if ensure_tun_created \
    >"${CASE_ROOT}/output.log" \
    2>&1
then
    fail "unavailable TUN driver unexpectedly passed"
fi

grep -Fq -- \
    'kernel TUN driver is unavailable' \
    "${CASE_ROOT}/output.log" ||
    fail "missing-driver error was not reported"

printf 'PASS\n'
PASS_COUNT=$((PASS_COUNT + 1))


printf '\nResults: %d passed, 0 failed\n' \
    "${PASS_COUNT}"
