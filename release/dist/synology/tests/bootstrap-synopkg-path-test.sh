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

BOOTSTRAP_SOURCE="${REPO_ROOT}/release/dist/synology/files/scripts/tailscale-synology-bootstrap"

PASS_COUNT=0
FAIL_COUNT=0

fail() {
    printf 'ERROR: %s\n' "$*" >&2
    exit 1
}

test_default_synopkg_path() {
    local actual

    actual="$(
        unset TAILSCALE_SYNOLOGY_SYNOPKG

        export TAILSCALE_SYNOLOGY_PACKAGE_ROOT="/tmp/tailscale-bootstrap-path-test"

        # shellcheck disable=SC1090
        source "${BOOTSTRAP_SOURCE}"

        printf '%s\n' "${SYNO_PKG}"
    )"

    [ "${actual}" = "/usr/syno/bin/synopkg" ] ||
        fail "unexpected default synopkg path: ${actual}"
}

test_synopkg_override() {
    local expected="/tmp/mock-synopkg"
    local actual

    actual="$(
        export TAILSCALE_SYNOLOGY_PACKAGE_ROOT="/tmp/tailscale-bootstrap-path-test"
        export TAILSCALE_SYNOLOGY_SYNOPKG="${expected}"

        # shellcheck disable=SC1090
        source "${BOOTSTRAP_SOURCE}"

        printf '%s\n' "${SYNO_PKG}"
    )"

    [ "${actual}" = "${expected}" ] ||
        fail "synopkg override was not preserved: ${actual}"
}

run_case() {
    local name="$1"
    local function_name="$2"

    printf 'TEST: %s ... ' "${name}"

    if (
        set -euo pipefail
        "${function_name}"
    ); then
        printf 'PASS\n'
        PASS_COUNT=$((PASS_COUNT + 1))
    else
        printf 'FAIL\n'
        FAIL_COUNT=$((FAIL_COUNT + 1))
    fi
}

run_case \
    "bootstrap defaults to DSM synopkg path" \
    test_default_synopkg_path

run_case \
    "bootstrap preserves explicit synopkg override" \
    test_synopkg_override

printf '\nResults: %s passed, %s failed\n' \
    "${PASS_COUNT}" \
    "${FAIL_COUNT}"

if [ "${FAIL_COUNT}" -ne 0 ]; then
    exit 1
fi
