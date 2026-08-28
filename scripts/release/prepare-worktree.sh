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
ROLE="work"
TARGET_WORKTREE=""
APPLY_PATCHES=0
CONFIRM_CREATE=0
PLAN_ONLY=0

usage() {
  cat << 'USAGE'
Usage:
  bash scripts/release/prepare-worktree.sh \
    --source-repo PATH \
    --role work|release \
    [--control-worktree PATH] \
    [--manifest PATH] \
    [--target-worktree PATH] \
    [--apply-patches] \
    [--confirm-create]

Use --plan-only to validate and print the exact operation without mutation.
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
    --role)
      ROLE="$2"
      shift
      ;;
    --target-worktree)
      TARGET_WORKTREE="$2"
      shift
      ;;
    --apply-patches)
      APPLY_PATCHES=1
      ;;
    --confirm-create)
      CONFIRM_CREATE=1
      ;;
    --plan-only)
      PLAN_ONLY=1
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

if [ "$ROLE" != "work" ] &&
  [ "$ROLE" != "release" ]; then
  release_fail "--role must be work or release"
  exit 2
fi

if [ -z "$SOURCE_REPO" ]; then
  release_fail "--source-repo is required"
  exit 2
fi

if [ -z "$MANIFEST" ]; then
  MANIFEST="${CONTROL_WORKTREE}/release/manifest.yaml"
fi

release_require_worktree "$CONTROL_WORKTREE" || exit 1
release_require_worktree "$SOURCE_REPO" || exit 1
release_validate_manifest "$MANIFEST" || exit 1
release_require_clean_worktree "$SOURCE_REPO" || exit 1

UPSTREAM_COMMIT="$(release_manifest_get "$MANIFEST" upstream.commit)"

if [ "$ROLE" = "work" ]; then
  TARGET_BRANCH="$(release_manifest_get "$MANIFEST" branches.work)"
else
  TARGET_BRANCH="$(release_manifest_get "$MANIFEST" branches.release)"
fi

if [ -z "$TARGET_WORKTREE" ]; then
  safe_branch="$(
    printf '%s\n' \
      "$TARGET_BRANCH" |
      tr \
        '/' \
        '-'
  )"
  TARGET_WORKTREE="${HOME}/development/tailscale-synology-${safe_branch}"
fi

printf '=== Release worktree plan ===\n'
printf 'Source repository: %s\n' "$SOURCE_REPO"
printf 'Control worktree:  %s\n' "$CONTROL_WORKTREE"
printf 'Role:              %s\n' "$ROLE"
printf 'Target branch:     %s\n' "$TARGET_BRANCH"
printf 'Target worktree:   %s\n' "$TARGET_WORKTREE"
printf 'Upstream commit:   %s\n' "$UPSTREAM_COMMIT"
printf 'Apply patches:     %s\n' "$APPLY_PATCHES"

release_clean_git \
  -C "$SOURCE_REPO" \
  cat-file \
  -e \
  "${UPSTREAM_COMMIT}^{commit}" ||
  {
    release_fail "upstream commit is unavailable locally"
    exit 1
  }

release_validate_patch_layers "$MANIFEST" "$CONTROL_WORKTREE" || exit 1

PATCH_COUNT=0
while IFS= read -r layer; do
  [ -n "$layer" ] || continue
  PATCH_ROOT="$(release_patch_layer_root "$MANIFEST" "$CONTROL_WORKTREE" "$layer")" || exit 1
  layer_count="$(find "$PATCH_ROOT" -maxdepth 1 -type f -name '*.patch' -print | wc -l | tr -d ' ')"
  PATCH_COUNT=$((PATCH_COUNT + layer_count))
done < <(release_manifest_patch_layers "$MANIFEST")

if [ "$PATCH_COUNT" -lt 1 ]; then
  release_fail "canonical patch series is unavailable: ${PATCH_ROOT}"
  exit 1
fi

printf 'Patch count:       %s\n' "$PATCH_COUNT"

if [ "$PLAN_ONLY" -eq 1 ]; then
  release_pass "release worktree plan is valid."
  release_notice "no branch or worktree was created."
  exit 0
fi

if [ "$CONFIRM_CREATE" -ne 1 ]; then
  release_fail "--confirm-create is required for mutation"
  exit 2
fi

if [ -e "$TARGET_WORKTREE" ]; then
  release_fail "target worktree path already exists"
  exit 1
fi

if release_clean_git \
  -C "$SOURCE_REPO" \
  show-ref \
  --verify \
  --quiet \
  "refs/heads/${TARGET_BRANCH}"; then
  release_fail "target local branch already exists"
  exit 1
fi

REMOTE_MATCH="$(
  release_clean_git \
    -C "$SOURCE_REPO" \
    ls-remote \
    --heads \
    origin \
    "refs/heads/${TARGET_BRANCH}" \
    2> /dev/null ||
    true
)"

if [ -n "$REMOTE_MATCH" ]; then
  release_fail "target remote branch already exists"
  exit 1
fi

release_clean_git \
  -C "$SOURCE_REPO" \
  worktree \
  add \
  -b "$TARGET_BRANCH" \
  "$TARGET_WORKTREE" \
  "$UPSTREAM_COMMIT"

WORKTREE_RC=$?

printf 'Worktree creation status: %s\n' "$WORKTREE_RC"

if [ "$WORKTREE_RC" -ne 0 ]; then
  echo "STOP: release worktree creation failed."
  exit "$WORKTREE_RC"
fi

if [ "$APPLY_PATCHES" -eq 1 ]; then
  release_apply_patch_layers \
    "$TARGET_WORKTREE" \
    "$MANIFEST" \
    "$CONTROL_WORKTREE" \
    worktree

  PATCH_RC=$?

  printf 'Patch application status: %s\n' "$PATCH_RC"

  if [ "$PATCH_RC" -ne 0 ]; then
    release_clean_git \
      -C "$TARGET_WORKTREE" \
      reset \
      --hard \
      "$UPSTREAM_COMMIT" \
      > /dev/null

    release_clean_git \
      -C "$TARGET_WORKTREE" \
      clean \
      -fd \
      > /dev/null

    release_fail "patch application failed; the new clean worktree remains for review"
    exit "$PATCH_RC"
  fi
fi

release_pass "release worktree was created from the exact upstream commit."
release_notice "the branch was not pushed and no package was built."
