#!/usr/bin/env bash
set -u

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
MANIFEST="${REPO_ROOT}/release/manifest.yaml"
TEMP_ROOT="$(mktemp -d "${TMPDIR:-/tmp}/tailscale-build-candidate-role.XXXXXX")"

cleanup() {
  rm -rf -- "$TEMP_ROOT"
}
trap cleanup EXIT

# shellcheck source=scripts/release/common.sh
. "${REPO_ROOT}/scripts/release/common.sh"

OUTPUT_ROOT="${TEMP_ROOT}/output"
INSPECTOR="${TEMP_ROOT}/inspect-spk.sh"
INSPECTOR_LOG="${TEMP_ROOT}/inspector.log"

mkdir -p \
  "${OUTPUT_ROOT}/sideload" \
  "${OUTPUT_ROOT}/package-center-reference"

printf '%s\n' \
  '#!/usr/bin/env bash' \
  "printf '%s\\n' \"\$*\" >> \"\$INSPECTOR_LOG\"" \
  > "$INSPECTOR"
chmod +x "$INSPECTOR"

sideload_filename="$(release_manifest_get "$MANIFEST" package.artifacts.sideload.filename)"
package_center_filename="$(release_manifest_get "$MANIFEST" package.artifacts.package_center_reference.filename)"

touch \
  "${OUTPUT_ROOT}/sideload/${sideload_filename}" \
  "${OUTPUT_ROOT}/package-center-reference/${package_center_filename}"

INSPECTOR_LOG="$INSPECTOR_LOG" \
  release_inspect_candidate_artifacts \
  "$MANIFEST" \
  "$REPO_ROOT" \
  "$OUTPUT_ROOT" \
  "$INSPECTOR" || exit 1

expected_calls="$(
  cat << EOF
--control-worktree ${REPO_ROOT} --manifest ${MANIFEST} --artifact-role sideload --spk ${OUTPUT_ROOT}/sideload/${sideload_filename}
--control-worktree ${REPO_ROOT} --manifest ${MANIFEST} --artifact-role package-center-reference --spk ${OUTPUT_ROOT}/package-center-reference/${package_center_filename}
EOF
)"

if [ "$(cat "$INSPECTOR_LOG")" != "$expected_calls" ]; then
  echo "FAIL: canonical candidate artifacts did not reach the inspector with exact roles" >&2
  exit 1
fi

for argument_case in missing excess; do
  case "$argument_case" in
    missing)
      if argument_output="$(release_inspect_candidate_artifacts 2>&1)"; then
        argument_status=0
      else
        argument_status=$?
      fi
      ;;
    excess)
      if argument_output="$(
        release_inspect_candidate_artifacts \
          "$MANIFEST" \
          "$REPO_ROOT" \
          "$OUTPUT_ROOT" \
          "$INSPECTOR" \
          unexpected 2>&1
      )"; then
        argument_status=0
      else
        argument_status=$?
      fi
      ;;
  esac

  if [ "$argument_status" -ne 2 ]; then
    printf 'FAIL: %s argument case returned %s instead of 2\n' \
      "$argument_case" \
      "$argument_status" \
      >&2
    exit 1
  fi

  if ! grep -Fq \
    "candidate artifact inspection requires manifest, control worktree, output root, and inspector" \
    <<< "$argument_output"; then
    printf 'FAIL: %s argument case did not report the argument contract\n' \
      "$argument_case" \
      >&2
    exit 1
  fi
done

for case_name in unknown duplicate missing; do
  case "$case_name" in
    unknown)
      touch "${OUTPUT_ROOT}/unexpected.spk"
      ;;
    duplicate)
      touch "${OUTPUT_ROOT}/sideload/duplicate-${sideload_filename}"
      ;;
    missing)
      rm "${OUTPUT_ROOT}/sideload/${sideload_filename}"
      ;;
  esac

  : > "$INSPECTOR_LOG"

  if INSPECTOR_LOG="$INSPECTOR_LOG" \
    release_inspect_candidate_artifacts \
    "$MANIFEST" \
    "$REPO_ROOT" \
    "$OUTPUT_ROOT" \
    "$INSPECTOR"; then
    printf 'FAIL: %s artifact set was accepted\n' "$case_name" >&2
    exit 1
  fi

  if [ -s "$INSPECTOR_LOG" ]; then
    printf 'FAIL: %s artifact set invoked inspector after a non-canonical mapping\n' "$case_name" >&2
    exit 1
  fi

  case "$case_name" in
    unknown)
      rm "${OUTPUT_ROOT}/unexpected.spk"
      ;;
    duplicate)
      rm "${OUTPUT_ROOT}/sideload/duplicate-${sideload_filename}"
      ;;
    missing)
      touch "${OUTPUT_ROOT}/sideload/${sideload_filename}"
      ;;
  esac
done

manifest="caller-manifest"
control_worktree="caller-control-worktree"
output_root="caller-output-root"
spk_inspector="caller-spk-inspector"
artifact="caller-artifact"
role="caller-role"
path="caller-path"
expected_list="caller-expected-list"
observed_list="caller-observed-list"
expected_artifacts=("caller-expected-artifacts")
expected_paths=("caller-expected-paths")

: > "$INSPECTOR_LOG"
INSPECTOR_LOG="$INSPECTOR_LOG" \
  release_inspect_candidate_artifacts \
  "$MANIFEST" \
  "$REPO_ROOT" \
  "$OUTPUT_ROOT" \
  "$INSPECTOR" || exit 1

for preserved_variable in \
  manifest \
  control_worktree \
  output_root \
  spk_inspector \
  artifact \
  role \
  path \
  expected_list \
  observed_list; do
  expected_value="caller-${preserved_variable//_/-}"
  if [ "${!preserved_variable}" != "$expected_value" ]; then
    printf 'FAIL: candidate inspection overwrote caller variable %s\n' \
      "$preserved_variable" \
      >&2
    exit 1
  fi
done

if [ "${expected_artifacts[*]}" != "caller-expected-artifacts" ] ||
  [ "${expected_paths[*]}" != "caller-expected-paths" ]; then
  echo "FAIL: candidate inspection overwrote caller scratch arrays" >&2
  exit 1
fi

echo "PASS: candidate artifact roles map one-to-one and reject non-canonical output sets."
