#!/usr/bin/env bash
set -u

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
GIT_DIR_PATH="$(git -C "$REPO_ROOT" rev-parse --git-dir)"

# shellcheck source=scripts/release/common.sh
. "${REPO_ROOT}/scripts/release/common.sh"

declare -A before

for key in core.bare user.name user.email; do
  before["$key"]="$(release_clean_git -C "$REPO_ROOT" config --get "$key")"
done

for contract in \
  tests/releases/patch-base-identity-contract.sh \
  tests/releases/reference-patch-contract.sh; do
  GIT_DIR="$GIT_DIR_PATH" \
    GIT_WORK_TREE="$REPO_ROOT" \
    bash "${REPO_ROOT}/${contract}" || {
    printf 'FAIL: temporary Git contract failed under hook Git environment: %s\n' "$contract" >&2
    exit 1
  }
done

for key in core.bare user.name user.email; do
  after="$(release_clean_git -C "$REPO_ROOT" config --get "$key")"
  if [ "$after" != "${before[$key]}" ]; then
    printf 'FAIL: temporary Git contracts changed caller worktree %s\n' "$key" >&2
    exit 1
  fi
done

release_clean_git -C "$REPO_ROOT" status --short > /dev/null || {
  echo "FAIL: temporary Git contracts left the caller without a worktree" >&2
  exit 1
}

echo "PASS: temporary Git contracts isolate hook Git environment from the caller worktree."
