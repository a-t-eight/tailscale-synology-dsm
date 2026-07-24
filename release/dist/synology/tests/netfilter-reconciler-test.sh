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

RECONCILER="${REPO_ROOT}/release/dist/synology/files/scripts/tailscale-netfilter-reconciler"

TEST_ROOT="$(mktemp -d)"
MOCK_BIN="${TEST_ROOT}/bin"

PASS_COUNT=0
FAIL_COUNT=0

cleanup() {
    rm -rf -- "${TEST_ROOT}"
}

trap cleanup EXIT

mkdir -p "${MOCK_BIN}"


fail() {
    printf 'ERROR: %s\n' "$*" >&2
    exit 1
}


assert_contains() {
    local file="$1"
    local wanted="$2"

    grep -Fq -- "${wanted}" "${file}" ||
        fail "${file} does not contain: ${wanted}"
}


assert_not_contains() {
    local file="$1"
    local unwanted="$2"

    if grep -Fq -- "${unwanted}" "${file}"; then
        fail "${file} unexpectedly contains: ${unwanted}"
    fi
}


command cat >"${MOCK_BIN}/tailscale" <<'MOCK'
#!/bin/bash

set -u

STATE="${MOCK_STATE:?}"
COMMAND_LOG="${STATE}/commands.log"

args=" $* "

case "${args}" in
*" debug prefs "*)
    mode="$(command cat "${STATE}/netfilter-mode")"
    want="$(command cat "${STATE}/want-running")"

    printf '{\n'
    printf '  "WantRunning": %s,\n' "${want}"
    printf '  "NetfilterMode": %s,\n' "${mode}"
    printf '  "Padding": "'
    printf '%262144s' '' | tr ' ' x
    printf '"\n'
    printf '}\n'
    ;;

*" status --json "*)
    backend="$(command cat "${STATE}/backend-state")"

    printf '{\n'
    printf '  "BackendState": "%s"\n' "${backend}"
    printf '}\n'
    ;;

*" set --netfilter-mode=off "*)
    printf '%s\n' \
        'set --netfilter-mode=off' \
        >>"${COMMAND_LOG}"

    printf '%s\n' \
        0 \
        >"${STATE}/netfilter-mode"

    rm -f -- "${STATE}/hooks-complete"
    ;;

*" set --netfilter-mode=on "*)
    printf '%s\n' \
        'set --netfilter-mode=on' \
        >>"${COMMAND_LOG}"

    printf '%s\n' \
        2 \
        >"${STATE}/netfilter-mode"

    touch "${STATE}/hooks-complete"
    ;;

*)
    printf 'unsupported mock tailscale invocation: %s\n' \
        "$*" >&2
    exit 1
    ;;
esac
MOCK

chmod 0755 \
  "${MOCK_BIN}/tailscale"


command cat >"${MOCK_BIN}/iptables" <<'MOCK'
#!/bin/bash

set -u

STATE="${MOCK_STATE:?}"

case " $* " in
*" -t filter -S "*)
    exit 0
    ;;

*" -t filter -C INPUT -j ts-input "*|\
*" -t filter -C FORWARD -j ts-forward "*|\
*" -t nat -C POSTROUTING -j ts-postrouting "*)
    [ -e "${STATE}/hooks-complete" ]
    exit $?
    ;;

*)
    printf 'unsupported mock iptables invocation: %s\n' \
        "$*" >&2
    exit 1
    ;;
esac
MOCK

chmod 0755 \
  "${MOCK_BIN}/iptables"

ln -s \
  "${MOCK_BIN}/iptables" \
  "${MOCK_BIN}/ip6tables"


setup_case() {
    CASE_NAME="$1"
    CASE_ROOT="${TEST_ROOT}/${CASE_NAME}"
    STATE="${CASE_ROOT}/state"
    OUTPUT="${CASE_ROOT}/output"

    rm -rf -- "${CASE_ROOT}"

    mkdir -p \
        "${STATE}/pkgvar"

    : >"${STATE}/commands.log"

    printf '%s\n' true >"${STATE}/want-running"
    printf '%s\n' 2 >"${STATE}/netfilter-mode"
    printf '%s\n' Running >"${STATE}/backend-state"
}


run_reconciler() {
    env \
        PATH="${MOCK_BIN}:/usr/bin:/bin" \
        MOCK_STATE="${STATE}" \
        TAILSCALE_RECONCILER_PKGVAR="${STATE}/pkgvar" \
        TAILSCALE_RECONCILER_TAILSCALE_BIN="${MOCK_BIN}/tailscale" \
        TAILSCALE_RECONCILER_SOCKET_FILE="${STATE}/tailscaled.sock" \
        TAILSCALE_RECONCILER_IPTABLES_BIN="${MOCK_BIN}/iptables" \
        TAILSCALE_RECONCILER_IP6TABLES_BIN="${MOCK_BIN}/ip6tables" \
        TAILSCALE_RECONCILER_PID_FILE="${STATE}/pkgvar/reconciler.pid" \
        TAILSCALE_RECONCILER_PENDING_FILE="${STATE}/pkgvar/repair.pending" \
        TAILSCALE_SYNOLOGY_TEST_MODE=1 \
        TAILSCALE_SYNOLOGY_RECONCILER_TEST_MAX_ITERATIONS=1 \
        TAILSCALE_SYNOLOGY_RECONCILER_TEST_NO_SLEEP=1 \
        bash "${RECONCILER}" \
        >"${OUTPUT}" \
        2>&1

    assert_not_contains \
        "${OUTPUT}" \
        'Broken pipe'
}


printf 'TEST: complete hooks do not trigger repair ... '

setup_case complete
touch "${STATE}/hooks-complete"

run_reconciler

assert_not_contains \
    "${STATE}/commands.log" \
    'set --netfilter-mode='

printf 'PASS\n'
PASS_COUNT=$((PASS_COUNT + 1))


printf 'TEST: missing hooks trigger one off-on reconstruction ... '

setup_case missing

run_reconciler

assert_contains \
    "${STATE}/commands.log" \
    'set --netfilter-mode=off'

assert_contains \
    "${STATE}/commands.log" \
    'set --netfilter-mode=on'

[ -e "${STATE}/hooks-complete" ] ||
    fail "repair did not restore hooks"

[ ! -e "${STATE}/pkgvar/repair.pending" ] ||
    fail "successful repair left a pending marker"

printf 'PASS\n'
PASS_COUNT=$((PASS_COUNT + 1))


printf 'TEST: netfilter off is not overridden ... '

setup_case disabled
printf '%s\n' 0 >"${STATE}/netfilter-mode"

run_reconciler

assert_not_contains \
    "${STATE}/commands.log" \
    'set --netfilter-mode='

printf 'PASS\n'
PASS_COUNT=$((PASS_COUNT + 1))


printf 'TEST: non-running backend is not repaired ... '

setup_case backend-wait
printf '%s\n' Starting >"${STATE}/backend-state"

run_reconciler

assert_not_contains \
    "${STATE}/commands.log" \
    'set --netfilter-mode='

printf 'PASS\n'
PASS_COUNT=$((PASS_COUNT + 1))


printf 'TEST: interrupted repair restores netfilter mode on ... '

setup_case pending
printf '%s\n' 0 >"${STATE}/netfilter-mode"
touch "${STATE}/pkgvar/repair.pending"

run_reconciler

assert_contains \
    "${STATE}/commands.log" \
    'set --netfilter-mode=on'

assert_not_contains \
    "${STATE}/commands.log" \
    'set --netfilter-mode=off'

[ -e "${STATE}/hooks-complete" ] ||
    fail "pending repair did not restore hooks"

[ ! -e "${STATE}/pkgvar/repair.pending" ] ||
    fail "pending repair marker was not removed"

printf 'PASS\n'
PASS_COUNT=$((PASS_COUNT + 1))


printf '\nResults: %d passed, %d failed\n' \
    "${PASS_COUNT}" \
    "${FAIL_COUNT}"
