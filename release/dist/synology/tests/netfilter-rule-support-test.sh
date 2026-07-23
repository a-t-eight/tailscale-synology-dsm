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

PASS_COUNT=0
FAIL_COUNT=0

cleanup() {
    rm -rf -- "${TEST_ROOT}"
}

trap cleanup EXIT

fail() {
    printf 'ERROR: %s\n' "$*" >&2
    exit 1
}

assert_nonzero_status() {
    local status="$1"

    if [ "${status}" -eq 0 ]; then
        fail "expected command failure, but it succeeded"
    fi
}

assert_contains() {
    local value="$1"
    local expected="$2"

    case "${value}" in
    *"${expected}"*)
        ;;
    *)
        printf 'ERROR: expected output to contain:\n  %s\n' \
            "${expected}" >&2
        printf 'Actual output:\n%s\n' \
            "${value}" >&2
        exit 1
        ;;
    esac
}

assert_probe_state_clean() {
    if [ -s "${MOCK_CHAINS}" ]; then
        printf 'ERROR: temporary chains remain:\n' >&2
        command cat "${MOCK_CHAINS}" >&2
        exit 1
    fi

    if [ -s "${MOCK_RULES}" ]; then
        printf 'ERROR: temporary rules remain:\n' >&2
        command cat "${MOCK_RULES}" >&2
        exit 1
    fi
}

setup_case() {
    CASE_ROOT="${TEST_ROOT}/case"

    rm -rf -- "${CASE_ROOT}"

    PACKAGE_ROOT="${CASE_ROOT}/package"
    PACKAGE_VAR="${PACKAGE_ROOT}/var"
    PACKAGE_TARGET="${CASE_ROOT}/target"
    MOCK_BIN="${CASE_ROOT}/mock-bin"
    MOCK_IPTABLES="${MOCK_BIN}/iptables"
    MOCK_STATE="${CASE_ROOT}/iptables-state"
    MOCK_COMMANDS="${MOCK_STATE}/commands"
    MOCK_CHAINS="${MOCK_STATE}/chains"
    MOCK_RULES="${MOCK_STATE}/rules"
    DEFINITIONS="${CASE_ROOT}/start-stop-definitions.sh"

    mkdir -p \
        "${PACKAGE_VAR}" \
        "${PACKAGE_TARGET}/bin" \
        "${MOCK_BIN}" \
        "${MOCK_STATE}"

    : >"${MOCK_COMMANDS}"
    : >"${MOCK_CHAINS}"
    : >"${MOCK_RULES}"

    awk '
        /^case \$1 in/ {
            exit
        }

        {
            print
        }
    ' "${START_STOP_SOURCE}" >"${DEFINITIONS}"

    command cat >"${MOCK_IPTABLES}" <<'IPTABLES'
#!/bin/bash

set -u

STATE="${MOCK_IPTABLES_STATE:?}"
COMMANDS="${STATE}/commands"
CHAINS="${STATE}/chains"
RULES="${STATE}/rules"

printf '%s\n' "$*" >>"${COMMANDS}"

iptables_error() {
    printf 'iptables: No chain/target/match by that name.\n' >&2
    exit 1
}

contains_line() {
    local value="$1"
    local file="$2"

    grep -Fxq -- "${value}" "${file}" 2>/dev/null
}

add_line() {
    local value="$1"
    local file="$2"

    if ! contains_line "${value}" "${file}"; then
        printf '%s\n' "${value}" >>"${file}"
    fi
}

remove_line() {
    local value="$1"
    local file="$2"
    local temporary="${file}.new.$$"

    contains_line "${value}" "${file}" ||
        return 1

    grep -Fvx -- "${value}" "${file}" \
        >"${temporary}" ||
        true

    mv -f -- "${temporary}" "${file}"
}

remove_rule_prefix() {
    local prefix="$1"
    local temporary="${RULES}.new.$$"

    awk -v prefix="${prefix}" '
        index($0, prefix) != 1 {
            print
        }
    ' "${RULES}" >"${temporary}"

    mv -f -- "${temporary}" "${RULES}"
}

[ "${1:-}" = "-t" ] ||
    iptables_error

table="${2:-}"
shift 2

operation="${1:-}"
shift || true

case "${operation}" in
-N)
    chain="${1:-}"
    key="${table}|${chain}"

    [ -n "${chain}" ] ||
        iptables_error

    if contains_line "${key}" "${CHAINS}"; then
        iptables_error
    fi

    add_line "${key}" "${CHAINS}"
    ;;

-A)
    chain="${1:-}"
    shift || true

    key="${table}|${chain}"
    rule="${key}|$*"

    contains_line "${key}" "${CHAINS}" ||
        iptables_error

    if [ "${MOCK_IPTABLES_FAIL_APPEND:-0}" = "1" ]; then
        iptables_error
    fi

    add_line "${rule}" "${RULES}"
    ;;

-C)
    chain="${1:-}"
    shift || true

    case "${chain}" in
    INPUT|FORWARD|OUTPUT|PREROUTING|POSTROUTING)
        # Reproduce DSM's built-in-chain check failure.
        iptables_error
        ;;
    esac

    key="${table}|${chain}"
    rule="${key}|$*"

    contains_line "${key}" "${CHAINS}" ||
        iptables_error

    if [ "${MOCK_IPTABLES_FAIL_VERIFY:-0}" = "1" ]; then
        iptables_error
    fi

    contains_line "${rule}" "${RULES}" ||
        iptables_error
    ;;

-F)
    chain="${1:-}"
    key="${table}|${chain}"

    contains_line "${key}" "${CHAINS}" ||
        iptables_error

    remove_rule_prefix "${key}|"
    ;;

-X)
    chain="${1:-}"
    key="${table}|${chain}"

    contains_line "${key}" "${CHAINS}" ||
        iptables_error

    if grep -Fq -- "${key}|" "${RULES}"; then
        iptables_error
    fi

    remove_line "${key}" "${CHAINS}" ||
        iptables_error
    ;;

*)
    iptables_error
    ;;
esac

exit 0
IPTABLES

    chmod 0755 "${MOCK_IPTABLES}"

    export SYNOPKG_DSM_VERSION_MAJOR=7
    export SYNOPKG_PKGVAR="${PACKAGE_VAR}"
    export SYNOPKG_PKGDEST="${PACKAGE_TARGET}"
    export SYNOPKG_PKGNAME="Tailscale"
    export TAILSCALE_SYNOLOGY_PACKAGE_ROOT="${PACKAGE_ROOT}"

    export MOCK_IPTABLES_STATE="${MOCK_STATE}"
    export MOCK_IPTABLES_FAIL_APPEND=0
    export MOCK_IPTABLES_FAIL_VERIFY=0

    # shellcheck disable=SC1090
    source "${DEFINITIONS}"

    IPTABLES_BIN="${MOCK_IPTABLES}"
}

run_connmark_restore_probe() {
    check_iptables_rule_support \
        "CONNMARK restore target" \
        mangle \
        PREROUTING \
        -m conntrack \
        --ctstate ESTABLISHED,RELATED \
        -j CONNMARK \
        --restore-mark \
        --nfmask 0xff0000 \
        --ctmask 0xff0000
}

test_builtin_failure_temporary_chain_success() {
    setup_case

    if "${IPTABLES_BIN}" \
        -t mangle \
        -C PREROUTING \
        -m conntrack \
        --ctstate ESTABLISHED,RELATED \
        -j CONNMARK \
        --restore-mark \
        --nfmask 0xff0000 \
        --ctmask 0xff0000 \
        >/dev/null 2>&1
    then
        fail "mock unexpectedly accepted built-in PREROUTING check"
    fi

    : >"${MOCK_COMMANDS}"

    run_connmark_restore_probe

    assert_probe_state_clean

    grep -F -- \
        "-t mangle -N ts-pf-rule-" \
        "${MOCK_COMMANDS}" >/dev/null ||
        fail "temporary mangle chain was not created"

    grep -F -- \
        "-t mangle -A ts-pf-rule-" \
        "${MOCK_COMMANDS}" >/dev/null ||
        fail "candidate rule was not appended to the temporary chain"

    grep -F -- \
        "-t mangle -C ts-pf-rule-" \
        "${MOCK_COMMANDS}" >/dev/null ||
        fail "candidate rule was not verified in the temporary chain"

    if grep -Fq -- \
        "-t mangle -C PREROUTING" \
        "${MOCK_COMMANDS}"
    then
        fail "generic probe still checked built-in PREROUTING"
    fi
}

test_append_failure_cleanup() {
    local output
    local status

    setup_case

    export MOCK_IPTABLES_FAIL_APPEND=1

    set +e
    output="$(
        run_connmark_restore_probe 2>&1
    )"
    status=$?
    set -e

    assert_nonzero_status "${status}"

    assert_contains \
        "${output}" \
        "iptables prerequisite CONNMARK restore target for mangle/PREROUTING failed"

    assert_probe_state_clean
}

test_verify_failure_cleanup() {
    local output
    local status

    setup_case

    export MOCK_IPTABLES_FAIL_VERIFY=1

    set +e
    output="$(
        run_connmark_restore_probe 2>&1
    )"
    status=$?
    set -e

    assert_nonzero_status "${status}"

    assert_contains \
        "${output}" \
        "cannot verify iptables prerequisite CONNMARK restore target"

    assert_probe_state_clean
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
    "built-in check fails but temporary-chain probe succeeds" \
    test_builtin_failure_temporary_chain_success

run_case \
    "temporary-chain append failure cleans up" \
    test_append_failure_cleanup

run_case \
    "temporary-chain verification failure cleans up" \
    test_verify_failure_cleanup

printf '\nResults: %s passed, %s failed\n' \
    "${PASS_COUNT}" \
    "${FAIL_COUNT}"

if [ "${FAIL_COUNT}" -ne 0 ]; then
    exit 1
fi
