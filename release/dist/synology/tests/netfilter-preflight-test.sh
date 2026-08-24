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

assert_status() {
    local expected="$1"
    local actual="$2"

    if [ "${actual}" -ne "${expected}" ]; then
        fail \
            "expected status ${expected}, received ${actual}"
    fi
}

assert_nonzero_status() {
    local actual="$1"

    if [ "${actual}" -eq 0 ]; then
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

assert_file_has_no_probe_state() {
    local file="$1"

    if grep -q '^ts-pf-nat-' "${file}" 2>/dev/null; then
        printf 'ERROR: temporary probe state remains in %s:\n' \
            "${file}" >&2
        cat "${file}" >&2
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
    MOCK_IPTABLES_STATE="${CASE_ROOT}/iptables-state"
    MOCK_IPTABLES_LOG="${MOCK_IPTABLES_STATE}/commands.log"
    MOCK_CHAINS="${MOCK_IPTABLES_STATE}/chains"
    MOCK_HOOKS="${MOCK_IPTABLES_STATE}/hooks"
    MOCK_MASQUERADE="${MOCK_IPTABLES_STATE}/masquerade"
    MOCK_DELETE_COUNT="${MOCK_IPTABLES_STATE}/delete-count"
    DEFINITIONS="${CASE_ROOT}/start-stop-definitions.sh"

    mkdir -p \
        "${PACKAGE_ROOT}/conf" \
        "${PACKAGE_VAR}" \
        "${PACKAGE_TARGET}/bin" \
        "${MOCK_BIN}" \
        "${MOCK_IPTABLES_STATE}"

    : >"${MOCK_IPTABLES_LOG}"
    : >"${MOCK_CHAINS}"
    : >"${MOCK_HOOKS}"
    : >"${MOCK_MASQUERADE}"
    printf '0\n' >"${MOCK_DELETE_COUNT}"

    awk '
        /^case \$1 in/ {
            exit
        }

        {
            print
        }
    ' "${START_STOP_SOURCE}" >"${DEFINITIONS}"

    cat >"${MOCK_IPTABLES}" <<'IPTABLES'
#!/bin/bash

set -u

STATE="${MOCK_IPTABLES_STATE:?MOCK_IPTABLES_STATE is required}"
COMMAND_LOG="${STATE}/commands.log"
CHAINS="${STATE}/chains"
HOOKS="${STATE}/hooks"
MASQUERADE="${STATE}/masquerade"
DELETE_COUNT="${STATE}/delete-count"

printf '%s\n' "$*" >>"${COMMAND_LOG}"

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

    if ! contains_line "${value}" "${file}"; then
        return 1
    fi

    grep -Fvx -- "${value}" "${file}" \
        >"${temporary}" ||
        true

    mv -f -- "${temporary}" "${file}"
}

list_filter_table() {
    cat <<'EOF'
-P INPUT ACCEPT
-P FORWARD ACCEPT
-P OUTPUT ACCEPT
-N INPUT_FIREWALL
-N FORWARD_FIREWALL
-A INPUT -j INPUT_FIREWALL
-A FORWARD -j FORWARD_FIREWALL
EOF
}

list_mangle_table() {
    cat <<'EOF'
-P PREROUTING ACCEPT
-P INPUT ACCEPT
-P FORWARD ACCEPT
-P OUTPUT ACCEPT
-P POSTROUTING ACCEPT
EOF
}

list_nat_table() {
    local chain

    cat <<'EOF'
-P PREROUTING ACCEPT
-P INPUT ACCEPT
-P OUTPUT ACCEPT
-P POSTROUTING ACCEPT
-N DEFAULT_PREROUTING
-N DEFAULT_OUTPUT
-N DEFAULT_POSTROUTING
EOF

    while IFS= read -r chain; do
        [ -n "${chain}" ] ||
            continue

        printf '%s\n' \
            "-N ${chain}"
    done <"${CHAINS}"

    while IFS= read -r chain; do
        [ -n "${chain}" ] ||
            continue

        printf '%s\n' \
            "-A DEFAULT_POSTROUTING -j ${chain}"
    done <"${HOOKS}"

    while IFS= read -r chain; do
        [ -n "${chain}" ] ||
            continue

        printf '%s\n' \
            "-A ${chain} -m mark --mark 0xfe0000/0xff0000 -j MASQUERADE"
    done <"${MASQUERADE}"
}

if [ "${1:-}" != "-t" ] ||
    [ -z "${2:-}" ]
then
    iptables_error
fi

table="$2"
shift 2

operation="${1:-}"
[ -n "${operation}" ] ||
    iptables_error

shift

case "${operation}" in
-S)
    # Reproduce DSM's observed behaviour:
    #
    #   iptables -t TABLE -S
    #       succeeds and prints the complete table.
    #
    #   iptables -t TABLE -S CHAIN
    #       fails or returns an unrelated private chain.
    if [ "$#" -ne 0 ]; then
        iptables_error
    fi

    case "${table}" in
    filter)
        list_filter_table
        ;;
    mangle)
        list_mangle_table
        ;;
    nat)
        list_nat_table
        ;;
    *)
        iptables_error
        ;;
    esac
    ;;

-N)
    chain="${1:-}"

    [ "${table}" = "nat" ] ||
        iptables_error

    [ -n "${chain}" ] ||
        iptables_error

    if contains_line "${chain}" "${CHAINS}"; then
        iptables_error
    fi

    add_line "${chain}" "${CHAINS}"
    ;;

-I)
    parent="${1:-}"
    position="${2:-}"
    jump_option="${3:-}"
    target="${4:-}"

    [ "${table}" = "nat" ] ||
        iptables_error

    [ "${parent}" = "POSTROUTING" ] ||
        iptables_error

    [ "${position}" = "1" ] ||
        iptables_error

    [ "${jump_option}" = "-j" ] ||
        iptables_error

    contains_line "${target}" "${CHAINS}" ||
        iptables_error

    add_line "${target}" "${HOOKS}"
    ;;

-A)
    chain="${1:-}"
    shift || true

    [ "${table}" = "nat" ] ||
        iptables_error

    contains_line "${chain}" "${CHAINS}" ||
        iptables_error

    [ "$*" = \
        "-m mark --mark 0xfe0000/0xff0000 -j MASQUERADE" ] ||
        iptables_error

    if [ "${MOCK_IPTABLES_FAIL_MASQUERADE:-0}" = "1" ]; then
        iptables_error
    fi

	add_line "${chain}" "${MASQUERADE}"

	;;

-C)
    chain="${1:-}"
    shift || true

	[ "${table}" = "nat" ] ||
		iptables_error

	case "${chain}" in
    POSTROUTING)
        [ "${1:-}" = "-j" ] ||
            iptables_error

        target="${2:-}"

        contains_line "${target}" "${HOOKS}" ||
            iptables_error
        ;;

    *)
        contains_line "${chain}" "${CHAINS}" ||
            iptables_error

        [ "$*" = \
            "-m mark --mark 0xfe0000/0xff0000 -j MASQUERADE" ] ||
            iptables_error

        contains_line "${chain}" "${MASQUERADE}" ||
            iptables_error
        ;;
    esac
    ;;

-D)
    parent="${1:-}"
    jump_option="${2:-}"
    target="${3:-}"

    [ "${table}" = "nat" ] ||
        iptables_error

    case "${parent}" in
    POSTROUTING|DEFAULT_POSTROUTING)
        ;;
    *)
        iptables_error
        ;;
    esac

	[ "${jump_option}" = "-j" ] ||
		iptables_error

	delete_count="$(cat "${DELETE_COUNT}")"
	no_progress_successes="${MOCK_IPTABLES_DELETE_NO_PROGRESS_SUCCESSES:-0}"
	if [ "${delete_count}" -lt "${no_progress_successes}" ]; then
		printf '%s\n' \
			"$((delete_count + 1))" \
			>"${DELETE_COUNT}"
		exit 0
	fi

	remove_line "${target}" "${HOOKS}" ||
        iptables_error
    ;;

-F)
    chain="${1:-}"

    [ "${table}" = "nat" ] ||
        iptables_error

    contains_line "${chain}" "${CHAINS}" ||
        iptables_error

    remove_line "${chain}" "${MASQUERADE}" ||
        true
    ;;

-X)
    chain="${1:-}"

    [ "${table}" = "nat" ] ||
        iptables_error

    contains_line "${chain}" "${CHAINS}" ||
        iptables_error

    if contains_line "${chain}" "${HOOKS}" ||
        contains_line "${chain}" "${MASQUERADE}"
    then
        iptables_error
    fi

    remove_line "${chain}" "${CHAINS}" ||
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

    export MOCK_IPTABLES_STATE
    export MOCK_IPTABLES_FAIL_MASQUERADE=0
    export MOCK_IPTABLES_DELETE_NO_PROGRESS_SUCCESSES=0
    export TAILSCALE_SYNOLOGY_TEST_MODE=1

    # shellcheck disable=SC1090
    source "${DEFINITIONS}"

    IPTABLES_BIN="${MOCK_IPTABLES}"
}

assert_probe_state_clean() {
    assert_file_has_no_probe_state "${MOCK_CHAINS}"
    assert_file_has_no_probe_state "${MOCK_HOOKS}"
    assert_file_has_no_probe_state "${MOCK_MASQUERADE}"
}

test_dsm_table_wide_chain_detection() {
    setup_case

    # Confirm that the mock reproduces the exact DSM incompatibility
    # that caused the original false negative.
    if "${IPTABLES_BIN}" \
        -t filter \
        -S INPUT \
        >/dev/null 2>&1
    then
        fail \
            "mock unexpectedly accepted chain-specific filter listing"
    fi

    check_iptables_chain filter INPUT
    check_iptables_chain filter FORWARD
    check_iptables_chain nat POSTROUTING
    check_iptables_chain mangle PREROUTING
    check_iptables_chain mangle OUTPUT
    check_iptables_chain mangle FORWARD
}

test_tailscale_nat_topology_success() {
    setup_case

    check_tailscale_nat_topology

    assert_probe_state_clean

    grep -F -- \
        "-t nat -I POSTROUTING 1 -j ts-pf-nat-" \
        "${MOCK_IPTABLES_LOG}" >/dev/null ||
        fail \
            "temporary POSTROUTING hook was not attempted"

    grep -F -- \
        "-m mark --mark 0xfe0000/0xff0000 -j MASQUERADE" \
        "${MOCK_IPTABLES_LOG}" >/dev/null ||
        fail \
            "temporary marked MASQUERADE rule was not attempted"

    grep -F -- \
        "-t nat -X ts-pf-nat-" \
        "${MOCK_IPTABLES_LOG}" >/dev/null ||
        fail \
            "temporary NAT chain deletion was not attempted"
}

test_tailscale_nat_topology_failure_cleanup() {
    local output
    local status

    setup_case

    export MOCK_IPTABLES_FAIL_MASQUERADE=1

    set +e

    output="$(
        check_tailscale_nat_topology 2>&1
    )"
    status=$?

    set -e

    assert_nonzero_status "${status}"

    assert_contains \
        "${output}" \
        "cannot add a marked MASQUERADE rule"

    assert_probe_state_clean
}

test_tailscale_nat_cleanup_rejects_success_without_progress() {
    local chain="ts-pf-nat-no-progress"
    local delete_attempts
    local status

    setup_case

    "${IPTABLES_BIN}" -t nat -N "${chain}"
    "${IPTABLES_BIN}" -t nat -I POSTROUTING 1 -j "${chain}"
    : >"${MOCK_IPTABLES_LOG}"

    export MOCK_IPTABLES_DELETE_NO_PROGRESS_SUCCESSES=20

    set +e
    cleanup_tailscale_nat_preflight "${chain}"
    status=$?
    set -e

    assert_nonzero_status "${status}"

    delete_attempts="$(
        grep -Ec -- \
            "-t nat -D (POSTROUTING|DEFAULT_POSTROUTING) -j ${chain}" \
            "${MOCK_IPTABLES_LOG}" ||
            true
    )"

    if [ "${delete_attempts}" -gt 1 ]; then
        fail \
            "NAT cleanup retried a successful no-progress deletion ${delete_attempts} times"
    fi

    if [ "$(sed -n '1p' "${MOCK_IPTABLES_LOG}")" != "-t nat -S" ]; then
        fail "NAT cleanup attempted deletion before checking hook existence"
    fi

    if [ "$(sed -n '2p' "${MOCK_IPTABLES_LOG}")" != \
        "-t nat -D DEFAULT_POSTROUTING -j ${chain}" ]; then
        fail "NAT cleanup did not delete the observed DSM hook"
    fi

    if [ "$(sed -n '3p' "${MOCK_IPTABLES_LOG}")" != "-t nat -S" ]; then
        fail "NAT cleanup did not verify state after reported deletion"
    fi
}

test_tailscale_nat_cleanup_checks_hook_before_delete() {
    local chain="ts-pf-nat-no-hook"

    setup_case

    "${IPTABLES_BIN}" -t nat -N "${chain}"
    : >"${MOCK_IPTABLES_LOG}"

    cleanup_tailscale_nat_preflight "${chain}"

    if grep -F -- \
        "-t nat -D " \
        "${MOCK_IPTABLES_LOG}" >/dev/null; then
        fail "NAT cleanup attempted deletion without an existing hook"
    fi

    if [ "$(sed -n '1p' "${MOCK_IPTABLES_LOG}")" != "-t nat -S" ]; then
        fail "NAT cleanup did not inspect hook existence before cleanup"
    fi

    assert_probe_state_clean
}

test_tailscale_nat_topology_no_progress_cleans_once() {
    local delete_attempts
    local output
    local status

    setup_case

    export MOCK_IPTABLES_DELETE_NO_PROGRESS_SUCCESSES=20

    set +e
    output="$(check_tailscale_nat_topology 2>&1)"
    status=$?
    set -e

    assert_nonzero_status "${status}"
    assert_contains \
        "${output}" \
        "cannot remove the temporary NAT preflight topology"

    delete_attempts="$(
        grep -Ec -- \
            '-t nat -D (POSTROUTING|DEFAULT_POSTROUTING) -j ts-pf-nat-' \
            "${MOCK_IPTABLES_LOG}" ||
            true
    )"

    if [ "${delete_attempts}" -ne 1 ]; then
        fail \
            "full NAT topology attempted ${delete_attempts} no-progress deletions, expected 1"
    fi
}

test_tailscale_nat_signal_cleans_temporary_state() {
    local probe_pid
    local status

    setup_case

    # Invoked indirectly by the sourced lifecycle definitions.
    # shellcheck disable=SC2329
    tailscale_nat_preflight_test_checkpoint() {
        kill -TERM "${BASHPID}"
    }

    (
        check_tailscale_nat_topology
    ) &
    probe_pid=$!

    set +e
    wait "${probe_pid}" >/dev/null 2>&1
    status=$?
    set -e

    assert_nonzero_status "${status}"

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
    "DSM table-wide chain detection" \
    test_dsm_table_wide_chain_detection

run_case \
    "Tailscale NAT topology succeeds and cleans up" \
    test_tailscale_nat_topology_success

run_case \
    "Tailscale NAT failure cleans up temporary state" \
    test_tailscale_nat_topology_failure_cleanup

run_case \
    "Tailscale NAT cleanup rejects success without progress" \
    test_tailscale_nat_cleanup_rejects_success_without_progress

run_case \
    "Tailscale NAT cleanup checks hook existence before deletion" \
    test_tailscale_nat_cleanup_checks_hook_before_delete

run_case \
    "Tailscale NAT topology performs one no-progress cleanup" \
    test_tailscale_nat_topology_no_progress_cleans_once

run_case \
    "Tailscale NAT signal cleans temporary state" \
    test_tailscale_nat_signal_cleans_temporary_state

printf '\nResults: %s passed, %s failed\n' \
    "${PASS_COUNT}" \
    "${FAIL_COUNT}"

if [ "${FAIL_COUNT}" -ne 0 ]; then
    exit 1
fi
