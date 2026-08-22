#!/usr/bin/env bash
set -u

SCRIPT_DIR="$(
  cd \
    "$(dirname "${BASH_SOURCE[0]}")" &&
    pwd
)"

# shellcheck source=scripts/release/common.sh
. "${SCRIPT_DIR}/common.sh"

CONTROL_WORKTREE="$(
  cd \
    "${SCRIPT_DIR}/../.." &&
    pwd
)"

prepare_version_usage() {
  cat << 'USAGE'
Usage:
  bash scripts/release/prepare-worktree.sh prepare-version \
    --source-repo PATH \
    --upstream-tag vN.N.N \
    --upstream-commit FULL_SHA \
    --previous-upstream-commit FULL_SHA \
    --previous-release-commit FULL_SHA \
    --new-version N.N.N \
    --downstream-revision rN \
    --target-branch work/vN.N.N-synology-rN \
    --target-worktree PATH \
    --output-root PATH \
    (--plan-only | --confirm-create)

All Git objects and the explicit tag must already exist locally. This command
does not fetch, push, tag, build, publish, install or operate a NAS.
USAGE
}

prepare_version() (
  SOURCE_REPO=""
  UPSTREAM_TAG=""
  UPSTREAM_COMMIT=""
  PREVIOUS_UPSTREAM_COMMIT=""
  PREVIOUS_RELEASE_COMMIT=""
  NEW_VERSION=""
  DOWNSTREAM_REVISION=""
  TARGET_BRANCH=""
  TARGET_WORKTREE=""
  OUTPUT_ROOT=""
  PLAN_ONLY=0
  CONFIRM_CREATE=0
  STAGING_DIR=""
  ROUND_TRIP_PARENT=""
  ROUND_TRIP_WORKTREE=""
  MESSAGE_FILE=""

  # shellcheck disable=SC2329 # Invoked by the EXIT trap below.
  cleanup_prepare_version() {
    if [ -n "$MESSAGE_FILE" ] &&
      [ -f "$MESSAGE_FILE" ]; then
      rm -f -- "$MESSAGE_FILE"
    fi

    if [ -n "$ROUND_TRIP_WORKTREE" ] &&
      [ -n "$SOURCE_REPO" ]; then
      release_clean_git \
        -C "$SOURCE_REPO" \
        worktree \
        remove \
        "$ROUND_TRIP_WORKTREE" \
        > /dev/null 2>&1 || true
    fi

    if [ -n "$ROUND_TRIP_PARENT" ] &&
      [[ "$ROUND_TRIP_PARENT" == /tmp/tailscale-version-round-trip.* ]]; then
      rmdir -- "$ROUND_TRIP_PARENT" > /dev/null 2>&1 || true
    fi

    if [ -n "$STAGING_DIR" ] &&
      [ -d "$STAGING_DIR" ] &&
      [[ "$(basename "$STAGING_DIR")" == .*\.staging.* ]]; then
      rm -rf -- "$STAGING_DIR"
    fi
  }

  trap cleanup_prepare_version EXIT

  require_option_value() {
    if [ "$#" -lt 2 ] ||
      [ -z "$2" ]; then
      release_fail "$1 requires a value"
      exit 2
    fi
  }

  while [ "$#" -gt 0 ]; do
    case "$1" in
      --source-repo)
        require_option_value "$@"
        SOURCE_REPO="$2"
        shift
        ;;
      --upstream-tag)
        require_option_value "$@"
        UPSTREAM_TAG="$2"
        shift
        ;;
      --upstream-commit)
        require_option_value "$@"
        UPSTREAM_COMMIT="$2"
        shift
        ;;
      --previous-upstream-commit)
        require_option_value "$@"
        PREVIOUS_UPSTREAM_COMMIT="$2"
        shift
        ;;
      --previous-release-commit)
        require_option_value "$@"
        PREVIOUS_RELEASE_COMMIT="$2"
        shift
        ;;
      --new-version)
        require_option_value "$@"
        NEW_VERSION="$2"
        shift
        ;;
      --downstream-revision)
        require_option_value "$@"
        DOWNSTREAM_REVISION="$2"
        shift
        ;;
      --target-branch)
        require_option_value "$@"
        TARGET_BRANCH="$2"
        shift
        ;;
      --target-worktree)
        require_option_value "$@"
        TARGET_WORKTREE="$2"
        shift
        ;;
      --output-root)
        require_option_value "$@"
        OUTPUT_ROOT="$2"
        shift
        ;;
      --plan-only)
        PLAN_ONLY=1
        ;;
      --confirm-create)
        CONFIRM_CREATE=1
        ;;
      --help | -h)
        prepare_version_usage
        exit 0
        ;;
      *)
        release_fail "unsupported prepare-version option: $1"
        prepare_version_usage >&2
        exit 2
        ;;
    esac
    shift
  done

  for command_name in git python3 sha256sum mktemp mv; do
    release_require_command "$command_name" || exit 1
  done

  for required_value in \
    SOURCE_REPO \
    UPSTREAM_TAG \
    UPSTREAM_COMMIT \
    PREVIOUS_UPSTREAM_COMMIT \
    PREVIOUS_RELEASE_COMMIT \
    NEW_VERSION \
    DOWNSTREAM_REVISION \
    TARGET_BRANCH \
    TARGET_WORKTREE \
    OUTPUT_ROOT; do
    if [ -z "${!required_value}" ]; then
      release_fail "required prepare-version input is absent: ${required_value}"
      exit 2
    fi
  done

  if [ "$PLAN_ONLY" -eq "$CONFIRM_CREATE" ]; then
    release_fail "select exactly one of --plan-only or --confirm-create"
    exit 2
  fi

  if [[ ! "$UPSTREAM_COMMIT" =~ ^[0-9a-f]{40}$ ]] ||
    [[ ! "$PREVIOUS_UPSTREAM_COMMIT" =~ ^[0-9a-f]{40}$ ]] ||
    [[ ! "$PREVIOUS_RELEASE_COMMIT" =~ ^[0-9a-f]{40}$ ]]; then
    release_fail "all commit identities must be full lowercase 40-character SHAs"
    exit 2
  fi

  if [[ ! "$NEW_VERSION" =~ ^[0-9]+\.[0-9]+\.[0-9]+(-[0-9A-Za-z.-]+)?$ ]] ||
    [ "$UPSTREAM_TAG" != "v${NEW_VERSION}" ]; then
    release_fail "upstream tag and new version identity differ or are invalid"
    exit 2
  fi

  if [[ ! "$DOWNSTREAM_REVISION" =~ ^r[1-9][0-9]*$ ]]; then
    release_fail "downstream revision must use rN form"
    exit 2
  fi

  EXPECTED_BRANCH="work/v${NEW_VERSION}-synology-${DOWNSTREAM_REVISION}"
  if [ "$TARGET_BRANCH" != "$EXPECTED_BRANCH" ]; then
    release_fail "target branch must equal ${EXPECTED_BRANCH}"
    exit 2
  fi

  release_require_worktree "$CONTROL_WORKTREE" || exit 1
  release_require_worktree "$SOURCE_REPO" || exit 1
  release_require_clean_worktree "$SOURCE_REPO" || exit 1

  SOURCE_REPO="$(
    release_clean_git \
      -C "$SOURCE_REPO" \
      rev-parse \
      --show-toplevel \
      2> /dev/null ||
      true
  )"
  if [ -z "$SOURCE_REPO" ]; then
    release_fail "could not resolve source repository root"
    exit 1
  fi
  TARGET_WORKTREE="$(release_absolute_path "$TARGET_WORKTREE")"
  OUTPUT_ROOT="$(release_absolute_path "$OUTPUT_ROOT")"

  if [ "$TARGET_WORKTREE" = "$OUTPUT_ROOT" ] ||
    [[ "$TARGET_WORKTREE" == "$OUTPUT_ROOT/"* ]] ||
    [[ "$OUTPUT_ROOT" == "$TARGET_WORKTREE/"* ]]; then
    release_fail "target worktree and output root must not overlap"
    exit 1
  fi

  if [ -e "$TARGET_WORKTREE" ] ||
    [ -e "$OUTPUT_ROOT" ]; then
    release_fail "target worktree and output root must not already exist"
    exit 1
  fi

  if [ ! -d "$(dirname "$TARGET_WORKTREE")" ] ||
    [ ! -d "$(dirname "$OUTPUT_ROOT")" ]; then
    release_fail "target worktree and output parent directories must already exist"
    exit 1
  fi

  bash "${CONTROL_WORKTREE}/tests/releases/version-preparation-contract.sh" ||
    {
      release_fail "version-preparation baseline validation failed"
      exit 1
    }

  for commit_id in \
    "$UPSTREAM_COMMIT" \
    "$PREVIOUS_UPSTREAM_COMMIT" \
    "$PREVIOUS_RELEASE_COMMIT"; do
    release_clean_git \
      -C "$SOURCE_REPO" \
      cat-file \
      -e \
      "${commit_id}^{commit}" 2> /dev/null ||
      {
        release_fail "required commit is unavailable locally: ${commit_id}"
        exit 1
      }
  done

  PEELED_TAG="$(
    release_clean_git \
      -C "$SOURCE_REPO" \
      rev-parse \
      --verify \
      "refs/tags/${UPSTREAM_TAG}^{commit}" \
      2> /dev/null ||
      true
  )"
  if [ "$PEELED_TAG" != "$UPSTREAM_COMMIT" ]; then
    release_stop "explicit upstream tag does not peel to the explicit commit"
    exit 1
  fi

  if ! release_clean_git \
    -C "$SOURCE_REPO" \
    merge-base \
    --is-ancestor \
    "$PREVIOUS_UPSTREAM_COMMIT" \
    "$PREVIOUS_RELEASE_COMMIT"; then
    release_fail "previous upstream commit is not an ancestor of the previous release"
    exit 1
  fi

  mapfile -t SOURCE_COMMITS < <(
    release_clean_git \
      -C "$SOURCE_REPO" \
      rev-list \
      --reverse \
      --topo-order \
      "${PREVIOUS_UPSTREAM_COMMIT}..${PREVIOUS_RELEASE_COMMIT}"
  )
  if [ "${#SOURCE_COMMITS[@]}" -eq 0 ]; then
    release_fail "previous downstream logical range is empty"
    exit 1
  fi

  EXPECTED_PARENT="$PREVIOUS_UPSTREAM_COMMIT"
  for source_commit in "${SOURCE_COMMITS[@]}"; do
    read -r -a COMMIT_WITH_PARENTS <<< "$(
      release_clean_git \
        -C "$SOURCE_REPO" \
        rev-list \
        --parents \
        -n \
        1 \
        "$source_commit"
    )"
    if [ "${#COMMIT_WITH_PARENTS[@]}" -ne 2 ] ||
      [ "${COMMIT_WITH_PARENTS[1]}" != "$EXPECTED_PARENT" ]; then
      release_fail "previous downstream range is not one linear ordered stack"
      exit 1
    fi
    EXPECTED_PARENT="$source_commit"
  done
  if [ "$EXPECTED_PARENT" != "$PREVIOUS_RELEASE_COMMIT" ]; then
    release_fail "previous release tip differs from the ordered logical stack"
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

  SIGNING_KEY="$(
    release_clean_git \
      -C "$SOURCE_REPO" \
      config \
      --get \
      user.signingkey \
      2> /dev/null ||
      true
  )"
  COMMIT_SIGNING="$(
    release_clean_git \
      -C "$SOURCE_REPO" \
      config \
      --bool \
      --get \
      commit.gpgsign \
      2> /dev/null ||
      true
  )"
  AUTHOR_NAME="$(release_clean_git -C "$SOURCE_REPO" config --get user.name || true)"
  AUTHOR_EMAIL="$(release_clean_git -C "$SOURCE_REPO" config --get user.email || true)"
  if [ -z "$SIGNING_KEY" ] ||
    [ "$COMMIT_SIGNING" != "true" ] ||
    [ -z "$AUTHOR_NAME" ] ||
    [ -z "$AUTHOR_EMAIL" ]; then
    release_fail "source repository lacks complete author and commit-signing configuration"
    exit 1
  fi

  printf '=== Pinned Synology version preparation plan ===\n'
  printf 'Source repository:          %s\n' "$SOURCE_REPO"
  printf 'Upstream tag:               %s\n' "$UPSTREAM_TAG"
  printf 'Upstream commit:            %s\n' "$UPSTREAM_COMMIT"
  printf 'Previous upstream commit:   %s\n' "$PREVIOUS_UPSTREAM_COMMIT"
  printf 'Previous release commit:    %s\n' "$PREVIOUS_RELEASE_COMMIT"
  printf 'Logical commit count:       %s\n' "${#SOURCE_COMMITS[@]}"
  printf 'New version:                %s\n' "$NEW_VERSION"
  printf 'Downstream revision:        %s\n' "$DOWNSTREAM_REVISION"
  printf 'Target branch:              %s\n' "$TARGET_BRANCH"
  printf 'Target worktree:            %s\n' "$TARGET_WORKTREE"
  printf 'Review artifact root:       %s\n' "$OUTPUT_ROOT"
  printf 'Commit signer configuration:%s\n' " present"
  printf 'Publication capabilities:   disabled\n'

  for source_commit in "${SOURCE_COMMITS[@]}"; do
    printf '  %s %s\n' \
      "$source_commit" \
      "$(release_clean_git -C "$SOURCE_REPO" show -s --format=%s "$source_commit")"
  done

  if [ "$PLAN_ONLY" -eq 1 ]; then
    release_pass "pinned version preparation plan is valid"
    release_notice "no branch, worktree, commit, artifact or remote ref was changed"
    exit 0
  fi

  release_clean_git \
    -C "$SOURCE_REPO" \
    worktree \
    add \
    -b "$TARGET_BRANCH" \
    "$TARGET_WORKTREE" \
    "$UPSTREAM_COMMIT"
  WORKTREE_RC=$?
  if [ "$WORKTREE_RC" -ne 0 ]; then
    release_fail "isolated preparation worktree creation failed"
    exit "$WORKTREE_RC"
  fi

  release_clean_git \
    -C "$TARGET_WORKTREE" \
    config \
    extensions.worktreeConfig \
    true
  release_clean_git \
    -C "$TARGET_WORKTREE" \
    config \
    --worktree \
    commit.gpgsign \
    true

  MESSAGE_FILE="$(mktemp /tmp/tailscale-version-message.XXXXXX)"
  PREPARED_COMMITS=()

  for source_commit in "${SOURCE_COMMITS[@]}"; do
    printf 'Replaying logical commit: %s\n' "$source_commit"
    release_clean_git \
      -C "$TARGET_WORKTREE" \
      cherry-pick \
      --no-commit \
      "$source_commit"
    CHERRY_PICK_RC=$?
    if [ "$CHERRY_PICK_RC" -ne 0 ]; then
      release_clean_git \
        -C "$TARGET_WORKTREE" \
        cherry-pick \
        --abort \
        > /dev/null 2>&1 || true
      release_clean_git \
        -C "$TARGET_WORKTREE" \
        reset \
        --hard \
        HEAD \
        > /dev/null 2>&1 || true
      release_fail "logical commit replay conflicted: ${source_commit}"
      exit "$CHERRY_PICK_RC"
    fi

    release_clean_git \
      -C "$SOURCE_REPO" \
      show \
      -s \
      --format=%B \
      "$source_commit" \
      > "$MESSAGE_FILE"
    python3 - "$MESSAGE_FILE" << 'PY'
import re
import sys
from pathlib import Path

path = Path(sys.argv[1])
lines = path.read_text(encoding="utf-8").splitlines()
lines = [line for line in lines if not re.match(r"^Signed-off-by:\s", line, re.I)]
while lines and not lines[-1]:
    lines.pop()
path.write_text("\n".join(lines) + "\n", encoding="utf-8")
PY

    release_hookless_git \
      -C "$TARGET_WORKTREE" \
      commit \
      -S \
      -s \
      -F "$MESSAGE_FILE"
    COMMIT_RC=$?
    if [ "$COMMIT_RC" -ne 0 ]; then
      release_clean_git \
        -C "$TARGET_WORKTREE" \
        reset \
        --hard \
        HEAD \
        > /dev/null 2>&1 || true
      release_fail "signed logical commit creation failed: ${source_commit}"
      exit "$COMMIT_RC"
    fi

    prepared_commit="$(release_clean_git -C "$TARGET_WORKTREE" rev-parse HEAD)"
    if ! release_clean_git \
      -C "$TARGET_WORKTREE" \
      verify-commit \
      "$prepared_commit" \
      > /dev/null; then
      release_fail "prepared commit signature verification failed: ${prepared_commit}"
      exit 1
    fi
    if [ "$(release_count_signoffs "$TARGET_WORKTREE" "$prepared_commit")" -ne 1 ] ||
      [ "$(release_count_matching_signoff "$TARGET_WORKTREE" "$prepared_commit")" -ne 1 ]; then
      release_fail "prepared commit must contain exactly one matching sign-off"
      exit 1
    fi
    PREPARED_COMMITS+=("$prepared_commit")
  done

  rm -f -- "$MESSAGE_FILE"
  MESSAGE_FILE=""

  OUTPUT_PARENT="$(dirname "$OUTPUT_ROOT")"
  OUTPUT_BASENAME="$(basename "$OUTPUT_ROOT")"
  STAGING_DIR="$(
    mktemp \
      -d \
      "${OUTPUT_PARENT}/.${OUTPUT_BASENAME}.staging.XXXXXX"
  )"
  mkdir -p "$STAGING_DIR/patches"

  release_clean_git \
    -C "$TARGET_WORKTREE" \
    format-patch \
    --no-signature \
    --output-directory "$STAGING_DIR/patches" \
    "${UPSTREAM_COMMIT}..HEAD" \
    > /dev/null
  FORMAT_RC=$?
  if [ "$FORMAT_RC" -ne 0 ]; then
    release_fail "mail patch export failed"
    exit "$FORMAT_RC"
  fi

  mapfile -t PATCH_PATHS < <(
    find "$STAGING_DIR/patches" \
      -maxdepth 1 \
      -type f \
      -name '*.patch' \
      -print |
      sort
  )
  if [ "${#PATCH_PATHS[@]}" -ne "${#SOURCE_COMMITS[@]}" ]; then
    release_fail "mail patch count differs from logical commit count"
    exit 1
  fi

  : > "$STAGING_DIR/patches/series"
  for patch_path in "${PATCH_PATHS[@]}"; do
    basename "$patch_path" >> "$STAGING_DIR/patches/series"
  done

  ROUND_TRIP_PARENT="$(mktemp -d /tmp/tailscale-version-round-trip.XXXXXX)"
  ROUND_TRIP_WORKTREE="${ROUND_TRIP_PARENT}/worktree"
  release_clean_git \
    -C "$SOURCE_REPO" \
    worktree \
    add \
    --detach \
    "$ROUND_TRIP_WORKTREE" \
    "$UPSTREAM_COMMIT" \
    > /dev/null
  ROUND_WORKTREE_RC=$?
  if [ "$ROUND_WORKTREE_RC" -ne 0 ]; then
    release_fail "round-trip worktree creation failed"
    exit "$ROUND_WORKTREE_RC"
  fi

  release_hookless_git \
    -C "$ROUND_TRIP_WORKTREE" \
    am \
    --3way \
    "${PATCH_PATHS[@]}" \
    > /dev/null
  ROUND_APPLY_RC=$?
  if [ "$ROUND_APPLY_RC" -ne 0 ]; then
    release_hookless_git \
      -C "$ROUND_TRIP_WORKTREE" \
      am \
      --abort \
      > /dev/null 2>&1 || true
    release_fail "mail patch round-trip application failed"
    exit "$ROUND_APPLY_RC"
  fi

  PREPARED_HEAD="$(release_clean_git -C "$TARGET_WORKTREE" rev-parse HEAD)"
  PREPARED_TREE="$(release_clean_git -C "$TARGET_WORKTREE" rev-parse 'HEAD^{tree}')"
  ROUND_TRIP_TREE="$(release_clean_git -C "$ROUND_TRIP_WORKTREE" rev-parse 'HEAD^{tree}')"
  if [ "$ROUND_TRIP_TREE" != "$PREPARED_TREE" ]; then
    release_fail "mail patch round-trip tree differs from the prepared tree"
    exit 1
  fi

  release_clean_git \
    -C "$SOURCE_REPO" \
    worktree \
    remove \
    "$ROUND_TRIP_WORKTREE" \
    > /dev/null
  ROUND_TRIP_WORKTREE=""
  rmdir -- "$ROUND_TRIP_PARENT"
  ROUND_TRIP_PARENT=""

  printf '%s\n' "${SOURCE_COMMITS[@]}" > "$STAGING_DIR/.source-commits"
  printf '%s\n' "${PREPARED_COMMITS[@]}" > "$STAGING_DIR/.prepared-commits"

  python3 - \
    "$STAGING_DIR/manifest.json" \
    "$STAGING_DIR/.source-commits" \
    "$STAGING_DIR/.prepared-commits" \
    "$STAGING_DIR/patches/series" \
    "$STAGING_DIR/patches" \
    "$SOURCE_REPO" \
    "$PREVIOUS_UPSTREAM_COMMIT" \
    "$PREVIOUS_RELEASE_COMMIT" \
    "$UPSTREAM_TAG" \
    "$UPSTREAM_COMMIT" \
    "$NEW_VERSION" \
    "$DOWNSTREAM_REVISION" \
    "$TARGET_BRANCH" \
    "$TARGET_WORKTREE" \
    "$PREPARED_HEAD" \
    "$PREPARED_TREE" \
    "$CONTROL_WORKTREE/release/upgrade-baseline.json" << 'PY'
import hashlib
import json
import subprocess
import sys
from pathlib import Path

(
    manifest_path,
    source_commits_path,
    prepared_commits_path,
    series_path,
    patches_path,
    source_repo,
    previous_upstream,
    previous_release,
    upstream_tag,
    upstream_commit,
    new_version,
    revision,
    branch,
    worktree,
    prepared_head,
    prepared_tree,
    baseline_path,
) = sys.argv[1:]

source_commits = Path(source_commits_path).read_text(encoding="utf-8").splitlines()
prepared_commits = Path(prepared_commits_path).read_text(encoding="utf-8").splitlines()
patch_names = Path(series_path).read_text(encoding="utf-8").splitlines()
baseline = json.loads(Path(baseline_path).read_text(encoding="utf-8"))

logical = []
for order, (source_commit, prepared_commit) in enumerate(
    zip(source_commits, prepared_commits, strict=True), start=1
):
    subject = subprocess.check_output(
        ["git", "-C", source_repo, "show", "-s", "--format=%s", source_commit],
        text=True,
    ).rstrip("\n")
    logical.append(
        {
            "order": order,
            "source_commit": source_commit,
            "prepared_commit": prepared_commit,
            "subject": subject,
        }
    )

patches = []
for order, name in enumerate(patch_names, start=1):
    digest = hashlib.sha256((Path(patches_path) / name).read_bytes()).hexdigest()
    patches.append({"order": order, "filename": name, "sha256": digest})

manifest = {
    "schema_version": 1,
    "source": {
        "repository": source_repo,
        "previous_upstream_commit": previous_upstream,
        "previous_release_commit": previous_release,
    },
    "upstream": {"tag": upstream_tag, "commit": upstream_commit},
    "version": {"upstream": new_version, "downstream_revision": revision},
    "prepared": {
        "branch": branch,
        "commit": prepared_head,
        "tree": prepared_tree,
        "worktree": worktree,
    },
    "logical_commits": logical,
    "patches": patches,
    "synology_contract": baseline["synology_contract"],
    "validation": {
        "source_range_linear": True,
        "signed_commits": True,
        "single_signoff_commits": True,
        "patch_round_trip": True,
        "round_trip_tree": prepared_tree,
    },
    "safety": baseline["safety"],
}
Path(manifest_path).write_text(
    json.dumps(manifest, indent=2) + "\n", encoding="utf-8"
)
PY

  release_validate_version_preparation_manifest \
    "$STAGING_DIR/manifest.json" \
    "$CONTROL_WORKTREE/release/version-preparation.schema.json" \
    "$CONTROL_WORKTREE/release/upgrade-baseline.json" || exit 1

  python3 - \
    "$STAGING_DIR/preparation-report.md" \
    "$STAGING_DIR/manifest.json" << 'PY'
import json
import sys
from pathlib import Path

report_path = Path(sys.argv[1])
manifest = json.loads(Path(sys.argv[2]).read_text(encoding="utf-8"))
lines = [
    "# Synology version preparation evidence",
    "",
    "## Change summary",
    "",
    f"- Upstream: `{manifest['upstream']['tag']}` at `{manifest['upstream']['commit']}`",
    f"- Previous upstream: `{manifest['source']['previous_upstream_commit']}`",
    f"- Previous release: `{manifest['source']['previous_release_commit']}`",
    f"- Prepared branch: `{manifest['prepared']['branch']}`",
    f"- Prepared commit: `{manifest['prepared']['commit']}`",
    f"- Prepared tree: `{manifest['prepared']['tree']}`",
    "",
    "## Ordered logical history",
    "",
]
for item in manifest["logical_commits"]:
    lines.append(
        f"{item['order']}. `{item['source_commit']}` -> "
        f"`{item['prepared_commit']}` — {item['subject']}"
    )
lines.extend(
    [
        "",
        "## Validation evidence",
        "",
        "- Internal commit/apply hooks: disabled",
        "- Source range: linear and ordered",
        "- Prepared commits: signed with one matching sign-off each",
        "- Patch series: mail format with verified SHA-256 digests",
        f"- Round-trip tree: `{manifest['validation']['round_trip_tree']}`",
        "",
        "## Fixed product contract",
        "",
        "- Dependency: `iptables-netfilter-extensions`",
        "- Dependency minimum: `1.1.0-3`",
        "- Dependency and Tailscale DSM minimum: `7.3-86009`",
        "- Production `os_max_ver`: absent",
        "",
        "## Risks and reviewer attention",
        "",
        "Review the range-diff and run source/package/hardware validation separately.",
        "",
        "## Prohibited side effects",
        "",
        "No fetch, push, pull request, tag, SPK build, release, publication, NAS",
        "installation, root bootstrap, firewall mutation or reboot was performed.",
        "",
        "## Verdict",
        "",
        "`PASS — ready for independent source review`",
        "",
    ]
)
report_path.write_text("\n".join(lines), encoding="utf-8")
PY

  rm -f -- "$STAGING_DIR/.source-commits" "$STAGING_DIR/.prepared-commits"
  CHECKSUM_PATHS=(
    manifest.json
    preparation-report.md
    patches/series
  )
  for patch_path in "${PATCH_PATHS[@]}"; do
    CHECKSUM_PATHS+=("patches/$(basename "$patch_path")")
  done
  (
    cd "$STAGING_DIR" || exit 1
    sha256sum "${CHECKSUM_PATHS[@]}" > SHA256SUMS
  ) || {
    release_fail "review artifact checksum generation failed"
    exit 1
  }

  mv \
    --update=none-fail \
    --no-copy \
    --no-target-directory \
    -- \
    "$STAGING_DIR" \
    "$OUTPUT_ROOT"
  INSTALL_RC=$?
  if [ "$INSTALL_RC" -ne 0 ]; then
    release_fail "review artifact installation failed"
    exit "$INSTALL_RC"
  fi
  STAGING_DIR=""

  release_pass "pinned Synology version was prepared in an isolated worktree"
  release_pass "signed logical history and mail patches passed round-trip validation"
  release_notice "no fetch, push, tag, PR, build, publication or NAS action was performed"
)

if [ "${1:-}" = "prepare-version" ]; then
  shift
  prepare_version "$@"
  exit $?
fi

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
PATCH_RELATIVE="$(release_manifest_get "$MANIFEST" paths.patch_series)"
PATCH_ROOT="$(release_resolve_path "$CONTROL_WORKTREE" "$PATCH_RELATIVE")"

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

PATCH_COUNT="$(
  find \
    "$PATCH_ROOT" \
    -maxdepth 1 \
    -type f \
    -name '*.patch' \
    -print |
    wc \
      -l |
    tr \
      -d \
      ' '
)"

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
  release_apply_patch_series \
    "$TARGET_WORKTREE" \
    "$MANIFEST" \
    "$PATCH_ROOT" \
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
