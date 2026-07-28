#!/usr/bin/env bash
set -u

SCRIPT_DIR="$(
  cd \
    "$(dirname "${BASH_SOURCE[0]}")" &&
    pwd
)"

# shellcheck source=common.sh
. "${SCRIPT_DIR}/common.sh"

CONTROL_WORKTREE="$(
  cd \
    "${SCRIPT_DIR}/../.." &&
    pwd
)"
SOURCE_REPO=""
MANIFEST=""
FAILURES=0

usage() {
  cat << 'USAGE'
Usage:
  bash scripts/release/audit-inputs.sh \
    [--control-worktree PATH] \
    --source-repo PATH \
    [--manifest PATH]

This command validates release identity and local prerequisites without
creating branches, worktrees, commits, packages or evidence.
USAGE
}

while [ "$#" -gt 0 ]; do
  case "$1" in
    --control-worktree)
      CONTROL_WORKTREE="$2"
      shift
      ;;
    --source-repo)
      SOURCE_REPO="$2"
      shift
      ;;
    --manifest)
      MANIFEST="$2"
      shift
      ;;
    --help | -h)
      usage
      exit 0
      ;;
    *)
      release_fail "unsupported option: $1"
      usage >&2
      exit 2
      ;;
  esac
  shift
done

if [ -z "$SOURCE_REPO" ]; then
  release_fail "--source-repo is required"
  usage >&2
  exit 2
fi

if [ -z "$MANIFEST" ]; then
  MANIFEST="${CONTROL_WORKTREE}/release/manifest.yaml"
fi

for command_name in git python3 sha256sum; do
  if ! release_require_command "$command_name"; then
    FAILURES=$((FAILURES + 1))
  fi
done

if ! release_require_worktree "$CONTROL_WORKTREE"; then
  FAILURES=$((FAILURES + 1))
fi

if ! release_require_worktree "$SOURCE_REPO"; then
  FAILURES=$((FAILURES + 1))
fi

if [ ! -s "$MANIFEST" ]; then
  release_fail "release manifest is missing or empty: ${MANIFEST}"
  FAILURES=$((FAILURES + 1))
fi

if [ "$FAILURES" -ne 0 ]; then
  printf 'Audit failures: %s\n' "$FAILURES"
  echo "STOP: release input audit did not begin."
  exit 1
fi

printf '=== Release manifest ===\n'

if ! release_validate_manifest "$MANIFEST"; then
  echo "STOP: release manifest validation failed."
  exit 1
fi

CONTROL_BRANCH="$(release_manifest_get "$MANIFEST" control.branch)"
CONTROL_BASELINE_COMMIT="$(release_manifest_get "$MANIFEST" control.governance_baseline_commit)"
UPSTREAM_REPOSITORY="$(
  release_manifest_get "$MANIFEST" upstream.repository
)"
UPSTREAM_TAG="$(release_manifest_get "$MANIFEST" upstream.tag)"
UPSTREAM_COMMIT="$(release_manifest_get "$MANIFEST" upstream.commit)"
RELEASE_COMMIT="$(release_manifest_get "$MANIFEST" downstream.release_commit)"
RELEASE_TREE="$(release_manifest_get "$MANIFEST" downstream.release_tree)"
PATCH_RELATIVE="$(release_manifest_get "$MANIFEST" paths.patch_series)"
BUILD_RELATIVE="$(release_manifest_get "$MANIFEST" paths.build_entrypoint)"
EVIDENCE_RELATIVE="$(release_manifest_get "$MANIFEST" paths.evidence)"
RECORD_RELATIVE="$(release_manifest_get "$MANIFEST" paths.release_record)"

PATCH_ROOT="$(release_resolve_path "$CONTROL_WORKTREE" "$PATCH_RELATIVE")"
BUILD_ENTRYPOINT="$(release_resolve_path "$SOURCE_REPO" "$BUILD_RELATIVE")"
EVIDENCE_ROOT="$(release_resolve_path "$CONTROL_WORKTREE" "$EVIDENCE_RELATIVE")"
RELEASE_RECORD="$(release_resolve_path "$CONTROL_WORKTREE" "$RECORD_RELATIVE")"

printf 'Control worktree: %s\n' "$CONTROL_WORKTREE"
printf 'Source repository: %s\n' "$SOURCE_REPO"
printf 'Control branch:    %s\n' "$CONTROL_BRANCH"
printf 'Control baseline:  %s\n' "$CONTROL_BASELINE_COMMIT"
printf 'Upstream repo:     %s\n' "$UPSTREAM_REPOSITORY"
printf 'Upstream tag:      %s\n' "$UPSTREAM_TAG"
printf 'Upstream commit:   %s\n' "$UPSTREAM_COMMIT"
printf 'Release commit:    %s\n' "$RELEASE_COMMIT"
printf 'Release tree:      %s\n' "$RELEASE_TREE"
printf 'Patch root:        %s\n' "$PATCH_ROOT"
printf 'Build entrypoint:  %s\n' "$BUILD_ENTRYPOINT"
printf 'Evidence root:     %s\n' "$EVIDENCE_ROOT"

printf '\n=== Worktree state ===\n'

if release_require_clean_worktree "$SOURCE_REPO"; then
  release_pass "source repository is clean."
else
  FAILURES=$((FAILURES + 1))
fi

CONTROL_HEAD="$(
  release_clean_git \
    -C "$CONTROL_WORKTREE" \
    rev-parse \
    HEAD
)"

SOURCE_HEAD="$(
  release_clean_git \
    -C "$SOURCE_REPO" \
    rev-parse \
    HEAD
)"

SOURCE_TREE="$(
  release_clean_git \
    -C "$SOURCE_REPO" \
    rev-parse \
    'HEAD^{tree}'
)"

printf 'Observed control HEAD: %s\n' "$CONTROL_HEAD"
printf 'Observed source HEAD:  %s\n' "$SOURCE_HEAD"
printf 'Observed source tree:  %s\n' "$SOURCE_TREE"

if ! release_clean_git \
  -C "$CONTROL_WORKTREE" \
  merge-base \
  --is-ancestor \
  "$CONTROL_BASELINE_COMMIT" \
  "$CONTROL_HEAD"; then
  release_fail "control HEAD does not contain the governance baseline"
  FAILURES=$((FAILURES + 1))
else
  release_pass "control HEAD contains the manifest governance baseline."
fi

if [ "$SOURCE_HEAD" != "$RELEASE_COMMIT" ]; then
  release_fail "source HEAD does not match the accepted release commit"
  FAILURES=$((FAILURES + 1))
else
  release_pass "source HEAD matches the accepted release commit."
fi

if [ "$SOURCE_TREE" != "$RELEASE_TREE" ]; then
  release_fail "source tree does not match the accepted release tree"
  FAILURES=$((FAILURES + 1))
else
  release_pass "source tree matches the accepted release tree."
fi

printf '\n=== Upstream identity ===\n'

if ! release_clean_git \
  -C "$SOURCE_REPO" \
  cat-file \
  -e \
  "${UPSTREAM_COMMIT}^{commit}" \
  2> /dev/null; then
  release_fail "upstream commit is unavailable locally"
  FAILURES=$((FAILURES + 1))
else
  release_pass "upstream commit is available locally."
fi

LOCAL_TAG_COMMIT="$(
  release_clean_git \
    -C "$SOURCE_REPO" \
    rev-parse \
    --verify \
    --quiet \
    "refs/tags/${UPSTREAM_TAG}^{commit}" ||
    true
)"

TAG_COMMIT=""
TAG_SOURCE=""

if [ -n "$LOCAL_TAG_COMMIT" ]; then
  TAG_COMMIT="$LOCAL_TAG_COMMIT"
  TAG_SOURCE="local source repository"
else
  REMOTE_TAG_REFS="$(
    release_clean_git \
      -C "$SOURCE_REPO" \
      ls-remote \
      --tags \
      "https://github.com/${UPSTREAM_REPOSITORY}.git" \
      "refs/tags/${UPSTREAM_TAG}" \
      "refs/tags/${UPSTREAM_TAG}^{}" \
      2> /dev/null ||
      true
  )"

  TAG_COMMIT="$(
    printf '%s\n' \
      "$REMOTE_TAG_REFS" |
      awk \
        -v direct="refs/tags/${UPSTREAM_TAG}" \
        -v peeled="refs/tags/${UPSTREAM_TAG}^{}" '
        $2 == direct {
          direct_sha = $1
        }

        $2 == peeled {
          peeled_sha = $1
        }

        END {
          if (peeled_sha != "") {
            print peeled_sha
          } else if (direct_sha != "") {
            print direct_sha
          }
        }
      '
  )"

  TAG_SOURCE="official upstream repository"
fi

printf 'Tag source: %s\n' "${TAG_SOURCE:-unavailable}"
printf 'Tag commit: %s\n' "${TAG_COMMIT:-unavailable}"

if [ "$TAG_COMMIT" != "$UPSTREAM_COMMIT" ]; then
  release_fail "upstream tag does not resolve to the manifest commit"
  FAILURES=$((FAILURES + 1))
else
  release_pass "upstream tag resolves to the manifest commit."
fi

if ! release_clean_git \
  -C "$SOURCE_REPO" \
  merge-base \
  --is-ancestor \
  "$UPSTREAM_COMMIT" \
  "$RELEASE_COMMIT"; then
  release_fail "release commit is not a descendant of the upstream commit"
  FAILURES=$((FAILURES + 1))
else
  release_pass "release commit descends from the pinned upstream commit."
fi

printf '\n=== Release assets and paths ===\n'

if release_validate_patch_inventory \
  "$MANIFEST" \
  "$PATCH_ROOT"; then
  release_pass "canonical patch roles are coherent."
else
  release_fail "canonical patch roles or inventory differ"
  FAILURES=$((FAILURES + 1))
fi

if [ ! -x "$BUILD_ENTRYPOINT" ]; then
  release_fail "build entrypoint is missing or not executable"
  FAILURES=$((FAILURES + 1))
else
  release_pass "build entrypoint is executable."
fi

if [ ! -d "$EVIDENCE_ROOT" ]; then
  release_fail "release evidence root is absent"
  FAILURES=$((FAILURES + 1))
else
  release_pass "release evidence root exists."
fi

if [ ! -s "$RELEASE_RECORD" ]; then
  release_fail "permanent release record is absent"
  FAILURES=$((FAILURES + 1))
else
  release_pass "permanent release record exists."
fi

printf '\n=== Release input audit result ===\n'
printf 'Failures: %s\n' "$FAILURES"

if [ "$FAILURES" -eq 0 ]; then
  echo "PASS: release inputs and accepted baseline are coherent."
  echo "NOTICE: no branch, worktree, commit, package, release or evidence was changed."
else
  echo "STOP: release input audit found blocking differences."
fi

exit "$FAILURES"
