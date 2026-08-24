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

cleanup() {
    rm -rf -- "${TEST_ROOT}"
}

trap cleanup EXIT

DEFINITIONS="${TEST_ROOT}/start-stop-definitions.sh"
STDOUT_FILE="${TEST_ROOT}/stdout"
STDERR_FILE="${TEST_ROOT}/stderr"

mkdir -p \
    "${TEST_ROOT}/package/scripts" \
    "${TEST_ROOT}/proc" \
    "${TEST_ROOT}/pkgvar" \
    "${TEST_ROOT}/pkgdest/bin"

cat >"${TEST_ROOT}/pkgdest/bin/tailscaled" <<'TAILSCALED'
#!/bin/sh
exit 0
TAILSCALED

cat >"${TEST_ROOT}/unrelated" <<'UNRELATED'
#!/bin/sh
exit 0
UNRELATED

cat >"${TEST_ROOT}/package/scripts/tailscale-netfilter-reconciler" <<'RECONCILER'
#!/bin/bash
exit 0
RECONCILER

chmod 0755 \
    "${TEST_ROOT}/pkgdest/bin/tailscaled" \
    "${TEST_ROOT}/unrelated" \
    "${TEST_ROOT}/package/scripts/tailscale-netfilter-reconciler"

awk '
    /^case \$1 in/ {
        exit
    }

    {
        print
    }
' "${START_STOP_SOURCE}" >"${DEFINITIONS}"

set +e

# The single-quoted script is intentionally expanded by the nested Bash.
# shellcheck disable=SC2016
env \
    SYNOPKG_DSM_VERSION_MAJOR=7 \
    SYNOPKG_PKGVAR="${TEST_ROOT}/pkgvar" \
    SYNOPKG_PKGDEST="${TEST_ROOT}/pkgdest" \
    SYNOPKG_PKGNAME=Tailscale \
    TAILSCALE_SYNOLOGY_PACKAGE_ROOT="${TEST_ROOT}/package" \
    TAILSCALE_SYNOLOGY_PROC_ROOT="${TEST_ROOT}/proc" \
    TAILSCALE_SYNOLOGY_TEST_MODE=1 \
    bash -u -c '
        source "$1"

        printf "%s\n" \
            "$NETFILTER_LOCALAPI_ATTEMPTS" \
            "$TUN_WAIT_ATTEMPTS" \
            "$TUN_WAIT_SECONDS" \
            "$RECONCILER_START_ATTEMPTS" \
            "$BOOTSTRAP_COMMAND"

        mkdir -p "$PROC_ROOT/$$"

        printf "%s\n" "$$" >"$PID_FILE"
        ln -sfn "$2/unrelated" "$PROC_ROOT/$$/exe"

        if daemon_status; then
            printf "ERROR: unrelated process accepted as tailscaled\n" >&2
            exit 41
        fi

        printf "%s\n" "$$" >"$PID_FILE"
        ln -sfn "$SYNOPKG_PKGDEST/bin/tailscaled" "$PROC_ROOT/$$/exe"

        if ! daemon_status; then
            printf "ERROR: matching tailscaled process was rejected\n" >&2
            exit 42
        fi

        printf "%s\n" "$$" >"$RECONCILER_PID_FILE"
        printf "%s\0" /bin/bash "$2/unrelated" >"$PROC_ROOT/$$/cmdline"

        if reconciler_status; then
            printf "ERROR: unrelated process accepted as reconciler\n" >&2
            exit 43
        fi

        printf "%s\n" "$$" >"$RECONCILER_PID_FILE"
        printf "%s\0" /bin/bash "$RECONCILER_SCRIPT" >"$PROC_ROOT/$$/cmdline"

        if ! reconciler_status; then
            printf "ERROR: matching reconciler process was rejected\n" >&2
            exit 44
        fi

        printf "identity-checks-pass\n"

        PROC_ROOT=/proc
        RECONCILER_START_ATTEMPTS=2

        printf "%s\n" \
            "#!/bin/bash" \
            "sleep 0.2" \
            "exit 0" \
            >"$RECONCILER_SCRIPT"

        secure_root_path() {
            return 0
        }

        if start_reconciler 2>/dev/null; then
            printf "ERROR: short-lived reconciler passed startup stability check\n" >&2
            exit 45
        fi

        printf "stability-check-pass\n"

        daemon_status() {
            return 1
        }

        bootstrap_is_current() {
            return 1
        }

        service_status >/dev/null 2>&1
        bootstrap_pending_status=$?

        if [ "${bootstrap_pending_status}" -ne 0 ]; then
            printf "ERROR: bootstrap-pending service status returned %s, expected 0\n" \
                "${bootstrap_pending_status}" >&2
            exit 46
        fi

        printf "bootstrap-pending-status-check-pass\n"

        daemon_status() {
            return 0
        }

        reconciler_status() {
            return 1
        }

        service_status >/dev/null 2>&1
        degraded_status=$?

        if [ "${degraded_status}" -ne 1 ]; then
            printf "ERROR: degraded service status returned %s, expected 1\n" \
                "${degraded_status}" >&2
            exit 47
        fi

        printf "degraded-status-check-pass\n"
    ' bash "${DEFINITIONS}" \
    "${TEST_ROOT}" \
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
    10 \
    1 \
    10 \
    "sudo ${TEST_ROOT}/package/scripts/tailscale-synology-bootstrap install" \
    identity-checks-pass \
    stability-check-pass \
    bootstrap-pending-status-check-pass \
    degraded-status-check-pass \
    >"${EXPECTED}"

if ! cmp -s \
    "${EXPECTED}" \
    "${STDOUT_FILE}"
then
    printf 'ERROR: unexpected package startup defaults\n' >&2

    printf 'Expected:\n' >&2
    sed -n '1,20p' "${EXPECTED}" >&2

    printf 'Actual:\n' >&2
    sed -n '1,20p' "${STDOUT_FILE}" >&2

    exit 1
fi

printf 'TEST: start-stop definitions load cleanly ... PASS\n'
