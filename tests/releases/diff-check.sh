#!/usr/bin/env bash
set -u

REPO_ROOT="$(
  cd \
    "$(dirname "${BASH_SOURCE[0]}")/../.." &&
    pwd
)"
BASE="8c9fe5239ee57a89ce687fc8c7608d3df91f6ede"
TEMP_ROOT=""

fail() {
  printf 'FAIL: %s\n' "$1" >&2
  exit 1
}

cleanup() {
  if [ -n "$TEMP_ROOT" ] &&
    [[ "$TEMP_ROOT" == /tmp/tailscale-diff-check-test.* ]]; then
    rm -rf -- "$TEMP_ROOT"
  fi
}

trap cleanup EXIT

git -C "$REPO_ROOT" diff --check "${BASE}..HEAD" ||
  fail "full feature range contains a non-exempt whitespace error"

TEMP_ROOT="$(mktemp -d /tmp/tailscale-diff-check-test.XXXXXX)"
FIXTURE_ROOT="${TEMP_ROOT}/repo"
CHECK_LOG="${TEMP_ROOT}/diff-check.log"

git init -b main "$FIXTURE_ROOT" > /dev/null 2>&1 ||
  fail "could not create whitespace-policy fixture"
git -C "$FIXTURE_ROOT" config user.name "Whitespace Fixture"
git -C "$FIXTURE_ROOT" config user.email "whitespace@example.invalid"
mkdir -p "$FIXTURE_ROOT/docs" "$FIXTURE_ROOT/patches/v1.98.9/history"
cp "$REPO_ROOT/.gitattributes" "$FIXTURE_ROOT/.gitattributes"
printf 'clean\n' > "$FIXTURE_ROOT/docs/defect.md"
printf 'clean\n' > \
  "$FIXTURE_ROOT/patches/v1.98.9/history/0001-immutable.patch"
git -C "$FIXTURE_ROOT" add .
git -C "$FIXTURE_ROOT" commit -m "fixture: baseline" > /dev/null ||
  fail "could not commit whitespace-policy baseline"

printf 'defect \n' > "$FIXTURE_ROOT/docs/defect.md"
printf 'payload \n \timmutable\n' > \
  "$FIXTURE_ROOT/patches/v1.98.9/history/0001-immutable.patch"
if git -C "$FIXTURE_ROOT" diff --check > "$CHECK_LOG" 2>&1; then
  fail "Git accepted a whitespace defect outside immutable payload paths"
fi
grep -Fq 'docs/defect.md:1: trailing whitespace.' "$CHECK_LOG" ||
  fail "Git did not report the non-payload Markdown whitespace defect"
if grep -Fq 'patches/v1.98.9/history/0001-immutable.patch' "$CHECK_LOG"; then
  fail "Git reported an exempt immutable patch payload"
fi

git -C "$FIXTURE_ROOT" restore docs/defect.md
git -C "$FIXTURE_ROOT" diff --check ||
  fail "immutable patch payload paths were not narrowly exempted"

echo "PASS: full-range and non-payload whitespace policy checks passed."
