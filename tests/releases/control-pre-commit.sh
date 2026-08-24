#!/usr/bin/env bash
set -u

REPO_ROOT="$(
  cd \
    "$(dirname "${BASH_SOURCE[0]}")/../.." &&
    pwd
)"
TEMP_ROOT=""
SOURCE_LOG="$(mktemp /tmp/tailscale-source-control-role.XXXXXX)"

fail() {
  printf 'FAIL: %s\n' "$1" >&2
  exit 1
}

cleanup() {
  rm -f -- "$SOURCE_LOG"
  if [ -n "$TEMP_ROOT" ] &&
    [[ "$TEMP_ROOT" == /tmp/tailscale-control-hook-test.* ]]; then
    rm -rf -- "$TEMP_ROOT"
  fi
}

trap cleanup EXIT

hooks_before="$(
  git -C "$REPO_ROOT" config --worktree --get core.hooksPath 2> /dev/null ||
    true
)"
if bash "$REPO_ROOT/scripts/setup-worktree.sh" \
  --worktree "$REPO_ROOT" \
  --control-worktree "$REPO_ROOT" \
  --role control \
  --dry-run \
  > "$SOURCE_LOG" 2>&1; then
  fail "unified source tree accepted the control-only role"
fi
grep -Fxq \
  "FAIL: control role requires scripts/validate-repository.sh in the selected worktree" \
  "$SOURCE_LOG" || fail "source-tree rejection omitted the exact diagnostic"
hooks_after="$(
  git -C "$REPO_ROOT" config --worktree --get core.hooksPath 2> /dev/null ||
    true
)"
[ "$hooks_after" = "$hooks_before" ] ||
  fail "rejected control-role setup changed the hooks path"

TEMP_ROOT="$(mktemp -d /tmp/tailscale-control-hook-test.XXXXXX)"
FIXTURE_ROOT="${TEMP_ROOT}/control"
DIFFERENT_ROOT="${TEMP_ROOT}/different-control"
HOOK_RECORD="${TEMP_ROOT}/hook-record"

git init -b main "$FIXTURE_ROOT" > /dev/null 2>&1 ||
  fail "could not create control-role fixture"
git init -b main "$DIFFERENT_ROOT" > /dev/null 2>&1 ||
  fail "could not create differing-root fixture"
mkdir -p "$FIXTURE_ROOT/.githooks" "$FIXTURE_ROOT/scripts"
mkdir -p "$DIFFERENT_ROOT/scripts"
cp "$REPO_ROOT/.githooks/pre-commit" "$FIXTURE_ROOT/.githooks/pre-commit"
cp "$REPO_ROOT/.githooks/commit-msg" "$FIXTURE_ROOT/.githooks/commit-msg"
cp "$REPO_ROOT/scripts/setup-worktree.sh" "$FIXTURE_ROOT/scripts/setup-worktree.sh"
cat > "$FIXTURE_ROOT/scripts/validate-repository.sh" << 'VALIDATOR'
#!/usr/bin/env bash
printf '%s\n' "$*" > "${HOOK_RECORD:?}"
VALIDATOR
chmod 0755 \
  "$FIXTURE_ROOT/.githooks/pre-commit" \
  "$FIXTURE_ROOT/.githooks/commit-msg" \
  "$FIXTURE_ROOT/scripts/setup-worktree.sh" \
  "$FIXTURE_ROOT/scripts/validate-repository.sh"

cp \
  "$FIXTURE_ROOT/scripts/validate-repository.sh" \
  "$DIFFERENT_ROOT/scripts/validate-repository.sh"
if bash "$FIXTURE_ROOT/scripts/setup-worktree.sh" \
  --worktree "$DIFFERENT_ROOT" \
  --control-worktree "$FIXTURE_ROOT" \
  --role control \
  --dry-run \
  > "$SOURCE_LOG" 2>&1; then
  fail "control role accepted different validation and configured roots"
fi
grep -Fxq \
  "FAIL: control role requires worktree and control worktree to resolve to the same root" \
  "$SOURCE_LOG" || fail "differing-root rejection omitted the exact diagnostic"
if git -C "$DIFFERENT_ROOT" config --worktree --get core.hooksPath \
  > /dev/null 2>&1; then
  fail "differing-root rejection configured an unchecked hooks path"
fi

bash "$FIXTURE_ROOT/scripts/setup-worktree.sh" \
  --worktree "$FIXTURE_ROOT" \
  --control-worktree "$FIXTURE_ROOT" \
  --role control \
  > /dev/null || fail "complete control-role setup failed"
asserted_hooks="$(
  git -C "$FIXTURE_ROOT" config --worktree --get core.hooksPath
)"
[ "$asserted_hooks" = "$FIXTURE_ROOT/.githooks" ] ||
  fail "complete control role did not select repository-owned hooks"

export HOOK_RECORD
(
  cd "$FIXTURE_ROOT" || exit 1
  bash .githooks/pre-commit
) || fail "direct control pre-commit invocation failed"
[ "$(<"$HOOK_RECORD")" = "--fast --staged-secrets" ] ||
  fail "control pre-commit passed unexpected validator arguments"

echo "PASS: source trees reject control role and complete control trees run their hook."
