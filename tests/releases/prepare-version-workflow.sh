#!/usr/bin/env bash
set -u

REPO_ROOT="$(
  cd \
    "$(dirname "${BASH_SOURCE[0]}")/../.." &&
    pwd
)"
PREPARE_SCRIPT="${REPO_ROOT}/scripts/release/prepare-worktree.sh"
CASE="${1:-success}"
TEMP_ROOT=""
SOURCE_REPO=""

fail() {
  printf 'FAIL: %s\n' "$1" >&2
  exit 1
}

cleanup() {
  if [ -n "$SOURCE_REPO" ] &&
    [ -d "$SOURCE_REPO/.git" ]; then
    while IFS= read -r registered_worktree; do
      if [ "$registered_worktree" != "$SOURCE_REPO" ] &&
        [ -n "$TEMP_ROOT" ] &&
        [[ "$registered_worktree" == "$TEMP_ROOT"/* ]]; then
        git -C "$SOURCE_REPO" worktree remove "$registered_worktree" \
          > /dev/null 2>&1 || true
      fi
    done < <(
      git -C "$SOURCE_REPO" worktree list --porcelain |
        sed -n 's/^worktree //p'
    )
  fi

  if [ -n "$TEMP_ROOT" ] &&
    [[ "$TEMP_ROOT" == /tmp/tailscale-prepare-version-test.* ]]; then
    rm -rf -- "$TEMP_ROOT"
  fi
}

trap cleanup EXIT

require_command() {
  command -v "$1" > /dev/null 2>&1 || fail "required command unavailable: $1"
}

git_fixture() {
  git -C "$SOURCE_REPO" "$@"
}

write_product() {
  upstream_value="$1"
  network_value="$2"
  printf 'upstream=%s\nnetwork=%s\n' "$upstream_value" "$network_value" \
    > "$SOURCE_REPO/product.conf"
}

snapshot_refs() {
  refs_repo="$1"
  git -C "$refs_repo" show-ref 2> /dev/null | sort || true
}

assert_equal() {
  expected="$1"
  actual="$2"
  message="$3"

  if [ "$actual" != "$expected" ]; then
    printf 'Expected: %s\nObserved: %s\n' "$expected" "$actual" >&2
    fail "$message"
  fi
}

assert_file() {
  [ -s "$1" ] || fail "required artifact is missing or empty: $1"
}

create_success_fixture() {
  TEMP_ROOT="$(mktemp -d /tmp/tailscale-prepare-version-test.XXXXXX)"
  SOURCE_REPO="${TEMP_ROOT}/source"
  BARE_ORIGIN="${TEMP_ROOT}/origin.git"
  SIGNING_KEY="${TEMP_ROOT}/signing-key"
  ALLOWED_SIGNERS="${TEMP_ROOT}/allowed_signers"
  PREPARED_WORKTREE="${TEMP_ROOT}/prepared"
  ARTIFACTS="${TEMP_ROOT}/artifacts"
  LOG="${TEMP_ROOT}/prepare.log"
  HOOKS_DIR="${TEMP_ROOT}/inherited-hooks"
  HOOK_EVIDENCE="${TEMP_ROOT}/inherited-hooks.log"

  git init --bare --initial-branch=main "$BARE_ORIGIN" > /dev/null 2>&1 ||
    fail "could not create bare origin"
  git init -b main "$SOURCE_REPO" > /dev/null 2>&1 ||
    fail "could not create source repository"
  git_fixture config user.name "Fixture Agent"
  git_fixture config user.email "fixture@example.invalid"
  git_fixture config commit.gpgsign false

  write_product old userspace
  git_fixture add product.conf
  git_fixture commit -m "upstream: old base" > /dev/null || fail "could not commit old base"
  OLD_UPSTREAM="$(git_fixture rev-parse HEAD)"
  git_fixture tag v1.0.0 "$OLD_UPSTREAM"

  git_fixture switch -c previous-release > /dev/null 2>&1
  write_product old kernel
  git_fixture add product.conf
  git_fixture commit -s -m "synology: enable kernel tun" > /dev/null ||
    fail "could not commit first logical change"
  FIRST_SOURCE_COMMIT="$(git_fixture rev-parse HEAD)"

  printf 'backend=linux-netfilter\n' > "$SOURCE_REPO/netfilter.conf"
  git_fixture add netfilter.conf
  git_fixture commit -s -m "synology: enable linux netfilter" > /dev/null ||
    fail "could not commit second logical change"
  PREVIOUS_RELEASE="$(git_fixture rev-parse HEAD)"

  git_fixture switch main > /dev/null 2>&1
  printf 'release=2.0.0\n' > "$SOURCE_REPO/upstream-release.conf"
  git_fixture add upstream-release.conf
  git_fixture commit -m "upstream: new release" > /dev/null ||
    fail "could not commit new upstream"
  NEW_UPSTREAM="$(git_fixture rev-parse HEAD)"
  git_fixture tag v2.0.0 "$NEW_UPSTREAM"

  ssh-keygen -q -t ed25519 -N '' -f "$SIGNING_KEY" ||
    fail "could not generate fixture signing key"
  printf 'fixture@example.invalid %s\n' "$(<"${SIGNING_KEY}.pub")" \
    > "$ALLOWED_SIGNERS"
  git_fixture config gpg.format ssh
  git_fixture config user.signingkey "$SIGNING_KEY"
  git_fixture config gpg.ssh.allowedSignersFile "$ALLOWED_SIGNERS"
  git_fixture config commit.gpgsign true
  git_fixture remote add origin "$BARE_ORIGIN"
  git_fixture push origin main previous-release --tags > /dev/null 2>&1 ||
    fail "could not seed fixture origin"

  mkdir -p "$HOOKS_DIR"
  for hook_name in post-commit post-applypatch; do
    cat > "$HOOKS_DIR/$hook_name" << 'HOOK'
#!/bin/sh
printf '%s\n' "$(basename "$0")" >> "${HOOK_EVIDENCE:?}"
HOOK
    chmod 0755 "$HOOKS_DIR/$hook_name"
  done
  export HOOK_EVIDENCE
  git_fixture config core.hooksPath "$HOOKS_DIR"

  REMOTE_REFS_BEFORE="$(snapshot_refs "$BARE_ORIGIN")"
  TAG_REFS_BEFORE="$(git_fixture show-ref --tags | sort)"

  if ! bash "$PREPARE_SCRIPT" prepare-version \
    --source-repo "$SOURCE_REPO" \
    --upstream-tag v2.0.0 \
    --upstream-commit "$NEW_UPSTREAM" \
    --previous-upstream-commit "$OLD_UPSTREAM" \
    --previous-release-commit "$PREVIOUS_RELEASE" \
    --new-version 2.0.0 \
    --downstream-revision r1 \
    --target-branch work/v2.0.0-synology-r1 \
    --target-worktree "$PREPARED_WORKTREE" \
    --output-root "$ARTIFACTS" \
    --confirm-create \
    > "$LOG" 2>&1; then
    sed -n '1,240p' "$LOG" >&2
    fail "prepare-version success fixture did not complete"
  fi

  assert_file "$ARTIFACTS/manifest.json"
  assert_file "$ARTIFACTS/SHA256SUMS"
  assert_file "$ARTIFACTS/patches/series"
  assert_file "$ARTIFACTS/preparation-report.md"

  if [ -e "$HOOK_EVIDENCE" ]; then
    sed -n '1,80p' "$HOOK_EVIDENCE" >&2
    fail "prepare-version executed inherited Git hooks"
  fi
  if ! grep -Fxq \
    -- '- Internal commit/apply hooks: disabled' \
    "$ARTIFACTS/preparation-report.md"; then
    fail "preparation report does not record internal hook isolation"
  fi

  PREPARED_HEAD="$(git -C "$PREPARED_WORKTREE" rev-parse HEAD)"
  PREPARED_TREE="$(git -C "$PREPARED_WORKTREE" rev-parse 'HEAD^{tree}')"
  PREPARED_BASE="$(git -C "$PREPARED_WORKTREE" rev-parse 'HEAD~2')"
  assert_equal "$NEW_UPSTREAM" "$PREPARED_BASE" \
    "prepared stack does not start at the exact new upstream commit"

  mapfile -t PREPARED_COMMITS < <(
    git -C "$PREPARED_WORKTREE" rev-list --reverse "${NEW_UPSTREAM}..HEAD"
  )
  assert_equal "2" "${#PREPARED_COMMITS[@]}" \
    "prepared stack does not preserve the logical commit count"

  EXPECTED_SUBJECTS=$'synology: enable kernel tun\nsynology: enable linux netfilter'
  ACTUAL_SUBJECTS="$(
    git -C "$PREPARED_WORKTREE" log --reverse --format=%s "${NEW_UPSTREAM}..HEAD"
  )"
  assert_equal "$EXPECTED_SUBJECTS" "$ACTUAL_SUBJECTS" \
    "prepared stack does not preserve logical order"

  for prepared_commit in "${PREPARED_COMMITS[@]}"; do
    git -C "$PREPARED_WORKTREE" verify-commit "$prepared_commit" \
      > /dev/null 2>&1 ||
      fail "prepared commit signature is invalid: ${prepared_commit}"
    signoff_count="$(
      git -C "$PREPARED_WORKTREE" show -s --format=%B "$prepared_commit" |
        git interpret-trailers --parse |
        grep -Eic '^Signed-off-by:[[:space:]]' || true
    )"
    assert_equal "1" "$signoff_count" \
      "prepared commit does not contain exactly one sign-off"
  done

  mapfile -t PATCH_FILES < "$ARTIFACTS/patches/series"
  assert_equal "2" "${#PATCH_FILES[@]}" \
    "mail patch series does not contain two ordered entries"
  for patch_name in "${PATCH_FILES[@]}"; do
    case "$patch_name" in
      [0-9][0-9][0-9][0-9]-*.patch) ;;
      *) fail "mail patch has an unsafe name: ${patch_name}" ;;
    esac
    assert_file "$ARTIFACTS/patches/$patch_name"
  done

  (
    cd "$ARTIFACTS" || exit 1
    sha256sum -c SHA256SUMS
  ) > /dev/null || fail "review artifact checksums do not verify"

  python3 - \
    "$ARTIFACTS/manifest.json" \
    "$SOURCE_REPO" \
    "$OLD_UPSTREAM" \
    "$PREVIOUS_RELEASE" \
    "$NEW_UPSTREAM" \
    "$PREPARED_HEAD" \
    "$PREPARED_TREE" \
    "$FIRST_SOURCE_COMMIT" << 'PY'
import json
import sys
from pathlib import Path

(
    manifest_path,
    source_repo,
    old_upstream,
    old_release,
    new_upstream,
    prepared_head,
    prepared_tree,
    first_source_commit,
) = sys.argv[1:]
manifest = json.loads(Path(manifest_path).read_text(encoding="utf-8"))
required = {
    "schema_version",
    "source",
    "upstream",
    "version",
    "prepared",
    "logical_commits",
    "patches",
    "synology_contract",
    "validation",
    "safety",
}
if set(manifest) != required:
    raise SystemExit("manifest top-level fields differ from schema contract")
if manifest["schema_version"] != 1:
    raise SystemExit("manifest schema version differs")
if manifest["source"] != {
    "repository": source_repo,
    "previous_upstream_commit": old_upstream,
    "previous_release_commit": old_release,
}:
    raise SystemExit("manifest source identities differ")
if manifest["upstream"] != {"tag": "v2.0.0", "commit": new_upstream}:
    raise SystemExit("manifest upstream identity differs")
if manifest["version"] != {"upstream": "2.0.0", "downstream_revision": "r1"}:
    raise SystemExit("manifest version identity differs")
prepared = manifest["prepared"]
if prepared["branch"] != "work/v2.0.0-synology-r1":
    raise SystemExit("manifest prepared branch differs")
if prepared["commit"] != prepared_head or prepared["tree"] != prepared_tree:
    raise SystemExit("manifest prepared commit/tree differs")
logical = manifest["logical_commits"]
if len(logical) != 2 or logical[0]["source_commit"] != first_source_commit:
    raise SystemExit("manifest logical history differs")
if [item["order"] for item in logical] != [1, 2]:
    raise SystemExit("manifest logical history order differs")
if [item["order"] for item in manifest["patches"]] != [1, 2]:
    raise SystemExit("manifest patch order differs")
if manifest["synology_contract"] != {
    "dependency_section": "iptables-netfilter-extensions",
    "dependency_minimum": "1.1.0-3",
    "dependency_os_minimum": "7.3-86009",
    "tailscale_os_minimum": "7.3-86009",
    "os_max_ver_allowed": False,
}:
    raise SystemExit("manifest Synology contract differs")
if set(manifest["safety"].values()) != {False}:
    raise SystemExit("manifest safety capabilities are not all false")
validation = manifest["validation"]
if validation != {
    "source_range_linear": True,
    "signed_commits": True,
    "single_signoff_commits": True,
    "patch_round_trip": True,
    "round_trip_tree": prepared_tree,
}:
    raise SystemExit("manifest validation evidence differs")
PY

  REMOTE_REFS_AFTER="$(snapshot_refs "$BARE_ORIGIN")"
  TAG_REFS_AFTER="$(git_fixture show-ref --tags | sort)"
  assert_equal "$REMOTE_REFS_BEFORE" "$REMOTE_REFS_AFTER" \
    "prepare-version changed remote refs"
  assert_equal "$TAG_REFS_BEFORE" "$TAG_REFS_AFTER" \
    "prepare-version changed local tags"

  if find "$TEMP_ROOT" -type f -name '*.spk' -print -quit | grep -q .; then
    fail "prepare-version created an SPK side effect"
  fi

  printf 'PASS: offline success fixture prepared signed ordered patches without publication side effects.\n'
}

create_failure_fixture() {
  failure_case="$1"
  TEMP_ROOT="$(mktemp -d /tmp/tailscale-prepare-version-test.XXXXXX)"
  SOURCE_REPO="${TEMP_ROOT}/source"
  BARE_ORIGIN="${TEMP_ROOT}/origin.git"
  SIGNING_KEY="${TEMP_ROOT}/signing-key"
  ALLOWED_SIGNERS="${TEMP_ROOT}/allowed_signers"
  PREPARED_WORKTREE="${TEMP_ROOT}/prepared"
  ARTIFACTS="${TEMP_ROOT}/artifacts"
  LOG="${TEMP_ROOT}/prepare.log"

  git init --bare --initial-branch=main "$BARE_ORIGIN" > /dev/null 2>&1 ||
    fail "could not create failure-fixture origin"
  git init -b main "$SOURCE_REPO" > /dev/null 2>&1 ||
    fail "could not create failure-fixture source"
  git_fixture config user.name "Fixture Agent"
  git_fixture config user.email "fixture@example.invalid"
  git_fixture config commit.gpgsign false

  write_product old userspace
  git_fixture add product.conf
  git_fixture commit -m "upstream: old base" > /dev/null ||
    fail "could not commit failure-fixture old base"
  OLD_UPSTREAM="$(git_fixture rev-parse HEAD)"

  git_fixture switch -c previous-release > /dev/null 2>&1
  write_product old kernel
  git_fixture add product.conf
  git_fixture commit -s -m "synology: enable kernel tun" > /dev/null ||
    fail "could not commit failure-fixture logical change"
  PREVIOUS_RELEASE="$(git_fixture rev-parse HEAD)"

  git_fixture switch main > /dev/null 2>&1
  case "$failure_case" in
    mismatch)
      printf 'release=2.0.0\n' > "$SOURCE_REPO/upstream-release.conf"
      git_fixture add upstream-release.conf
      ;;
    conflict)
      write_product old native
      git_fixture add product.conf
      ;;
    *)
      fail "unsupported failure fixture: ${failure_case}"
      ;;
  esac
  git_fixture commit -m "upstream: new release" > /dev/null ||
    fail "could not commit failure-fixture new upstream"
  NEW_UPSTREAM="$(git_fixture rev-parse HEAD)"
  git_fixture tag v2.0.0 "$NEW_UPSTREAM"

  ssh-keygen -q -t ed25519 -N '' -f "$SIGNING_KEY" ||
    fail "could not generate failure-fixture signing key"
  printf 'fixture@example.invalid %s\n' "$(<"${SIGNING_KEY}.pub")" \
    > "$ALLOWED_SIGNERS"
  git_fixture config gpg.format ssh
  git_fixture config user.signingkey "$SIGNING_KEY"
  git_fixture config gpg.ssh.allowedSignersFile "$ALLOWED_SIGNERS"
  git_fixture config commit.gpgsign true
  git_fixture remote add origin "$BARE_ORIGIN"
  git_fixture push origin main previous-release --tags > /dev/null 2>&1 ||
    fail "could not seed failure-fixture origin"

  REMOTE_REFS_BEFORE="$(snapshot_refs "$BARE_ORIGIN")"
  TAG_REFS_BEFORE="$(git_fixture show-ref --tags | sort)"
  SELECTED_UPSTREAM="$NEW_UPSTREAM"
  EXPECTED_FAILURE="logical commit replay conflicted"
  if [ "$failure_case" = "mismatch" ]; then
    SELECTED_UPSTREAM="$OLD_UPSTREAM"
    EXPECTED_FAILURE="explicit upstream tag does not peel to the explicit commit"
  fi

  if bash "$PREPARE_SCRIPT" prepare-version \
    --source-repo "$SOURCE_REPO" \
    --upstream-tag v2.0.0 \
    --upstream-commit "$SELECTED_UPSTREAM" \
    --previous-upstream-commit "$OLD_UPSTREAM" \
    --previous-release-commit "$PREVIOUS_RELEASE" \
    --new-version 2.0.0 \
    --downstream-revision r1 \
    --target-branch work/v2.0.0-synology-r1 \
    --target-worktree "$PREPARED_WORKTREE" \
    --output-root "$ARTIFACTS" \
    --confirm-create \
    > "$LOG" 2>&1; then
    fail "${failure_case} fixture unexpectedly succeeded"
  fi

  if ! grep -Fq "$EXPECTED_FAILURE" "$LOG"; then
    sed -n '1,240p' "$LOG" >&2
    fail "${failure_case} fixture did not report the expected stop condition"
  fi
  if [ -e "$ARTIFACTS" ]; then
    fail "${failure_case} fixture installed a final artifact directory"
  fi
  if find "$TEMP_ROOT" -maxdepth 1 -type d \
    -name '.artifacts.staging.*' -print -quit | grep -q .; then
    fail "${failure_case} fixture left a private artifact staging directory"
  fi

  if [ "$failure_case" = "mismatch" ]; then
    if git_fixture show-ref --verify --quiet \
      refs/heads/work/v2.0.0-synology-r1; then
      fail "identity mismatch created a target branch"
    fi
    if [ -e "$PREPARED_WORKTREE" ]; then
      fail "identity mismatch created a target worktree"
    fi
  else
    [ -d "$PREPARED_WORKTREE" ] ||
      fail "conflict fixture did not leave its isolated worktree for review"
    if git -C "$PREPARED_WORKTREE" rev-parse -q --verify CHERRY_PICK_HEAD \
      > /dev/null 2>&1; then
      fail "conflict fixture left CHERRY_PICK_HEAD"
    fi
    if [ -n "$(git -C "$PREPARED_WORKTREE" diff --name-only --diff-filter=U)" ]; then
      fail "conflict fixture left unmerged entries"
    fi
    if [ -n "$(git -C "$PREPARED_WORKTREE" status --short --untracked-files=all)" ]; then
      fail "conflict fixture left a dirty isolated worktree"
    fi
    assert_equal "$NEW_UPSTREAM" \
      "$(git -C "$PREPARED_WORKTREE" rev-parse HEAD)" \
      "conflict fixture did not return to the exact upstream commit"
  fi

  REMOTE_REFS_AFTER="$(snapshot_refs "$BARE_ORIGIN")"
  TAG_REFS_AFTER="$(git_fixture show-ref --tags | sort)"
  assert_equal "$REMOTE_REFS_BEFORE" "$REMOTE_REFS_AFTER" \
    "${failure_case} fixture changed remote refs"
  assert_equal "$TAG_REFS_BEFORE" "$TAG_REFS_AFTER" \
    "${failure_case} fixture changed local tags"

  printf 'PASS: %s fixture stopped closed without publication side effects.\n' \
    "$failure_case"
}

for command_name in git python3 sha256sum ssh-keygen sed sort; do
  require_command "$command_name"
done

case "$CASE" in
  success)
    create_success_fixture
    ;;
  mismatch | conflict)
    create_failure_fixture "$CASE"
    ;;
  all)
    create_success_fixture
    cleanup
    create_failure_fixture mismatch
    cleanup
    create_failure_fixture conflict
    ;;
  *)
    fail "unsupported fixture case: ${CASE}"
    ;;
esac
