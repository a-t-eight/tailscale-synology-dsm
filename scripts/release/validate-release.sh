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
SOURCE_WORKTREE=""
MANIFEST=""
ROLE="accepted"
FAST=0
ROUND_TRIP=0
FAILURES=0
TEMP_WORKTREE=""
TEMP_ALLOWED_SIGNERS=""

usage() {
  cat << 'USAGE'
Usage:
  bash scripts/release/validate-release.sh \
    --source-worktree PATH \
    [--control-worktree PATH] \
    [--manifest PATH] \
    [--role upstream|work|release|accepted] \
    [--fast] \
    [--round-trip]
USAGE
}

# shellcheck disable=SC2329 # Invoked by the EXIT trap below.
cleanup() {
  if [ -n "$TEMP_WORKTREE" ] &&
    [ -e "$TEMP_WORKTREE" ]; then
    release_clean_git \
      -C "$SOURCE_WORKTREE" \
      worktree \
      remove \
      --force \
      "$TEMP_WORKTREE" \
      > /dev/null \
      2>&1 ||
      true
  fi

  if [ -n "$TEMP_ALLOWED_SIGNERS" ] &&
    [ -f "$TEMP_ALLOWED_SIGNERS" ]; then
    rm \
      -f \
      -- \
      "$TEMP_ALLOWED_SIGNERS"
  fi
}

trap cleanup EXIT

while [ "$#" -gt 0 ]; do
  case "$1" in
    --control-worktree)
      CONTROL_WORKTREE="$2"
      shift
      ;;
    --source-worktree)
      SOURCE_WORKTREE="$2"
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
    --fast)
      FAST=1
      ;;
    --round-trip)
      ROUND_TRIP=1
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

case "$ROLE" in
  upstream | work | release | accepted)
    ;;
  *)
    release_fail "unsupported release role: ${ROLE}"
    exit 2
    ;;
esac

if [ -z "$SOURCE_WORKTREE" ]; then
  release_fail "--source-worktree is required"
  exit 2
fi

if [ -z "$MANIFEST" ]; then
  MANIFEST="${CONTROL_WORKTREE}/release/manifest.yaml"
fi

release_require_worktree "$CONTROL_WORKTREE" || exit 1
release_require_worktree "$SOURCE_WORKTREE" || exit 1
release_validate_manifest "$MANIFEST" || exit 1

UPSTREAM_COMMIT="$(release_manifest_get "$MANIFEST" upstream.commit)"
RELEASE_COMMIT="$(release_manifest_get "$MANIFEST" downstream.release_commit)"
RELEASE_TREE="$(release_manifest_get "$MANIFEST" downstream.release_tree)"
WORK_BRANCH="$(release_manifest_get "$MANIFEST" branches.work)"
RELEASE_BRANCH="$(release_manifest_get "$MANIFEST" branches.release)"
PATCH_RELATIVE="$(release_manifest_get "$MANIFEST" paths.patch_series)"
PATCH_ROOT="$(release_resolve_path "$CONTROL_WORKTREE" "$PATCH_RELATIVE")"

SSH_ALLOWED_SIGNERS_RELATIVE="$(
  release_manifest_get \
    "$MANIFEST" \
    validation.ssh_allowed_signers_path
)"

EXPECTED_SSH_ALLOWED_SIGNERS_SHA256="$(
  release_manifest_get \
    "$MANIFEST" \
    validation.ssh_allowed_signers_sha256
)"

SSH_TRUST_BOOTSTRAP_BASE_COMMIT="$(
  release_manifest_get \
    "$MANIFEST" \
    validation.ssh_trust_bootstrap_base_commit
)"

CONTROL_BASELINE_COMMIT="$(
  release_manifest_get \
    "$MANIFEST" \
    control.governance_baseline_commit
)"

mapfile -t EXPECTED_SSH_FINGERPRINTS < <(
  release_manifest_array \
    "$MANIFEST" \
    validation.ssh_signer_fingerprints
)

mapfile -t EXPECTED_SSH_PRINCIPALS < <(
  release_manifest_array \
    "$MANIFEST" \
    validation.ssh_signer_principals
)

SHA256SUM="$(command -v sha256sum || true)"

if [ -z "$SHA256SUM" ]; then
  release_fail "sha256sum is required"
  exit 1
fi

CONTROL_ALLOWED_SIGNERS="$(
  release_resolve_path \
    "$CONTROL_WORKTREE" \
    "$SSH_ALLOWED_SIGNERS_RELATIVE"
)"

PROTECTED_BASE_WORKTREE="${RELEASE_PROTECTED_BASE_WORKTREE:-}"
BOOTSTRAP_ALLOWED_SIGNERS_SHA256="${RELEASE_ALLOWED_SIGNERS_SHA256:-}"
SELECTED_ALLOWED_SIGNERS=""
SIGNER_TRUST_SOURCE=""

if [ -n "$PROTECTED_BASE_WORKTREE" ]; then
  release_require_worktree "$PROTECTED_BASE_WORKTREE" || exit 1
  release_require_clean_worktree "$PROTECTED_BASE_WORKTREE" || exit 1

  PROTECTED_BASE_HEAD="$(
    release_clean_git \
      -C "$PROTECTED_BASE_WORKTREE" \
      rev-parse \
      HEAD
  )"

  if ! release_clean_git \
    -C "$PROTECTED_BASE_WORKTREE" \
    merge-base \
    --is-ancestor \
    "$CONTROL_BASELINE_COMMIT" \
    "$PROTECTED_BASE_HEAD"; then
    release_fail \
      "protected base does not descend from the governance baseline"
    exit 1
  fi

  PROTECTED_ALLOWED_SIGNERS="$(
    release_resolve_path \
      "$PROTECTED_BASE_WORKTREE" \
      "$SSH_ALLOWED_SIGNERS_RELATIVE"
  )"

  if [ -f "$PROTECTED_ALLOWED_SIGNERS" ]; then
    SELECTED_ALLOWED_SIGNERS="$PROTECTED_ALLOWED_SIGNERS"
    SIGNER_TRUST_SOURCE="protected base"
  else
    if [ "$PROTECTED_BASE_HEAD" != "$SSH_TRUST_BOOTSTRAP_BASE_COMMIT" ]; then
      release_fail \
        "protected base lacks allowed_signers outside the bootstrap commit"
      exit 1
    fi

    if [ -z "$BOOTSTRAP_ALLOWED_SIGNERS_SHA256" ]; then
      release_fail \
        "one-time allowed-signers bootstrap SHA-256 is unavailable"
      exit 1
    fi

    CONTROL_SHA="$(
      "$SHA256SUM" \
        "$CONTROL_ALLOWED_SIGNERS" |
        awk \
          '{ print $1 }'
    )"

    if [ "$CONTROL_SHA" != "$BOOTSTRAP_ALLOWED_SIGNERS_SHA256" ]; then
      release_fail \
        "control allowed_signers does not match the repository variable"
      exit 1
    fi

    SELECTED_ALLOWED_SIGNERS="$CONTROL_ALLOWED_SIGNERS"
    SIGNER_TRUST_SOURCE="one-time repository-variable bootstrap"
  fi
else
  SELECTED_ALLOWED_SIGNERS="$CONTROL_ALLOWED_SIGNERS"
  SIGNER_TRUST_SOURCE="local control worktree"
fi

SELECTED_SHA="$(
  "$SHA256SUM" \
    "$SELECTED_ALLOWED_SIGNERS" |
    awk \
      '{ print $1 }'
)"

if [ "$SELECTED_SHA" != "$EXPECTED_SSH_ALLOWED_SIGNERS_SHA256" ]; then
  release_fail \
    "selected allowed_signers differs from the manifest SHA-256"
  exit 1
fi

TEMP_ALLOWED_SIGNERS="$(
  mktemp \
    "${TMPDIR:-/tmp}/tailscale-release-allowed-signers.XXXXXX"
)"

install \
  -m \
  0600 \
  "$SELECTED_ALLOWED_SIGNERS" \
  "$TEMP_ALLOWED_SIGNERS"

printf 'SSH trust source:    %s\n' "$SIGNER_TRUST_SOURCE"
printf 'SSH trust SHA-256:   %s\n' "$SELECTED_SHA"
printf 'Pinned fingerprints: %s\n' \
  "${#EXPECTED_SSH_FINGERPRINTS[@]}"
printf 'Pinned principals:   %s\n' \
  "${#EXPECTED_SSH_PRINCIPALS[@]}"

HEAD_COMMIT="$(
  release_clean_git \
    -C "$SOURCE_WORKTREE" \
    rev-parse \
    HEAD
)"

HEAD_TREE="$(
  release_clean_git \
    -C "$SOURCE_WORKTREE" \
    rev-parse \
    'HEAD^{tree}'
)"

HEAD_BRANCH="$(
  release_clean_git \
    -C "$SOURCE_WORKTREE" \
    branch \
    --show-current
)"

printf '=== Release source identity ===\n'
printf 'Role:             %s\n' "$ROLE"
printf 'Source worktree:  %s\n' "$SOURCE_WORKTREE"
printf 'HEAD commit:      %s\n' "$HEAD_COMMIT"
printf 'HEAD tree:        %s\n' "$HEAD_TREE"
printf 'HEAD branch:      %s\n' "${HEAD_BRANCH:-detached}"
printf 'Upstream commit:  %s\n' "$UPSTREAM_COMMIT"
printf 'Release commit:   %s\n' "$RELEASE_COMMIT"
printf 'Release tree:     %s\n' "$RELEASE_TREE"

if release_require_clean_worktree "$SOURCE_WORKTREE"; then
  release_pass "source worktree is clean."
else
  FAILURES=$((FAILURES + 1))
fi

case "$ROLE" in
  upstream)
    if [ "$HEAD_COMMIT" != "$UPSTREAM_COMMIT" ]; then
      release_fail "upstream role HEAD differs from the pinned upstream commit"
      FAILURES=$((FAILURES + 1))
    else
      release_pass "upstream role HEAD matches."
    fi
    ;;
  accepted)
    if [ "$HEAD_COMMIT" != "$RELEASE_COMMIT" ]; then
      release_fail "accepted role HEAD differs from the release commit"
      FAILURES=$((FAILURES + 1))
    else
      release_pass "accepted role HEAD matches."
    fi

    if [ "$HEAD_TREE" != "$RELEASE_TREE" ]; then
      release_fail "accepted role tree differs from the release tree"
      FAILURES=$((FAILURES + 1))
    else
      release_pass "accepted role tree matches."
    fi
    ;;
  work)
    if [ "$HEAD_BRANCH" != "$WORK_BRANCH" ]; then
      release_fail "work role branch differs from the manifest"
      FAILURES=$((FAILURES + 1))
    else
      release_pass "work role branch matches."
    fi
    ;;
  release)
    if [ "$HEAD_BRANCH" != "$RELEASE_BRANCH" ]; then
      release_fail "release role branch differs from the manifest"
      FAILURES=$((FAILURES + 1))
    else
      release_pass "release role branch matches."
    fi
    ;;
esac

if [ "$ROLE" != "upstream" ]; then
  if release_clean_git \
    -C "$SOURCE_WORKTREE" \
    merge-base \
    --is-ancestor \
    "$UPSTREAM_COMMIT" \
    "$HEAD_COMMIT"; then
    release_pass "source HEAD descends from the pinned upstream commit."
  else
    release_fail "source HEAD does not descend from the upstream commit"
    FAILURES=$((FAILURES + 1))
  fi
fi

printf '\n=== Downstream commit integrity ===\n'

is_legacy_no_signoff_commit() {
  candidate="$1"
  listed_commit=""

  for listed_commit in "${LEGACY_NO_SIGNOFF_COMMITS[@]}"; do
    if [ "$candidate" = "$listed_commit" ]; then
      return 0
    fi
  done

  return 1
}

array_contains() {
  candidate="$1"
  shift
  listed=""

  for listed in "$@"; do
    if [ "$candidate" = "$listed" ]; then
      return 0
    fi
  done

  return 1
}

mapfile -t LEGACY_NO_SIGNOFF_COMMITS < <(
  release_manifest_array \
    "$MANIFEST" \
    validation.accepted_legacy_no_signoff_commits
)

if [ "$ROLE" = "accepted" ] ||
  [ "$ROLE" = "release" ]; then
  signature_failures=0
  signoff_failures=0
  OBSERVED_LEGACY_NO_SIGNOFF=()
  OBSERVED_SSH_FINGERPRINTS=()
  OBSERVED_SSH_PRINCIPALS=()

  while IFS= read -r commit; do
    [ -n "$commit" ] || continue

    signature_record="$(
      release_clean_git \
        -c "gpg.ssh.allowedSignersFile=${TEMP_ALLOWED_SIGNERS}" \
        -C "$SOURCE_WORKTREE" \
        show \
        -s \
        --format='%G?%x09%GF%x09%GS' \
        "$commit"
    )"

    IFS=$'\t' read \
      -r \
      signature \
      signature_fingerprint \
      signature_principal \
      <<< "$signature_record"

    signoff_count="$(
      release_count_matching_signoff \
        "$SOURCE_WORKTREE" \
        "$commit"
    )"

    if [ "$signature" != "G" ]; then
      release_fail "downstream commit has signature status ${signature}: ${commit}"
      signature_failures=$((signature_failures + 1))
      FAILURES=$((FAILURES + 1))
    elif ! array_contains \
      "$signature_fingerprint" \
      "${EXPECTED_SSH_FINGERPRINTS[@]}"; then
      release_fail \
        "downstream commit uses an unpinned SSH fingerprint: ${commit}"
      signature_failures=$((signature_failures + 1))
      FAILURES=$((FAILURES + 1))
    elif ! array_contains \
      "$signature_principal" \
      "${EXPECTED_SSH_PRINCIPALS[@]}"; then
      release_fail \
        "downstream commit uses an unpinned SSH principal: ${commit}"
      signature_failures=$((signature_failures + 1))
      FAILURES=$((FAILURES + 1))
    else
      OBSERVED_SSH_FINGERPRINTS+=("$signature_fingerprint")
      OBSERVED_SSH_PRINCIPALS+=("$signature_principal")
    fi

    if [ "$signoff_count" -eq 1 ]; then
      continue
    fi

    if [ "$ROLE" = "accepted" ] &&
      [ "$signoff_count" -eq 0 ] &&
      is_legacy_no_signoff_commit "$commit"; then
      OBSERVED_LEGACY_NO_SIGNOFF+=("$commit")
      release_notice \
        "accepted immutable baseline grandfathers missing sign-off: ${commit}"
      continue
    fi

    release_fail \
      "downstream commit has ${signoff_count} matching sign-offs: ${commit}"
    signoff_failures=$((signoff_failures + 1))
    FAILURES=$((FAILURES + 1))
  done < <(
    release_clean_git \
      -C "$SOURCE_WORKTREE" \
      rev-list \
      --reverse \
      "${UPSTREAM_COMMIT}..${HEAD_COMMIT}"
  )

  EXPECTED_SSH_FINGERPRINT_TEXT="$(
    printf '%s\n' \
      "${EXPECTED_SSH_FINGERPRINTS[@]}" |
      sort -u
  )"

  OBSERVED_SSH_FINGERPRINT_TEXT="$(
    printf '%s\n' \
      "${OBSERVED_SSH_FINGERPRINTS[@]}" |
      sort -u
  )"

  EXPECTED_SSH_PRINCIPAL_TEXT="$(
    printf '%s\n' \
      "${EXPECTED_SSH_PRINCIPALS[@]}" |
      sort -u
  )"

  OBSERVED_SSH_PRINCIPAL_TEXT="$(
    printf '%s\n' \
      "${OBSERVED_SSH_PRINCIPALS[@]}" |
      sort -u
  )"

  if [ "$EXPECTED_SSH_FINGERPRINT_TEXT" != "$OBSERVED_SSH_FINGERPRINT_TEXT" ]; then
    release_fail \
      "observed SSH signer fingerprints differ from the manifest"
    FAILURES=$((FAILURES + 1))
  else
    release_pass \
      "observed SSH signer fingerprints match the manifest."
  fi

  if [ "$EXPECTED_SSH_PRINCIPAL_TEXT" != "$OBSERVED_SSH_PRINCIPAL_TEXT" ]; then
    release_fail \
      "observed SSH signer principals differ from the manifest"
    FAILURES=$((FAILURES + 1))
  else
    release_pass \
      "observed SSH signer principals match the manifest."
  fi

  if [ "$ROLE" = "accepted" ]; then
    EXPECTED_LEGACY_TEXT="$(
      printf '%s\n' \
        "${LEGACY_NO_SIGNOFF_COMMITS[@]}" |
        sort
    )"

    OBSERVED_LEGACY_TEXT="$(
      printf '%s\n' \
        "${OBSERVED_LEGACY_NO_SIGNOFF[@]}" |
        sort
    )"

    if [ "$EXPECTED_LEGACY_TEXT" != "$OBSERVED_LEGACY_TEXT" ]; then
      printf 'Expected legacy no-signoff commits:\n%s\n' \
        "$EXPECTED_LEGACY_TEXT"
      printf 'Observed legacy no-signoff commits:\n%s\n' \
        "$OBSERVED_LEGACY_TEXT"

      release_fail \
        "accepted legacy sign-off exception set differs from the manifest"
      FAILURES=$((FAILURES + 1))
    else
      release_pass \
        "accepted legacy sign-off exceptions match the exact manifest list."
    fi
  elif [ "${#LEGACY_NO_SIGNOFF_COMMITS[@]}" -gt 0 ]; then
    release_notice \
      "accepted legacy exceptions do not apply to a new release stack."
  fi

  if [ "$signature_failures" -eq 0 ]; then
    release_pass "all downstream commits have good signatures."
  fi

  if [ "$signoff_failures" -eq 0 ] &&
    [ "$ROLE" = "release" ]; then
    release_pass "all release commits contain exactly one matching sign-off."
  fi
else
  release_notice "commit-integrity enforcement is deferred for the work role."
fi

printf '\n=== Synology shell syntax ===\n'

SHELL_PATHS=()

while IFS= read -r -d '' path; do
  SHELL_PATHS+=("$path")
done < <(
  find \
    "$SOURCE_WORKTREE/release/dist/synology" \
    "$SOURCE_WORKTREE/cmd/tailscale/cli" \
    -type f \
    \( \
    -name '*.sh' \
    -o \
    -name '*.bash' \
    \) \
    -print0 \
    2> /dev/null
)

for relative in $(
  release_clean_git \
    -C "$SOURCE_WORKTREE" \
    diff \
    --name-only \
    "${UPSTREAM_COMMIT}..${HEAD_COMMIT}" |
    grep \
      -E \
      '\.(sh|bash)$' ||
    true
); do
  if [ -f "$SOURCE_WORKTREE/$relative" ]; then
    SHELL_PATHS+=("$SOURCE_WORKTREE/$relative")
  fi
done

shell_failures=0

for path in "${SHELL_PATHS[@]}"; do
  if ! bash \
    -n \
    "$path"; then
    release_fail "shell syntax failed: ${path}"
    shell_failures=$((shell_failures + 1))
  fi
done

if [ "$shell_failures" -eq 0 ]; then
  release_pass "inventoried Synology shell syntax passed."
else
  FAILURES=$((FAILURES + shell_failures))
fi

if [ "$FAST" -eq 0 ]; then
  printf '\n=== Repository-pinned Go tests ===\n'

  if [ ! -x "$SOURCE_WORKTREE/tool/go" ]; then
    release_fail "source worktree does not expose executable ./tool/go"
    FAILURES=$((FAILURES + 1))
  else
    while IFS= read -r package; do
      [ -n "$package" ] || continue

      printf 'Testing package: %s\n' "$package"

      (
        cd \
          "$SOURCE_WORKTREE" &&
          ./tool/go \
            test \
            "$package"
      )

      test_rc=$?

      if [ "$test_rc" -ne 0 ]; then
        release_fail "Go test failed for ${package}"
        FAILURES=$((FAILURES + 1))
      fi
    done < <(
      release_manifest_array \
        "$MANIFEST" \
        validation.go_packages
    )
  fi
else
  release_notice "Go tests were skipped by --fast."
fi

if [ "$ROUND_TRIP" -eq 1 ]; then
  printf '\n=== Patch round-trip ===\n'

  if ! release_validate_patch_inventory \
    "$MANIFEST" \
    "$PATCH_ROOT"; then
    release_fail "patch round-trip inventory differs"
    FAILURES=$((FAILURES + 1))
  else
    TEMP_WORKTREE="$(
      mktemp \
        -d \
        "${TMPDIR:-/tmp}/tailscale-release-round-trip.XXXXXX"
    )"

    rmdir "$TEMP_WORKTREE"

    release_clean_git \
      -C "$SOURCE_WORKTREE" \
      worktree \
      add \
      --detach \
      "$TEMP_WORKTREE" \
      "$UPSTREAM_COMMIT"

    add_rc=$?

    if [ "$add_rc" -ne 0 ]; then
      release_fail "round-trip worktree creation failed"
      FAILURES=$((FAILURES + 1))
    elif ! release_check_reference_patches_forward \
      "$TEMP_WORKTREE" \
      "$MANIFEST" \
      "$PATCH_ROOT"; then
      release_fail "reference patch validation against upstream failed"
      FAILURES=$((FAILURES + 1))
    else
      release_apply_patch_series \
        "$TEMP_WORKTREE" \
        "$MANIFEST" \
        "$PATCH_ROOT" \
        round-trip

      apply_rc=$?

      if [ "$apply_rc" -ne 0 ]; then
        release_fail "declared aggregate patch set did not apply cleanly"
        FAILURES=$((FAILURES + 1))
      elif ! release_check_reference_patches_reverse \
        "$TEMP_WORKTREE" \
        "$MANIFEST" \
        "$PATCH_ROOT"; then
        release_fail "reference patch is not contained in the aggregate result"
        FAILURES=$((FAILURES + 1))
      else
        ROUND_TRIP_TREE="$(
          release_clean_git \
            -C "$TEMP_WORKTREE" \
            write-tree
        )"

        printf 'Round-trip tree: %s\n' "$ROUND_TRIP_TREE"

        if [ "$ROUND_TRIP_TREE" != "$HEAD_TREE" ]; then
          release_fail "patch round-trip tree differs from source HEAD"
          FAILURES=$((FAILURES + 1))
        else
          release_pass "declared aggregate patch reproduces the exact source tree."
        fi
      fi
    fi
  fi

fi

printf '\n=== Release validation result ===\n'
printf 'Failures: %s\n' "$FAILURES"

if [ "$FAILURES" -eq 0 ]; then
  echo "PASS: release source validation completed."
  echo "NOTICE: no source commit, patch, branch, package or evidence was changed."
else
  echo "STOP: release source validation failed."
fi

exit "$FAILURES"
