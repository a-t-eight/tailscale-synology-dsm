#!/usr/bin/env bash
set -u

export PATH="/usr/syno/bin:/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin"

PACKAGE_NAME="Tailscale"
PACKAGE_ROOT="/var/packages/Tailscale"

EXPECTED_COMMIT=""
EXPECTED_PACKAGE_VERSION=""
EXPECTED_NODE_ID=""
EXPECTED_IPV4=""
EXPECTED_STATE_SHA256=""
CANDIDATE_SPK=""
EXPECTED_SPK_SHA256=""

WAIT_ATTEMPTS=60
WAIT_SECONDS=1

FAILURES=0
TEMP_ROOT=""
EXPECTED_PREFS=()

usage() {
  /usr/bin/printf '%s\n' \
    "Usage:" \
    "  sudo $0 [options]" \
    "" \
    "Options:" \
    "  --package-root PATH" \
    "  --expected-commit SHA" \
    "  --expected-package-version VERSION" \
    "  --expected-node-id ID" \
    "  --expected-ipv4 ADDRESS" \
    "  --expected-state-sha256 SHA256" \
    "  --candidate-spk PATH" \
    "  --expected-spk-sha256 SHA256" \
    "  --expect-pref TEXT" \
    "      Require TEXT to occur in tailscale debug prefs; repeatable." \
    "  --wait-attempts NUMBER" \
    "  --wait-seconds NUMBER" \
    "  --help"
}

pass_check() {
  /usr/bin/printf 'PASS: %s\n' \
    "$1"
}

fail_check() {
  /usr/bin/printf 'FAIL: %s\n' \
    "$1"

  FAILURES=$((FAILURES + 1))
}

# shellcheck disable=SC2329
cleanup() {
  if [ -n "$TEMP_ROOT" ] && [ -d "$TEMP_ROOT" ]; then
    /bin/rm \
      -rf \
      "$TEMP_ROOT"
  fi
}

numeric_value() {
  case "$1" in
    ''|*[!0-9]*)
      return 1
      ;;
    *)
      return 0
      ;;
  esac
}

read_pid_file() {
  local pid_file="$1"

  [ -r "$pid_file" ] ||
  return 1

  /usr/bin/tr \
    -cd \
    '0-9' \
    <"$pid_file"
}

pid_file_is_running() {
  local pid_file="$1"
  local pid=""

  pid="$(
    read_pid_file \
      "$pid_file"
  )" ||
  return 1

  [ -n "$pid" ] ||
  return 1

  [ -d "/proc/${pid}" ] ||
  return 1

  /bin/kill \
    -0 \
    "$pid" \
    2>/dev/null
}

check_pid_file() {
  local description="$1"
  local pid_file="$2"
  local expected_command="$3"
  local expected_uid="$4"

  local pid=""
  local command_line=""
  local process_uid=""

  if [ ! -r "$pid_file" ]; then
    fail_check "${description} PID file is missing: ${pid_file}"

    return
  fi

  pid="$(
    read_pid_file \
      "$pid_file"
  )"

  if [ -z "$pid" ]; then
    fail_check "${description} PID file is not numeric"

    return
  fi

  if [ ! -d "/proc/${pid}" ]; then
    fail_check "${description} process directory is missing: /proc/${pid}"

    return
  fi

  if ! /bin/kill \
    -0 \
    "$pid" \
    2>/dev/null
  then
    fail_check "${description} PID ${pid} is not running"

    return
  fi

  command_line="$(
    /usr/bin/tr \
      '\000' \
      ' ' \
      <"/proc/${pid}/cmdline"
  )"

  if /usr/bin/printf '%s\n' \
    "$command_line" |
    /bin/grep \
      -Fq \
      "$expected_command"
  then
    pass_check "${description} command line matches"
  else
    fail_check "${description} command line is unexpected: ${command_line}"
  fi

  process_uid="$(
    /usr/bin/awk '
      $1 == "Uid:" {
        print $2
        exit
      }
    ' \
      "/proc/${pid}/status"
  )"

  if [ "$process_uid" = "$expected_uid" ]; then
    pass_check "${description} runs as UID ${expected_uid}"
  else
    fail_check "${description} runs as UID ${process_uid:-unknown}, expected ${expected_uid}"
  fi
}

extract_self_id() {
  /usr/bin/awk '
    /"Self":[[:space:]]*\{/ {
      in_self = 1
      next
    }

    in_self && /"ID":[[:space:]]*"/ {
      value = $0
      sub(/^.*"ID":[[:space:]]*"/, "", value)
      sub(/".*$/, "", value)
      print value
      exit
    }
  ' \
    "$1"
}

while [ "$#" -gt 0 ]
do
  case "$1" in
    --package-root)
      [ "$#" -ge 2 ] || {
        usage >&2
        exit 2
      }

      PACKAGE_ROOT="$2"
      shift 2
      ;;

    --expected-commit)
      [ "$#" -ge 2 ] || {
        usage >&2
        exit 2
      }

      EXPECTED_COMMIT="$2"
      shift 2
      ;;

    --expected-package-version)
      [ "$#" -ge 2 ] || {
        usage >&2
        exit 2
      }

      EXPECTED_PACKAGE_VERSION="$2"
      shift 2
      ;;

    --expected-node-id)
      [ "$#" -ge 2 ] || {
        usage >&2
        exit 2
      }

      EXPECTED_NODE_ID="$2"
      shift 2
      ;;

    --expected-ipv4)
      [ "$#" -ge 2 ] || {
        usage >&2
        exit 2
      }

      EXPECTED_IPV4="$2"
      shift 2
      ;;

    --expected-state-sha256)
      [ "$#" -ge 2 ] || {
        usage >&2
        exit 2
      }

      EXPECTED_STATE_SHA256="$2"
      shift 2
      ;;

    --candidate-spk)
      [ "$#" -ge 2 ] || {
        usage >&2
        exit 2
      }

      CANDIDATE_SPK="$2"
      shift 2
      ;;

    --expected-spk-sha256)
      [ "$#" -ge 2 ] || {
        usage >&2
        exit 2
      }

      EXPECTED_SPK_SHA256="$2"
      shift 2
      ;;

    --expect-pref)
      [ "$#" -ge 2 ] || {
        usage >&2
        exit 2
      }

      EXPECTED_PREFS+=("$2")
      shift 2
      ;;

    --wait-attempts)
      [ "$#" -ge 2 ] || {
        usage >&2
        exit 2
      }

      WAIT_ATTEMPTS="$2"
      shift 2
      ;;

    --wait-seconds)
      [ "$#" -ge 2 ] || {
        usage >&2
        exit 2
      }

      WAIT_SECONDS="$2"
      shift 2
      ;;

    --help)
      usage
      exit 0
      ;;

    *)
      /usr/bin/printf 'Unknown option: %s\n' \
        "$1" \
        >&2

      usage >&2
      exit 2
      ;;
  esac
done

if [ "$(/usr/bin/id -u)" -ne 0 ]; then
  echo "STOP: run this validator as root."

  exit 1
fi

if ! numeric_value "$WAIT_ATTEMPTS" || [ "$WAIT_ATTEMPTS" -eq 0 ]; then
  echo "STOP: --wait-attempts must be a positive integer."

  exit 2
fi

if ! numeric_value "$WAIT_SECONDS"; then
  echo "STOP: --wait-seconds must be a non-negative integer."

  exit 2
fi

PACKAGE_VAR="${PACKAGE_ROOT}/var"
PACKAGE_TARGET="${PACKAGE_ROOT}/target"
PACKAGE_CONF="${PACKAGE_ROOT}/conf"

BOOTSTRAP="${PACKAGE_ROOT}/scripts/tailscale-synology-bootstrap"
TAILSCALE="${PACKAGE_TARGET}/bin/tailscale"
TAILSCALED="${PACKAGE_TARGET}/bin/tailscaled"

TAILSCALED_PID_FILE="${PACKAGE_VAR}/tailscaled.pid"
RECONCILER_PID_FILE="${PACKAGE_VAR}/tailscale-netfilter-reconciler.pid"
SOCKET_FILE="${PACKAGE_VAR}/tailscaled.sock"
STATE_FILE="${PACKAGE_VAR}/tailscaled.state"

TEMP_ROOT="$(
  /bin/mktemp \
    -d \
    "/tmp/tailscale-synology-runtime-validator.XXXXXX"
)"

trap cleanup EXIT

STATUS_JSON="${TEMP_ROOT}/status.json"
PREFS_JSON="${TEMP_ROOT}/prefs.json"

printf '=== Required paths ===\n'

for REQUIRED_PATH in \
  "$PACKAGE_ROOT" \
  "$PACKAGE_VAR" \
  "$PACKAGE_TARGET" \
  "$PACKAGE_CONF" \
  "$BOOTSTRAP" \
  "$TAILSCALE" \
  "$TAILSCALED" \
  "$STATE_FILE"
do
  if [ -e "$REQUIRED_PATH" ]; then
    pass_check "present: ${REQUIRED_PATH}"
  else
    fail_check "missing required path: ${REQUIRED_PATH}"
  fi
done

if [ "$FAILURES" -ne 0 ]; then
  printf '\nValidation failures: %s\n' \
    "$FAILURES"

  exit 1
fi

printf '\n=== Wait for runtime ===\n'

ATTEMPT=1
RUNTIME_READY=0

while [ "$ATTEMPT" -le "$WAIT_ATTEMPTS" ]
do
  if \
    pid_file_is_running "$TAILSCALED_PID_FILE" &&
    [ -S "$SOCKET_FILE" ] &&
    "$TAILSCALE" \
      status \
      >/dev/null \
      2>&1
  then
    RUNTIME_READY=1
    break
  fi

  if [ "$ATTEMPT" -lt "$WAIT_ATTEMPTS" ]; then
    /bin/sleep \
      "$WAIT_SECONDS"
  fi

  ATTEMPT=$((ATTEMPT + 1))
done

if [ "$RUNTIME_READY" -eq 1 ]; then
  pass_check "tailscaled PID, LocalAPI socket and status command are operational"
else
  fail_check "runtime did not become operational after ${WAIT_ATTEMPTS} attempts"
fi

printf '\n=== Bootstrap state ===\n'

BOOTSTRAP_STATUS="$(
  "$BOOTSTRAP" \
    status \
    2>&1
)"

printf '%s\n' \
  "$BOOTSTRAP_STATUS"

for EXPECTED_STATUS in \
  'Privilege mode: root' \
  'Bootstrap state: current' \
  'Runtime: running, UID=0'
do
  if /usr/bin/printf '%s\n' \
    "$BOOTSTRAP_STATUS" |
    /bin/grep \
      -Fq \
      "$EXPECTED_STATUS"
  then
    pass_check "$EXPECTED_STATUS"
  else
    fail_check "bootstrap status missing: ${EXPECTED_STATUS}"
  fi
done

printf '\n=== Installed package identity ===\n'

VERSION_OUTPUT="$(
  "$TAILSCALE" \
    version \
    2>&1
)"

printf '%s\n' \
  "$VERSION_OUTPUT"

if [ -n "$EXPECTED_COMMIT" ]; then
  if /usr/bin/printf '%s\n' \
    "$VERSION_OUTPUT" |
    /bin/grep \
      -Fq \
      "$EXPECTED_COMMIT"
  then
    pass_check "installed binary identifies expected commit ${EXPECTED_COMMIT}"
  else
    fail_check "installed binary does not identify expected commit ${EXPECTED_COMMIT}"
  fi
fi

PACKAGE_VERSION_OUTPUT="$(
  /usr/syno/bin/synopkg \
    version \
    "$PACKAGE_NAME" \
    2>&1
)"

printf 'DSM package version: %s\n' \
  "$PACKAGE_VERSION_OUTPUT"

if [ -n "$EXPECTED_PACKAGE_VERSION" ]; then
  if [ "$PACKAGE_VERSION_OUTPUT" = "$EXPECTED_PACKAGE_VERSION" ]; then
    pass_check "DSM package version matches ${EXPECTED_PACKAGE_VERSION}"
  else
    fail_check "DSM package version is ${PACKAGE_VERSION_OUTPUT}, expected ${EXPECTED_PACKAGE_VERSION}"
  fi
fi

PACKAGE_STATUS="$(
  /usr/syno/bin/synopkg \
    status \
    "$PACKAGE_NAME" \
    2>&1
)"

if /usr/bin/printf '%s\n' \
  "$PACKAGE_STATUS" |
  /bin/grep \
    -Fq \
    '"status":"running"'
then
  pass_check "DSM reports the package running"
else
  fail_check "DSM does not report the package running"
fi

printf '\n=== Candidate SPK integrity ===\n'

if [ -n "$CANDIDATE_SPK" ] || [ -n "$EXPECTED_SPK_SHA256" ]; then
  if [ -z "$CANDIDATE_SPK" ] || [ -z "$EXPECTED_SPK_SHA256" ]; then
    fail_check "--candidate-spk and --expected-spk-sha256 must be supplied together"
  elif [ ! -f "$CANDIDATE_SPK" ]; then
    fail_check "candidate SPK is missing: ${CANDIDATE_SPK}"
  else
    ACTUAL_SPK_SHA256="$(
      /usr/bin/sha256sum \
        "$CANDIDATE_SPK" |
      /usr/bin/awk \
        '{print $1}'
    )"

    if [ "$ACTUAL_SPK_SHA256" = "$EXPECTED_SPK_SHA256" ]; then
      pass_check "candidate SPK checksum matches"
    else
      fail_check "candidate SPK checksum mismatch"
    fi
  fi
else
  echo "NOTICE: candidate SPK checksum validation was not requested."
fi

printf '\n=== Runtime identity and preferences ===\n'

if "$TAILSCALE" \
  status \
  --json \
  >"$STATUS_JSON" \
  2>&1
then
  pass_check "status JSON captured"
else
  fail_check "status JSON request failed"
fi

if "$TAILSCALE" \
  debug \
  prefs \
  >"$PREFS_JSON" \
  2>&1
then
  pass_check "preferences captured"
else
  fail_check "preferences request failed"
fi

TAILSCALE_IPV4="$(
  "$TAILSCALE" \
    ip \
    -4 \
    2>/dev/null |
  /bin/sed \
    -n \
    '1p'
)"

SELF_ID="$(
  extract_self_id \
    "$STATUS_JSON"
)"

if [ -n "$EXPECTED_NODE_ID" ]; then
  if [ "$SELF_ID" = "$EXPECTED_NODE_ID" ]; then
    pass_check "node identity matches"
  else
    fail_check "node identity is ${SELF_ID:-unavailable}, expected ${EXPECTED_NODE_ID}"
  fi
fi

if [ -n "$EXPECTED_IPV4" ]; then
  if [ "$TAILSCALE_IPV4" = "$EXPECTED_IPV4" ]; then
    pass_check "Tailscale IPv4 matches ${EXPECTED_IPV4}"
  else
    fail_check "Tailscale IPv4 is ${TAILSCALE_IPV4:-unavailable}, expected ${EXPECTED_IPV4}"
  fi
fi

if [ "${#EXPECTED_PREFS[@]}" -eq 0 ]; then
  echo "NOTICE: no additional preference assertions requested."
else
  for EXPECTED_PREF in "${EXPECTED_PREFS[@]}"
  do
    if /bin/grep \
      -Fq \
      "$EXPECTED_PREF" \
      "$PREFS_JSON"
    then
      pass_check "preference retained: ${EXPECTED_PREF}"
    else
      fail_check "expected preference missing: ${EXPECTED_PREF}"
    fi
  done
fi

printf '\n=== Persistent state ===\n'

if [ -f "$STATE_FILE" ]; then
  pass_check "persistent state file exists"
else
  fail_check "persistent state file is missing"
fi

if [ -n "$EXPECTED_STATE_SHA256" ] && [ -f "$STATE_FILE" ]; then
  ACTUAL_STATE_SHA256="$(
    /usr/bin/sha256sum \
      "$STATE_FILE" |
    /usr/bin/awk \
      '{print $1}'
  )"

  if [ "$ACTUAL_STATE_SHA256" = "$EXPECTED_STATE_SHA256" ]; then
    pass_check "persistent state checksum matches"
  else
    fail_check "persistent state checksum mismatch"
  fi
fi

printf '\n=== Process validation ===\n'

check_pid_file \
  "tailscaled" \
  "$TAILSCALED_PID_FILE" \
  "${PACKAGE_TARGET}/bin/tailscaled" \
  "0"

check_pid_file \
  "netfilter reconciler" \
  "$RECONCILER_PID_FILE" \
  "${PACKAGE_ROOT}/scripts/tailscale-netfilter-reconciler" \
  "0"

printf '\n=== Netfilter validation ===\n'

for CHAIN_SPEC in \
  'filter ts-input' \
  'filter ts-forward' \
  'nat ts-postrouting'
do
  TABLE="${CHAIN_SPEC%% *}"
  CHAIN="${CHAIN_SPEC#* }"

  if /sbin/iptables \
    -t \
    "$TABLE" \
    -S \
    "$CHAIN" \
    >/dev/null \
    2>&1
  then
    pass_check "${TABLE}/${CHAIN} exists"
  else
    fail_check "${TABLE}/${CHAIN} is missing"
  fi
done

printf '\n=== Result ===\n'

printf 'Validation failures: %s\n' \
  "$FAILURES"

if [ "$FAILURES" -eq 0 ]; then
  echo "PASS: Synology Tailscale runtime acceptance completed."
  exit 0
fi

echo "STOP: Synology Tailscale runtime acceptance failed."
exit 1
