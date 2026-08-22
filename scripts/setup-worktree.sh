#!/usr/bin/env bash
set -u

WORKTREE=""
CONTROL_WORKTREE=""
ROLE=""
MIGRATE_COMMON=0
DRY_RUN=0

usage() {
  cat << 'USAGE'
Usage:
  bash scripts/setup-worktree.sh \
    --worktree PATH \
    --control-worktree PATH \
    --role control|accepted|work|release \
    [--migrate-common-hooks] \
    [--dry-run]

Control worktrees use their own committed .githooks directory. Source, work and
release worktrees receive generated wrappers in the common Git directory.
USAGE
}

fail() {
  printf 'FAIL: %s\n' "$1" >&2
}

clean_git() {
  (
    variable=""

    while IFS= read -r variable; do
      unset "$variable"
    done < <(
      git \
        rev-parse \
        --local-env-vars
    )

    command \
      git \
      "$@"
  )
}

while [ "$#" -gt 0 ]; do
  case "$1" in
    --worktree)
      WORKTREE="$2"
      shift
      ;;
    --control-worktree)
      CONTROL_WORKTREE="$2"
      shift
      ;;
    --role)
      ROLE="$2"
      shift
      ;;
    --migrate-common-hooks)
      MIGRATE_COMMON=1
      ;;
    --dry-run)
      DRY_RUN=1
      ;;
    --help | -h)
      usage
      exit 0
      ;;
    *)
      fail "unsupported option: $1"
      usage >&2
      exit 2
      ;;
  esac
  shift
done

case "$ROLE" in
  control | accepted | work | release)
    ;;
  *)
    fail "--role must be control, accepted, work or release"
    exit 2
    ;;
esac

for path in "$WORKTREE" "$CONTROL_WORKTREE"; do
  if [ ! -d "$path/.git" ] &&
    [ ! -f "$path/.git" ]; then
    fail "path is not a Git worktree: ${path}"
    exit 1
  fi
done

if [ ! -x "$CONTROL_WORKTREE/.githooks/pre-commit" ] ||
  [ ! -x "$CONTROL_WORKTREE/.githooks/commit-msg" ]; then
  fail "control worktree does not contain executable repository hooks"
  exit 1
fi

COMMON_DIR="$(
  clean_git \
    -C "$WORKTREE" \
    rev-parse \
    --path-format=absolute \
    --git-common-dir
)"

WORKTREE_ROOT="$(
  clean_git \
    -C "$WORKTREE" \
    rev-parse \
    --show-toplevel
)"

path_id="$(
  printf '%s\n' \
    "$WORKTREE_ROOT" |
    sha256sum |
    awk \
      '{ print substr($1, 1, 16) }'
)"

if [ "$ROLE" = "control" ]; then
  HOOKS_PATH="${WORKTREE_ROOT}/.githooks"
else
  HOOKS_PATH="${COMMON_DIR}/release-hooks/${ROLE}-${path_id}"
fi

printf '=== Worktree configuration plan ===\n'
printf 'Worktree:           %s\n' "$WORKTREE_ROOT"
printf 'Control worktree:   %s\n' "$CONTROL_WORKTREE"
printf 'Role:               %s\n' "$ROLE"
printf 'Common Git dir:     %s\n' "$COMMON_DIR"
printf 'Hooks path:         %s\n' "$HOOKS_PATH"
printf 'Migrate common path:%s\n' " $MIGRATE_COMMON"

if [ "$DRY_RUN" -eq 1 ]; then
  echo "PASS: worktree configuration plan is valid."
  echo "NOTICE: no Git configuration or hook wrapper was changed."
  exit 0
fi

clean_git \
  -C "$WORKTREE" \
  config \
  extensions.worktreeConfig \
  true

if [ "$MIGRATE_COMMON" -eq 1 ]; then
  common_hooks="$(
    clean_git \
      -C "$WORKTREE" \
      config \
      --get \
      core.hooksPath \
      2> /dev/null ||
      true
  )"

  if [ -n "$common_hooks" ] &&
    [ "$common_hooks" != ".githooks" ]; then
    fail "common core.hooksPath has an unexpected value: ${common_hooks}"
    exit 1
  fi

  if [ "$common_hooks" = ".githooks" ]; then
    clean_git \
      -C "$WORKTREE" \
      config \
      --unset-all \
      core.hooksPath
  fi
fi

if [ "$ROLE" != "control" ]; then
  mkdir -p \
    "$HOOKS_PATH"

  cat > "$HOOKS_PATH/commit-msg" << EOF
#!/usr/bin/env bash
exec \\
  "${CONTROL_WORKTREE}/.githooks/commit-msg" \\
  "\$@"
EOF

  cat > "$HOOKS_PATH/pre-commit" << EOF
#!/usr/bin/env bash
exec \\
  bash \\
  "${CONTROL_WORKTREE}/scripts/release/validate-release.sh" \\
  --control-worktree \\
  "${CONTROL_WORKTREE}" \\
  --source-worktree \\
  "${WORKTREE_ROOT}" \\
  --role \\
  "${ROLE}" \\
  --fast
EOF

  chmod \
    0755 \
    "$HOOKS_PATH/commit-msg" \
    "$HOOKS_PATH/pre-commit"
fi

clean_git \
  -C "$WORKTREE" \
  config \
  --worktree \
  core.hooksPath \
  "$HOOKS_PATH"

clean_git \
  -C "$WORKTREE" \
  config \
  --worktree \
  commit.gpgsign \
  true

clean_git \
  -C "$WORKTREE" \
  config \
  --worktree \
  tag.gpgsign \
  true

observed_hooks="$(
  clean_git \
    -C "$WORKTREE" \
    config \
    --worktree \
    --get \
    core.hooksPath
)"

observed_commit_signing="$(
  clean_git \
    -C "$WORKTREE" \
    config \
    --worktree \
    --bool \
    --get \
    commit.gpgsign
)"

observed_tag_signing="$(
  clean_git \
    -C "$WORKTREE" \
    config \
    --worktree \
    --bool \
    --get \
    tag.gpgsign
)"

if [ "$observed_hooks" != "$HOOKS_PATH" ] ||
  [ "$observed_commit_signing" != "true" ] ||
  [ "$observed_tag_signing" != "true" ]; then
  fail "worktree Git configuration did not converge"
  exit 1
fi

echo "PASS: worktree-specific hooks and signing were configured."
