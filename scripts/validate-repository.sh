#!/usr/bin/env bash
set -u

SOURCE_ENV_COMMIT="f49613eccf9350583cc328183f192a591cd76348"
SOURCE_ENV_TREE="44c0bc3cd3bbcd3eb70cacf34e9611909a38bd10"

SHELLCHECK_VERSION="v0.11.0"
SHFMT_VERSION="v3.13.1"
ACTIONLINT_VERSION="v1.7.12"
GITLEAKS_VERSION="v8.30.1"

REPO_ROOT="$(
  cd \
    "$(dirname "${BASH_SOURCE[0]}")/.." &&
    pwd
)"

SOURCE_ENV_ROOT="${TAILSCALE_SOURCE_ENVIRONMENT:-}"

CACHE_ROOT="${XDG_CACHE_HOME:-${HOME}/.cache}/tailscale-synology-dsm/governance-tools"
TOOLSET_ID="$(uname -s)-$(uname -m)-go-${SOURCE_ENV_COMMIT}-shellcheck-${SHELLCHECK_VERSION#v}-shfmt-${SHFMT_VERSION#v}-actionlint-${ACTIONLINT_VERSION#v}-gitleaks-${GITLEAKS_VERSION#v}"
BIN_ROOT="${CACHE_ROOT}/${TOOLSET_ID}/bin"
TEXT_VALIDATOR="${CACHE_ROOT}/${TOOLSET_ID}/validate-text.go"

BOOTSTRAP=0
FAST=0
FORMAT_MANAGED=0
STAGED_SECRETS=0
FAILURES=0

usage() {
  cat << 'USAGE'
Usage:
  bash scripts/validate-repository.sh \
    [--source-environment /path/to/exact-release-worktree] \
    [--bootstrap] \
    [--fast] \
    [--format-managed] \
    [--staged-secrets]

Options:
  --source-environment
      Exact Tailscale release worktree that provides the repository-pinned
      ./tool/go entry point. When omitted, discover exactly one clean registered
      worktree at the pinned release commit and tree.

  --bootstrap
      Install missing pinned validators into the user cache. Every Go tool is
      built through the supplied source environment's ./tool/go.

  --fast
      Perform no network access. Require all validators to be cached.

  --format-managed
      Format the complete repository-owned control-tree shell inventory.

  --staged-secrets
      Scan only the staged Git diff for secrets. This mode is used by the
      repository-owned pre-commit hook.
USAGE
}

while [ "$#" -gt 0 ]; do
  case "$1" in
    --source-environment)
      if [ "$#" -lt 2 ]; then
        echo "FAIL: --source-environment requires a path." >&2
        exit 2
      fi

      SOURCE_ENV_ROOT="$2"
      shift
      ;;
    --bootstrap)
      BOOTSTRAP=1
      ;;
    --fast)
      FAST=1
      ;;
    --format-managed)
      FORMAT_MANAGED=1
      ;;
    --staged-secrets)
      STAGED_SECRETS=1
      ;;
    --help | -h)
      usage
      exit 0
      ;;
    *)
      printf 'FAIL: unsupported option: %s\n' "$1" >&2
      usage >&2
      exit 2
      ;;
  esac

  shift
done

if [ "$BOOTSTRAP" -eq 1 ] &&
  [ "$FAST" -eq 1 ]; then
  echo "FAIL: --bootstrap and --fast are mutually exclusive." >&2
  exit 2
fi

fail_check() {
  printf 'FAIL: %s\n' "$1"
  FAILURES=$((FAILURES + 1))
}

pass_check() {
  printf 'PASS: %s\n' "$1"
}

require_command() {
  command_name="$1"

  if command \
    -v \
    "$command_name" \
    > /dev/null \
    2>&1; then
    return 0
  fi

  fail_check "required command is unavailable: ${command_name}"
  return 1
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

discover_source_environment() {
  candidates=()
  current_path=""
  current_head=""

  while IFS= read -r line; do
    case "$line" in
      worktree\ *)
        current_path="${line#worktree }"
        ;;
      HEAD\ *)
        current_head="${line#HEAD }"
        ;;
      '')
        if [ "$current_head" = "$SOURCE_ENV_COMMIT" ] &&
          [ -n "$current_path" ] &&
          [ -x "${current_path}/tool/go" ]; then
          candidate_tree="$(
            clean_git \
              -C "$current_path" \
              rev-parse \
              'HEAD^{tree}' \
              2> /dev/null ||
              true
          )"

          candidate_status="$(
            clean_git \
              -C "$current_path" \
              status \
              --short \
              --untracked-files=all \
              2> /dev/null ||
              true
          )"

          if [ "$candidate_tree" = "$SOURCE_ENV_TREE" ] &&
            [ -z "$candidate_status" ]; then
            candidates+=("$current_path")
          fi
        fi

        current_path=""
        current_head=""
        ;;
    esac
  done < <(
    clean_git \
      -C "$REPO_ROOT" \
      worktree \
      list \
      --porcelain

    printf '\n'
  )

  if [ "${#candidates[@]}" -eq 1 ]; then
    SOURCE_ENV_ROOT="${candidates[0]}"
    printf 'Auto-discovered source environment: %s\n' "$SOURCE_ENV_ROOT"
    return 0
  fi

  if [ "${#candidates[@]}" -eq 0 ]; then
    echo \
      "FAIL: no clean registered worktree matches the pinned source commit and tree." \
      >&2
    return 1
  fi

  printf \
    'FAIL: %s clean registered worktrees match the pinned source environment; pass --source-environment explicitly.\n' \
    "${#candidates[@]}" \
    >&2
  printf 'Candidates:\n' >&2
  printf '  %s\n' "${candidates[@]}" >&2
  return 1
}

if [ -z "$SOURCE_ENV_ROOT" ]; then
  if ! discover_source_environment; then
    usage >&2
    exit 1
  fi
fi

if [ ! -d "$SOURCE_ENV_ROOT/.git" ] &&
  [ ! -f "$SOURCE_ENV_ROOT/.git" ]; then
  echo "FAIL: source environment is not a Git worktree: ${SOURCE_ENV_ROOT}" >&2
  exit 1
fi

PINNED_GO="${SOURCE_ENV_ROOT}/tool/go"

if [ ! -x "$PINNED_GO" ]; then
  echo "FAIL: repository-pinned Go entry point is unavailable: ${PINNED_GO}" >&2
  exit 1
fi

SOURCE_ENV_HEAD="$(
  clean_git \
    -C "$SOURCE_ENV_ROOT" \
    rev-parse \
    HEAD
)"

SOURCE_ENV_TREE_ACTUAL="$(
  clean_git \
    -C "$SOURCE_ENV_ROOT" \
    rev-parse \
    'HEAD^{tree}'
)"

SOURCE_ENV_STATUS="$(
  clean_git \
    -C "$SOURCE_ENV_ROOT" \
    status \
    --short \
    --untracked-files=all
)"

if [ "$SOURCE_ENV_HEAD" != "$SOURCE_ENV_COMMIT" ]; then
  echo \
    "FAIL: source environment HEAD is ${SOURCE_ENV_HEAD}, expected ${SOURCE_ENV_COMMIT}." \
    >&2
  exit 1
fi

if [ "$SOURCE_ENV_TREE_ACTUAL" != "$SOURCE_ENV_TREE" ]; then
  echo \
    "FAIL: source environment tree is ${SOURCE_ENV_TREE_ACTUAL}, expected ${SOURCE_ENV_TREE}." \
    >&2
  exit 1
fi

if [ -n "$SOURCE_ENV_STATUS" ]; then
  printf 'Observed source-environment status:\n%s\n' "$SOURCE_ENV_STATUS" >&2
  echo "FAIL: source environment is not clean." >&2
  exit 1
fi

printf '=== Repository-pinned build environment ===\n'
printf 'Source environment: %s\n' "$SOURCE_ENV_ROOT"
printf 'Source commit:      %s\n' "$SOURCE_ENV_HEAD"
printf 'Source tree:        %s\n' "$SOURCE_ENV_TREE_ACTUAL"
printf 'Pinned Go:          %s\n' "$PINNED_GO"
printf 'Pinned Go version:  %s\n' "$("$PINNED_GO" version)"

github_api() {
  api_path="$1"

  if [ -n "${GH_TOKEN:-}" ]; then
    GH_TOKEN="$GH_TOKEN" \
      gh \
      api \
      "$api_path"
  else
    gh \
      api \
      "$api_path"
  fi
}

install_shellcheck() {
  mkdir -p \
    "$BIN_ROOT"

  target="${BIN_ROOT}/shellcheck"

  if [ -x "$target" ] &&
    "$target" \
      --version |
    grep \
      -Fq \
      "version: ${SHELLCHECK_VERSION#v}"; then
    return 0
  fi

  require_command gh || return 1
  require_command curl || return 1
  require_command python3 || return 1
  require_command sha256sum || return 1

  case "$(uname -s)" in
    Linux)
      release_os="linux"
      ;;
    Darwin)
      release_os="darwin"
      ;;
    *)
      fail_check "unsupported ShellCheck bootstrap operating system: $(uname -s)"
      return 1
      ;;
  esac

  case "$(uname -m)" in
    x86_64 | amd64)
      release_arch="x86_64"
      ;;
    aarch64 | arm64)
      release_arch="aarch64"
      ;;
    *)
      fail_check "unsupported ShellCheck bootstrap architecture: $(uname -m)"
      return 1
      ;;
  esac

  release_json="$(
    mktemp \
      "${TMPDIR:-/tmp}/shellcheck-release.XXXXXX"
  )"

  archive="$(
    mktemp \
      "${TMPDIR:-/tmp}/shellcheck-archive.XXXXXX"
  )"

  extract_root="$(
    mktemp \
      -d \
      "${TMPDIR:-/tmp}/shellcheck-extract.XXXXXX"
  )"

  if ! github_api \
    "repos/koalaman/shellcheck/releases/tags/${SHELLCHECK_VERSION}" \
    > "$release_json"; then
    rm -f \
      "$release_json" \
      "$archive"
    rm -rf \
      "$extract_root"
    fail_check "unable to retrieve ShellCheck release metadata"
    return 1
  fi

  asset_data="$(
    python3 \
      - \
      "$release_json" \
      "$SHELLCHECK_VERSION" \
      "$release_os" \
      "$release_arch" << 'PY'
import json
import sys
from pathlib import Path

data = json.loads(Path(sys.argv[1]).read_text(encoding="utf-8"))
version = sys.argv[2]
operating_system = sys.argv[3]
arch = sys.argv[4]
expected = f"shellcheck-{version}.{operating_system}.{arch}.tar.xz"

matches = [
    asset
    for asset in data.get("assets", [])
    if asset.get("name") == expected
]

if len(matches) != 1:
    raise SystemExit(
        f"expected exactly one ShellCheck asset named {expected}, "
        f"found {len(matches)}"
    )

asset = matches[0]
digest = asset.get("digest") or ""

if not digest.startswith("sha256:"):
    raise SystemExit("ShellCheck release asset lacks a SHA-256 digest")

print(asset["browser_download_url"])
print(digest.removeprefix("sha256:"))
PY
  )"

  asset_rc=$?

  if [ "$asset_rc" -ne 0 ]; then
    rm -f \
      "$release_json" \
      "$archive"
    rm -rf \
      "$extract_root"
    fail_check "unable to select a checksum-bearing ShellCheck asset"
    return 1
  fi

  asset_url="$(
    printf '%s\n' \
      "$asset_data" |
      sed \
        -n \
        '1p'
  )"

  asset_sha="$(
    printf '%s\n' \
      "$asset_data" |
      sed \
        -n \
        '2p'
  )"

  if ! curl \
    --fail \
    --location \
    --silent \
    --show-error \
    "$asset_url" \
    --output \
    "$archive"; then
    rm -f \
      "$release_json" \
      "$archive"
    rm -rf \
      "$extract_root"
    fail_check "unable to download ShellCheck release asset"
    return 1
  fi

  observed_sha="$(
    sha256sum \
      "$archive" |
      awk \
        '{ print $1 }'
  )"

  if [ "$observed_sha" != "$asset_sha" ]; then
    rm -f \
      "$release_json" \
      "$archive"
    rm -rf \
      "$extract_root"
    fail_check "ShellCheck release asset checksum mismatch"
    return 1
  fi

  if ! python3 \
    - \
    "$archive" \
    "$extract_root" << 'PY'; then
import sys
import tarfile
from pathlib import Path

archive = Path(sys.argv[1])
root = Path(sys.argv[2]).resolve()

with tarfile.open(archive, "r:xz") as handle:
    for member in handle.getmembers():
        destination = (root / member.name).resolve()

        if root not in destination.parents and destination != root:
            raise SystemExit("unsafe path in ShellCheck archive")

    handle.extractall(root)
PY
    rm -f \
      "$release_json" \
      "$archive"
    rm -rf \
      "$extract_root"
    fail_check "unable to extract ShellCheck release asset"
    return 1
  fi

  extracted="$(
    find \
      "$extract_root" \
      -type f \
      -name shellcheck \
      -print \
      -quit
  )"

  if [ -z "$extracted" ]; then
    rm -f \
      "$release_json" \
      "$archive"
    rm -rf \
      "$extract_root"
    fail_check "ShellCheck binary is absent from the release asset"
    return 1
  fi

  install \
    -m \
    0755 \
    "$extracted" \
    "$target"

  rm -f \
    "$release_json" \
    "$archive"
  rm -rf \
    "$extract_root"

  "$target" \
    --version \
    > /dev/null
}

install_gitleaks() {
  mkdir -p \
    "$BIN_ROOT"

  target="${BIN_ROOT}/gitleaks"

  if [ -x "$target" ] &&
    [ "$(
      "$target" \
        version
    )" = "${GITLEAKS_VERSION#v}" ]; then
    return 0
  fi

  require_command gh || return 1
  require_command curl || return 1
  require_command python3 || return 1
  require_command sha256sum || return 1

  case "$(uname -s):$(uname -m)" in
    Linux:x86_64 | Linux:amd64)
      release_os="linux"
      release_arch="x64"
      pinned_sha="551f6fc83ea457d62a0d98237cbad105af8d557003051f41f3e7ca7b3f2470eb"
      ;;
    Linux:aarch64 | Linux:arm64)
      release_os="linux"
      release_arch="arm64"
      pinned_sha="e4a487ee7ccd7d3a7f7ec08657610aa3606637dab924210b3aee62570fb4b080"
      ;;
    Darwin:x86_64 | Darwin:amd64)
      release_os="darwin"
      release_arch="x64"
      pinned_sha="dfe101a4db2255fc85120ac7f3d25e4342c3c20cf749f2c20a18081af1952709"
      ;;
    Darwin:aarch64 | Darwin:arm64)
      release_os="darwin"
      release_arch="arm64"
      pinned_sha="b40ab0ae55c505963e365f271a8d3846efbc170aa17f2607f13df610a9aeb6a5"
      ;;
    *)
      fail_check "unsupported Gitleaks bootstrap platform: $(uname -s)/$(uname -m)"
      return 1
      ;;
  esac

  release_json="$(
    mktemp \
      "${TMPDIR:-/tmp}/gitleaks-release.XXXXXX"
  )"

  archive="$(
    mktemp \
      "${TMPDIR:-/tmp}/gitleaks-archive.XXXXXX"
  )"

  extract_root="$(
    mktemp \
      -d \
      "${TMPDIR:-/tmp}/gitleaks-extract.XXXXXX"
  )"

  if ! github_api \
    "repos/gitleaks/gitleaks/releases/tags/${GITLEAKS_VERSION}" \
    > "$release_json"; then
    rm -f \
      "$release_json" \
      "$archive"
    rm -rf \
      "$extract_root"
    fail_check "unable to retrieve Gitleaks release metadata"
    return 1
  fi

  asset_data="$(
    python3 \
      - \
      "$release_json" \
      "$GITLEAKS_VERSION" \
      "$release_os" \
      "$release_arch" \
      "$pinned_sha" << 'PY'
import json
import sys
from pathlib import Path

data = json.loads(Path(sys.argv[1]).read_text(encoding="utf-8"))
version = sys.argv[2].removeprefix("v")
operating_system = sys.argv[3]
arch = sys.argv[4]
pinned_sha = sys.argv[5]
expected = f"gitleaks_{version}_{operating_system}_{arch}.tar.gz"

matches = [
    asset
    for asset in data.get("assets", [])
    if asset.get("name") == expected
]

if len(matches) != 1:
    raise SystemExit(
        f"expected exactly one Gitleaks asset named {expected}, "
        f"found {len(matches)}"
    )

asset = matches[0]
digest = asset.get("digest") or ""

if digest != f"sha256:{pinned_sha}":
    raise SystemExit(
        "Gitleaks release asset digest differs from the pinned SHA-256"
    )

print(asset["browser_download_url"])
print(pinned_sha)
PY
  )"

  asset_rc=$?

  if [ "$asset_rc" -ne 0 ]; then
    rm -f \
      "$release_json" \
      "$archive"
    rm -rf \
      "$extract_root"
    fail_check "unable to select the pinned Gitleaks release asset"
    return 1
  fi

  asset_url="$(
    printf '%s\n' \
      "$asset_data" |
      sed \
        -n \
        '1p'
  )"

  asset_sha="$(
    printf '%s\n' \
      "$asset_data" |
      sed \
        -n \
        '2p'
  )"

  if ! curl \
    --fail \
    --location \
    --silent \
    --show-error \
    "$asset_url" \
    --output \
    "$archive"; then
    rm -f \
      "$release_json" \
      "$archive"
    rm -rf \
      "$extract_root"
    fail_check "unable to download Gitleaks release asset"
    return 1
  fi

  observed_sha="$(
    sha256sum \
      "$archive" |
      awk \
        '{ print $1 }'
  )"

  if [ "$observed_sha" != "$asset_sha" ]; then
    rm -f \
      "$release_json" \
      "$archive"
    rm -rf \
      "$extract_root"
    fail_check "Gitleaks release asset checksum mismatch"
    return 1
  fi

  if ! python3 \
    - \
    "$archive" \
    "$extract_root" << 'PY'; then
import sys
import tarfile
from pathlib import Path, PurePosixPath

archive = Path(sys.argv[1])
root = Path(sys.argv[2]).resolve()

with tarfile.open(archive, "r:gz") as handle:
    for member in handle.getmembers():
        pure = PurePosixPath(member.name)

        if (
            pure.is_absolute()
            or ".." in pure.parts
            or "\\" in member.name
            or member.issym()
            or member.islnk()
            or member.ischr()
            or member.isblk()
            or member.isfifo()
        ):
            raise SystemExit("unsafe member in Gitleaks archive")

        destination = (root / member.name).resolve()

        if root not in destination.parents and destination != root:
            raise SystemExit("unsafe path in Gitleaks archive")

    handle.extractall(root)
PY
    rm -f \
      "$release_json" \
      "$archive"
    rm -rf \
      "$extract_root"
    fail_check "unable to extract Gitleaks release asset"
    return 1
  fi

  extracted="$(
    find \
      "$extract_root" \
      -type f \
      -name gitleaks \
      -print \
      -quit
  )"

  if [ -z "$extracted" ]; then
    rm -f \
      "$release_json" \
      "$archive"
    rm -rf \
      "$extract_root"
    fail_check "Gitleaks binary is absent from the release asset"
    return 1
  fi

  install \
    -m \
    0755 \
    "$extracted" \
    "$target"

  rm -f \
    "$release_json" \
    "$archive"
  rm -rf \
    "$extract_root"

  [ "$(
    "$target" \
      version
  )" = "${GITLEAKS_VERSION#v}" ]
}
install_go_tool() {
  binary="$1"
  module="$2"
  version="$3"

  mkdir -p \
    "$BIN_ROOT"

  target="${BIN_ROOT}/${binary}"

  if [ -x "$target" ]; then
    return 0
  fi

  GOBIN="$BIN_ROOT" \
    "$PINNED_GO" \
    install \
    "${module}@${version}"
}

write_text_validator() {
  mkdir -p \
    "$(dirname "$TEXT_VALIDATOR")"

  cat > "$TEXT_VALIDATOR" << 'GO'
package main

import (
	"bufio"
	"bytes"
	"fmt"
	"io"
	"os"
	"path/filepath"
	"strings"
	"unicode/utf8"

	yaml "go.yaml.in/yaml/v3"
)

var excluded = map[string]bool{
	".git":               true,
	".build-environment": true,
	"build":              true,
	"dist":               true,
	"node_modules":       true,
	"out":                true,
}

func main() {
	if len(os.Args) != 2 {
		fmt.Fprintln(os.Stderr, "usage: validate-text REPOSITORY_ROOT")
		os.Exit(2)
	}

	root, err := filepath.Abs(os.Args[1])
	if err != nil {
		fmt.Fprintln(os.Stderr, err)
		os.Exit(1)
	}

	failures := 0

	err = filepath.WalkDir(root, func(path string, entry os.DirEntry, walkErr error) error {
		if walkErr != nil {
			return walkErr
		}

		if entry.IsDir() {
			if path != root && excluded[entry.Name()] {
				return filepath.SkipDir
			}
			return nil
		}

		extension := strings.ToLower(filepath.Ext(path))

		switch extension {
		case ".md":
			failures += validateText(path, false)
		case ".yaml", ".yml":
			fileFailures := validateText(path, true)
			failures += fileFailures

			if fileFailures == 0 {
				failures += validateYAML(path)
			}
		}

		return nil
	})
	if err != nil {
		fmt.Fprintln(os.Stderr, err)
		os.Exit(1)
	}

	if failures != 0 {
		fmt.Fprintf(os.Stderr, "text-validation failures: %d\n", failures)
		os.Exit(1)
	}

	fmt.Println("text-validation failures: 0")
}

func validateText(path string, rejectTabs bool) int {
	data, err := os.ReadFile(path)
	if err != nil {
		fmt.Printf("%s: read failure: %v\n", path, err)
		return 1
	}

	failures := 0

	if !utf8.Valid(data) {
		fmt.Printf("%s: invalid UTF-8\n", path)
		failures++
	}

	if bytes.Contains(data, []byte{'\r'}) {
		fmt.Printf("%s: contains carriage returns\n", path)
		failures++
	}

	if len(data) == 0 || data[len(data)-1] != '\n' {
		fmt.Printf("%s: missing final newline\n", path)
		failures++
	}

	scanner := bufio.NewScanner(bytes.NewReader(data))
	lineNumber := 0
	blankRun := 0

	for scanner.Scan() {
		lineNumber++
		line := scanner.Text()

		if strings.TrimRight(line, " \t") != line {
			fmt.Printf("%s:%d: trailing whitespace\n", path, lineNumber)
			failures++
		}

		if rejectTabs && strings.ContainsRune(line, '\t') {
			fmt.Printf("%s:%d: YAML contains a tab character\n", path, lineNumber)
			failures++
		}

		if line == "" {
			blankRun++
			if blankRun > 2 {
				fmt.Printf("%s:%d: more than two consecutive blank lines\n", path, lineNumber)
				failures++
			}
		} else {
			blankRun = 0
		}
	}

	if err := scanner.Err(); err != nil {
		fmt.Printf("%s: scan failure: %v\n", path, err)
		failures++
	}

	return failures
}

func validateYAML(path string) int {
	handle, err := os.Open(path)
	if err != nil {
		fmt.Printf("%s: open failure: %v\n", path, err)
		return 1
	}
	defer handle.Close()

	decoder := yaml.NewDecoder(handle)
	document := 0

	for {
		var value any
		err := decoder.Decode(&value)

		if err == io.EOF {
			break
		}

		document++

		if err != nil {
			fmt.Printf("%s: YAML document %d: %v\n", path, document, err)
			return 1
		}
	}

	return 0
}
GO
}

if [ "$BOOTSTRAP" -eq 1 ]; then
  printf '\n=== Bootstrap pinned validators ===\n'

  install_shellcheck ||
    fail_check "ShellCheck bootstrap failed"

  install_go_tool \
    shfmt \
    mvdan.cc/sh/v3/cmd/shfmt \
    "$SHFMT_VERSION" ||
    fail_check "shfmt bootstrap failed"

  install_go_tool \
    actionlint \
    github.com/rhysd/actionlint/cmd/actionlint \
    "$ACTIONLINT_VERSION" ||
    fail_check "actionlint bootstrap failed"

  install_gitleaks ||
    fail_check "Gitleaks bootstrap failed"

  write_text_validator
fi

export PATH="${BIN_ROOT}:${PATH}"

printf '\n=== Validator availability ===\n'

for tool in \
  shellcheck \
  shfmt \
  actionlint \
  gitleaks; do
  require_command \
    "$tool" ||
    true
done

if [ ! -s "$TEXT_VALIDATOR" ]; then
  fail_check "repository text-validator source is unavailable: ${TEXT_VALIDATOR}"
fi

if [ "$FAILURES" -ne 0 ]; then
  echo "STOP: required validators are unavailable."
  exit "$FAILURES"
fi

printf 'ShellCheck: %s\n' "$(
  shellcheck \
    --version |
    awk \
      -F': ' \
      '$1 == "version" { print $2 }'
)"
printf 'shfmt:      %s\n' "$(
  shfmt \
    --version
)"
printf 'actionlint: %s\n' "$(
  actionlint \
    -version
)"
printf 'Gitleaks:   %s\n' "$(
  gitleaks \
    version
)"

cd \
  "$REPO_ROOT" ||
  exit 1

SHELL_FILES=()

while IFS= read -r -d '' path; do
  SHELL_FILES+=("$path")
done < <(
  find \
    . \
    -type f \
    \( \
    -name '*.sh' \
    -o \
    -name '*.bash' \
    \) \
    -not \
    -path './.git/*' \
    -not \
    -path './.build-environment/*' \
    -not \
    -path './build/*' \
    -not \
    -path './dist/*' \
    -not \
    -path './out/*' \
    -not \
    -path './node_modules/*' \
    -print0
)

for hook in \
  .githooks/pre-commit \
  .githooks/commit-msg; do
  if [ -f "$hook" ]; then
    SHELL_FILES+=("$hook")
  fi
done

mapfile -t SHELL_FILES < <(
  printf '%s\n' \
    "${SHELL_FILES[@]}" |
    sort \
      -u
)

if [ "${#SHELL_FILES[@]}" -eq 0 ]; then
  fail_check "repository-owned shell inventory is empty"
fi

if [ "$FORMAT_MANAGED" -eq 1 ] &&
  [ "${#SHELL_FILES[@]}" -gt 0 ]; then
  printf '\n=== Format repository-owned shell ===\n'

  shfmt \
    -w \
    -ln \
    bash \
    -i \
    2 \
    -ci \
    -sr \
    "${SHELL_FILES[@]}"
fi

printf '\n=== Shell syntax ===\n'

SYNTAX_FAILURES=0

for path in "${SHELL_FILES[@]}"; do
  if ! bash \
    -n \
    "$path"; then
    printf 'FAIL: shell syntax: %s\n' "$path"
    SYNTAX_FAILURES=$((SYNTAX_FAILURES + 1))
  fi
done

if [ "$SYNTAX_FAILURES" -eq 0 ]; then
  pass_check "all inventoried shell files pass Bash syntax validation."
else
  fail_check "${SYNTAX_FAILURES} shell file(s) failed syntax validation"
fi

printf '\n=== ShellCheck for repository-owned shell ===\n'

if [ "${#SHELL_FILES[@]}" -gt 0 ] &&
  shellcheck \
    --severity=error \
    "${SHELL_FILES[@]}"; then
  pass_check "complete control-tree ShellCheck error-level validation passed."
else
  fail_check "control-tree ShellCheck error-level validation failed"
fi

printf '\n=== Repository-owned shell formatting ===\n'

if [ "${#SHELL_FILES[@]}" -gt 0 ] &&
  shfmt \
    -d \
    -ln \
    bash \
    -i \
    2 \
    -ci \
    -sr \
    "${SHELL_FILES[@]}"; then
  pass_check "complete control-tree shell formatting passed."
else
  fail_check "control-tree shell formatting failed"
fi

printf '\n=== Markdown and YAML ===\n'

if (
  cd \
    "$SOURCE_ENV_ROOT" &&
    GOFLAGS='-mod=readonly' \
      "$PINNED_GO" \
      run \
      "$TEXT_VALIDATOR" \
      "$REPO_ROOT"
); then
  pass_check "repository-owned Markdown and YAML validation passed."
else
  fail_check "repository-owned Markdown or YAML validation failed"
fi

printf '\n=== Secret scanning ===\n'

if [ "$STAGED_SECRETS" -eq 1 ]; then
  if gitleaks \
    git \
    --pre-commit \
    --staged \
    --no-banner \
    --no-color \
    --redact \
    --verbose \
    "$REPO_ROOT"; then
    pass_check "staged Git diff contains no detected secret."
  else
    fail_check "staged Git diff secret scan failed"
  fi
else
  SECRET_SCAN_ROOT="$(
    mktemp \
      -d \
      "${TMPDIR:-/tmp}/tailscale-control-tree-secrets.XXXXXX"
  )"

  if python3 \
    - \
    "$REPO_ROOT" \
    "$SECRET_SCAN_ROOT" << 'PY'; then
from __future__ import annotations

import os
import shutil
import subprocess
import sys
from pathlib import Path

root = Path(sys.argv[1]).resolve()
destination = Path(sys.argv[2]).resolve()

result = subprocess.run(
    [
        "git",
        "-C",
        str(root),
        "ls-files",
        "-z",
        "--cached",
        "--others",
        "--exclude-standard",
    ],
    check=True,
    capture_output=True,
)

for raw in result.stdout.split(b"\0"):
    if not raw:
        continue

    relative = Path(os.fsdecode(raw))

    if relative.is_absolute() or ".." in relative.parts:
        raise SystemExit(f"unsafe Git path in secret scan: {relative}")

    source = root / relative
    target = destination / relative
    target.parent.mkdir(parents=True, exist_ok=True)

    if source.is_symlink():
        target.write_text(
            os.readlink(source) + "\n",
            encoding="utf-8",
        )
    elif source.is_file():
        shutil.copy2(source, target)
PY
    if gitleaks \
      dir \
      --no-banner \
      --no-color \
      --redact \
      --verbose \
      "$SECRET_SCAN_ROOT"; then
      pass_check "current control tree contains no detected secret."
    else
      fail_check "current control-tree secret scan failed"
    fi
  else
    fail_check "current control-tree secret-scan staging failed"
  fi

  rm \
    -rf \
    -- \
    "$SECRET_SCAN_ROOT"
fi

printf '\n=== Static SPK inspector tests ===\n'

if bash \
  tests/quality/inspect-spk.sh; then
  pass_check "synthetic static SPK inspection tests passed."
else
  fail_check "synthetic static SPK inspection tests failed"
fi

printf '\n=== Release control contracts ===\n'

if bash \
  tests/releases/patch-base-identity-contract.sh; then
  pass_check "patch-base identity contract passed."
else
  fail_check "patch-base identity contract failed"
fi

if bash \
  tests/releases/layered-patch-contract.sh; then
  pass_check "layered patch contract passed."
else
  fail_check "layered patch contract failed"
fi

if bash \
  tests/releases/reference-patch-contract.sh; then
  pass_check "reference patch contract passed."
else
  fail_check "reference patch contract failed"
fi

if bash \
  tests/releases/temporary-git-isolation-contract.sh; then
  pass_check "temporary Git contract isolation passed."
else
  fail_check "temporary Git contract isolation failed"
fi

printf '\n=== Living r2 release contract ===\n'

if bash \
  tests/releases/r2-control-contract.sh; then
  pass_check "living r2 release contract and retained checksums passed."
else
  fail_check "living r2 release contract or retained checksums failed"
fi

printf '\n=== Living r3 release contract ===\n'

if bash \
  tests/releases/r3-control-contract.sh; then
  pass_check "living r3 release contract and retained checksums passed."
else
  fail_check "living r3 release contract or retained checksums failed"
fi

printf '\n=== Candidate artifact role contract ===\n'

if bash \
  tests/releases/build-candidate-role-contract.sh; then
  pass_check "candidate artifact role contract passed."
else
  fail_check "candidate artifact role contract failed"
fi

printf '\n=== Automation governance contract ===\n'

if bash \
  tests/governance/automation-contract.sh \
  --source-environment \
  "$SOURCE_ENV_ROOT"; then
  pass_check "automation governance catalogue matches pinned workflow definitions."
else
  fail_check "automation governance catalogue validation failed"
fi

printf '\n=== GitHub Actions ===\n'

WORKFLOW_FILES=()

while IFS= read -r -d '' path; do
  WORKFLOW_FILES+=("$path")
done < <(
  find \
    .github/workflows \
    -maxdepth 1 \
    -type f \
    \( \
    -name '*.yml' \
    -o \
    -name '*.yaml' \
    \) \
    -print0 \
    2> /dev/null
)

if [ "${#WORKFLOW_FILES[@]}" -eq 0 ]; then
  fail_check "no GitHub Actions workflow is present"
elif actionlint \
  "${WORKFLOW_FILES[@]}"; then
  pass_check "GitHub Actions syntax validation passed."
else
  fail_check "GitHub Actions syntax validation failed"
fi

if python3 \
  - "${WORKFLOW_FILES[@]}" << 'PY'; then
from __future__ import annotations

import re
import sys
from pathlib import Path

failures = 0

for raw in sys.argv[1:]:
    path = Path(raw)
    content = path.read_text(encoding="utf-8")

    for line_number, line in enumerate(content.splitlines(), start=1):
        match = re.match(r"^\s*-\s+uses:\s+([^#\s]+)", line)

        if not match:
            continue

        value = match.group(1)

        if value.startswith("./") or value.startswith("docker://"):
            continue

        if not re.fullmatch(r"[^@\s]+@[0-9a-f]{40}", value):
            print(
                f"{path}:{line_number}: external Action is not pinned "
                f"to a full commit SHA: {value}"
            )
            failures += 1

raise SystemExit(0 if failures == 0 else 1)
PY
  pass_check "external Actions are pinned to full commit SHAs."
else
  fail_check "one or more external Actions are not pinned"
fi

printf '\n=== Git whitespace ===\n'

if git \
  diff \
  --check \
  -- \
  . \
  ':(exclude,glob)patches/**/*.patch' &&
  git \
    diff \
    --cached \
    --check \
    -- \
    . \
    ':(exclude,glob)patches/**/*.patch'; then
  pass_check "Git staged and unstaged whitespace validation passed."
else
  fail_check "Git staged or unstaged whitespace validation failed"
fi

printf '\n=== Required governance files ===\n'

REQUIRED_FILES=(
  LICENSE
  CONTRIBUTING.md
  SECURITY.md
  .github/CODEOWNERS
  .github/PULL_REQUEST_TEMPLATE.md
  .editorconfig
  .shellcheckrc
  .markdownlint-cli2.yaml
  .yamllint.yml
  .githooks/pre-commit
  .githooks/commit-msg
  scripts/validate-repository.sh
  scripts/release/inspect-spk.sh
  tests/quality/inspect-spk.sh
  tests/governance/automation-contract.sh
  .github/workflows/validate.yml
  docs/governance/automation.md
  docs/governance/repository-governance.md
  docs/governance/tooling.md
)

for path in "${REQUIRED_FILES[@]}"; do
  if [ -s "$path" ]; then
    pass_check "required file exists: ${path}"
  else
    fail_check "required file is missing or empty: ${path}"
  fi
done

printf '\n=== Validation result ===\n'
printf 'Failures: %s\n' "$FAILURES"

if [ "$FAILURES" -eq 0 ]; then
  echo "PASS: repository governance validation completed."
else
  echo "STOP: repository governance validation failed."
fi

exit "$FAILURES"
