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
DEFINITIONS="${TEST_ROOT}/reconciler-definitions.sh"
RUNNER="${TEST_ROOT}/runner.sh"
READY_FILE="${TEST_ROOT}/ready"

RUNNER_PID=""
SLEEP_PID=""

fail() {
    printf 'ERROR: %s\n' "$*" >&2
    exit 1
}

cleanup() {
    if [ -n "${RUNNER_PID}" ] &&
        kill -0 "${RUNNER_PID}" >/dev/null 2>&1
    then
        kill -KILL "${RUNNER_PID}" >/dev/null 2>&1 ||
            true

        wait "${RUNNER_PID}" >/dev/null 2>&1 ||
            true
    fi

    if [ -n "${SLEEP_PID}" ] &&
        kill -0 "${SLEEP_PID}" >/dev/null 2>&1
    then
        kill -KILL "${SLEEP_PID}" >/dev/null 2>&1 ||
            true
    fi

    rm -rf -- "${TEST_ROOT}"
}

trap cleanup EXIT

grep -Eq \
    '^[[:space:]]*main[[:space:]]+"\$@"[[:space:]]*$' \
    "${RECONCILER}" ||
    fail 'reconciler main invocation was not found'

awk '
    /^[[:space:]]*main[[:space:]]+"\$@"[[:space:]]*$/ {
        exit
    }

    {
        print
    }
' "${RECONCILER}" >"${DEFINITIONS}"

/bin/cat >"${RUNNER}" <<'RUNNER_SH'
#!/bin/bash

set -euo pipefail

DEFINITIONS="$1"
READY_FILE="$2"

source "${DEFINITIONS}"

TEST_MODE=0
TEST_NO_SLEEP=0
STOP_REQUESTED=0
SLEEP_PID=""

trap handle_stop TERM INT

printf 'ready\n' >"${READY_FILE}"

sleep_for 30
RUNNER_SH

chmod 0755 "${RUNNER}"

mkdir -p \
    "${TEST_ROOT}/pkgvar" \
    "${TEST_ROOT}/pkgdest/bin"

printf 'TEST: SIGTERM interrupts one long reconciler sleep ... '

SYNOPKG_PKGNAME=Tailscale \
SYNOPKG_PKGVAR="${TEST_ROOT}/pkgvar" \
SYNOPKG_PKGDEST="${TEST_ROOT}/pkgdest" \
TAILSCALE_RECONCILER_TEST_MODE=0 \
TAILSCALE_RECONCILER_TEST_NO_SLEEP=0 \
bash "${RUNNER}" \
    "${DEFINITIONS}" \
    "${READY_FILE}" &

RUNNER_PID=$!

for ATTEMPT in $(seq 1 50)
do
    [ -e "${READY_FILE}" ] &&
        break

    sleep 0.1
done

[ -e "${READY_FILE}" ] ||
    fail 'test runner did not become ready'

CHILDREN_FILE="/proc/${RUNNER_PID}/task/${RUNNER_PID}/children"

for ATTEMPT in $(seq 1 50)
do
    if [ -r "${CHILDREN_FILE}" ]; then
        SLEEP_PID="$(
            awk '
                {
                    print $1
                    exit
                }
            ' "${CHILDREN_FILE}"
        )"
    fi

    [ -n "${SLEEP_PID}" ] &&
        break

    sleep 0.1
done

[ -n "${SLEEP_PID}" ] ||
    fail 'sleep child was not created'

case "${SLEEP_PID}" in
*[!0-9]*|'')
    fail "unexpected child PID value: ${SLEEP_PID}"
    ;;
esac

SLEEP_COMMAND="$(
    tr '\0' ' ' \
        <"/proc/${SLEEP_PID}/cmdline"
)"

case "${SLEEP_COMMAND}" in
*"sleep 30"*)
    ;;
*)
    fail "unexpected sleep child command: ${SLEEP_COMMAND}"
    ;;
esac

kill -TERM "${RUNNER_PID}"

EXITED=0

for ATTEMPT in $(seq 1 30)
do
    if ! kill -0 "${RUNNER_PID}" >/dev/null 2>&1; then
        EXITED=1
        break
    fi

    sleep 0.1
done

[ "${EXITED}" -eq 1 ] ||
    fail 'reconciler did not exit within three seconds of SIGTERM'

if ! wait "${RUNNER_PID}"; then
    fail 'reconciler runner returned a failure status after SIGTERM'
fi

RUNNER_PID=""

if kill -0 "${SLEEP_PID}" >/dev/null 2>&1; then
    fail "sleep child remains after reconciler exit: PID=${SLEEP_PID}"
fi

SLEEP_PID=""

printf 'PASS\n'
printf '\nResults: 1 passed, 0 failed\n'
