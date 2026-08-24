#!/usr/bin/env bash

release_fail() {
  printf 'FAIL: %s\n' "$1" >&2
}

release_pass() {
  printf 'PASS: %s\n' "$1"
}

release_notice() {
  printf 'NOTICE: %s\n' "$1"
}

release_clean_git() {
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

release_require_command() {
  command_name="$1"

  if command \
    -v \
    "$command_name" \
    > /dev/null \
    2>&1; then
    return 0
  fi

  release_fail "required command is unavailable: ${command_name}"
  return 1
}

release_require_worktree() {
  worktree="$1"

  if [ -d "$worktree/.git" ] ||
    [ -f "$worktree/.git" ]; then
    return 0
  fi

  release_fail "path is not a Git worktree: ${worktree}"
  return 1
}

release_require_clean_worktree() {
  worktree="$1"

  status="$(
    release_clean_git \
      -C "$worktree" \
      status \
      --short \
      --untracked-files=all
  )"

  if [ -z "$status" ]; then
    return 0
  fi

  printf 'Observed status for %s:\n%s\n' \
    "$worktree" \
    "$status" \
    >&2

  release_fail "worktree is not clean: ${worktree}"
  return 1
}

release_manifest_get() {
  manifest="$1"
  expression="$2"

  python3 \
    - "$manifest" "$expression" << 'PY'
import json
import sys
from pathlib import Path

manifest = Path(sys.argv[1])
expression = sys.argv[2]
data = json.loads(manifest.read_text(encoding="utf-8"))

value = data

for part in expression.split("."):
    if not isinstance(value, dict) or part not in value:
        raise SystemExit(f"manifest field is absent: {expression}")
    value = value[part]

if isinstance(value, (dict, list)):
    print(json.dumps(value, separators=(",", ":")))
elif isinstance(value, bool):
    print("true" if value else "false")
else:
    print(value)
PY
}

release_manifest_array() {
  manifest="$1"
  expression="$2"

  python3 \
    - "$manifest" "$expression" << 'PY'
import json
import sys
from pathlib import Path

data = json.loads(Path(sys.argv[1]).read_text(encoding="utf-8"))
value = data

for part in sys.argv[2].split("."):
    if not isinstance(value, dict) or part not in value:
        raise SystemExit(f"manifest field is absent: {sys.argv[2]}")
    value = value[part]

if not isinstance(value, list):
    raise SystemExit(f"manifest field is not an array: {sys.argv[2]}")

for item in value:
    if not isinstance(item, (str, int, float)):
        raise SystemExit(f"manifest array contains a complex value: {sys.argv[2]}")
    print(item)
PY
}

release_validate_manifest() {
  manifest="$1"

  python3 \
    - "$manifest" << 'PY'
from __future__ import annotations

import json
import re
import sys
from pathlib import Path, PurePosixPath

path = Path(sys.argv[1])
data = json.loads(path.read_text(encoding="utf-8"))

required = (
    "control.repository",
    "control.branch",
    "control.governance_baseline_commit",
    "upstream.repository",
    "upstream.tag",
    "upstream.commit",
    "downstream.revision",
    "downstream.release_commit",
    "downstream.release_tree",
    "package.version",
    "package.build_number",
    "package.full_version",
    "package.architecture",
    "package.filename",
    "package.sha256",
    "synology.minimum_dsm",
    "synology.architectures",
    "branches.work",
    "branches.release",
    "tags.release",
    "paths.patch_series",
    "paths.build_entrypoint",
    "paths.build_output",
    "paths.evidence",
    "paths.release_record",
    "validation.go_packages",
    "validation.patch_series_format",
    "validation.patch_apply_files",
    "validation.patch_reference_files",
    "validation.accepted_legacy_no_signoff_commits",
    "safety.allow_stable_publication",
    "safety.allow_production_install",
    "safety.allow_root_bootstrap",
    "safety.allow_firewall_mutation",
    "safety.allow_reboot",
)


def get(expression: str):
    value = data

    for part in expression.split("."):
        if not isinstance(value, dict) or part not in value:
            raise SystemExit(f"required manifest field is absent: {expression}")
        value = value[part]

    return value


for expression in required:
    get(expression)

if data.get("schema_version") != 1:
    raise SystemExit("unsupported release manifest schema version")

for field in ("control.repository", "upstream.repository"):
    value = str(get(field))

    if not re.fullmatch(
        r"[A-Za-z0-9_.-]+/[A-Za-z0-9_.-]+",
        value,
    ):
        raise SystemExit(
            f"{field} does not use a safe owner/repository form"
        )

sha_fields = (
    "control.governance_baseline_commit",
    "upstream.commit",
    "downstream.release_commit",
    "downstream.release_tree",
    "package.sha256",
)

for field in sha_fields:
    value = str(get(field))
    if not re.fullmatch(r"[0-9a-f]{40}", value) and field != "package.sha256":
        raise SystemExit(f"{field} is not a full lowercase Git SHA")
    if field == "package.sha256" and not re.fullmatch(r"[0-9a-f]{64}", value):
        raise SystemExit("package.sha256 is not a lowercase SHA-256")

if not re.fullmatch(r"v[0-9]+\.[0-9]+\.[0-9]+(?:-[0-9A-Za-z.-]+)?", get("upstream.tag")):
    raise SystemExit("upstream.tag does not use the required explicit tag form")

if not re.fullmatch(r"r[1-9][0-9]*", get("downstream.revision")):
    raise SystemExit("downstream.revision does not use rN form")

if not get("branches.work").startswith("work/"):
    raise SystemExit("branches.work does not use the work/ namespace")

if not get("branches.release").startswith("release/"):
    raise SystemExit("branches.release does not use the release/ namespace")

if not get("tags.release").startswith("release/"):
    raise SystemExit("tags.release does not use the release/ namespace")

for field in (
    "paths.patch_series",
    "paths.build_entrypoint",
    "paths.build_output",
    "paths.evidence",
    "paths.release_record",
):
    value = str(get(field))
    pure = PurePosixPath(value)

    if pure.is_absolute() or ".." in pure.parts or value in ("", "."):
        raise SystemExit(f"{field} is not a safe repository-relative path")

    if "__" in value:
        raise SystemExit(f"{field} contains an unresolved placeholder")

if get("package.filename") != (
    f"tailscale-{get('package.architecture')}-"
    f"{get('package.full_version')}-dsm7.spk"
):
    raise SystemExit("package filename does not match package identity")

for field in (
    "safety.allow_stable_publication",
    "safety.allow_production_install",
    "safety.allow_root_bootstrap",
    "safety.allow_firewall_mutation",
    "safety.allow_reboot",
):
    if get(field) is not False:
        raise SystemExit(f"unsafe manifest setting must remain false: {field}")

packages = get("validation.go_packages")

if not isinstance(packages, list) or not packages:
    raise SystemExit("validation.go_packages must contain at least one package")

for package in packages:
    if not isinstance(package, str) or not package.startswith("./"):
        raise SystemExit("validation.go_packages contains an invalid package")

patch_format = get("validation.patch_series_format")

if patch_format not in ("mail", "raw-diff"):
    raise SystemExit(
        "validation.patch_series_format must be mail or raw-diff"
    )

apply_files = get("validation.patch_apply_files")
reference_files = get("validation.patch_reference_files")

if not isinstance(apply_files, list) or not apply_files:
    raise SystemExit(
        "validation.patch_apply_files must be a non-empty array"
    )

if not isinstance(reference_files, list):
    raise SystemExit(
        "validation.patch_reference_files must be an array"
    )

all_patch_files = apply_files + reference_files

if len(all_patch_files) != len(set(all_patch_files)):
    raise SystemExit("declared patch filenames contain duplicates")

for patch_name in all_patch_files:
    if (
        not isinstance(patch_name, str)
        or "/" in patch_name
        or patch_name in ("", ".", "..")
        or not patch_name.endswith(".patch")
    ):
        raise SystemExit(
            "declared patch filename is not a safe direct .patch file"
        )

if patch_format == "mail" and reference_files:
    raise SystemExit(
        "mail patch series must not declare reference-only patches"
    )

legacy_commits = get(
    "validation.accepted_legacy_no_signoff_commits"
)

if not isinstance(legacy_commits, list):
    raise SystemExit(
        "validation.accepted_legacy_no_signoff_commits must be an array"
    )

if len(legacy_commits) != len(set(legacy_commits)):
    raise SystemExit(
        "validation.accepted_legacy_no_signoff_commits contains duplicates"
    )

for commit in legacy_commits:
    if not isinstance(commit, str) or not re.fullmatch(
        r"[0-9a-f]{40}", commit
    ):
        raise SystemExit(
            "accepted legacy no-signoff list contains an invalid commit"
        )

print("PASS: release manifest schema and safety policy are valid.")
PY
}

release_resolve_path() {
  root="$1"
  relative="$2"

  python3 \
    - "$root" "$relative" << 'PY'
import sys
from pathlib import Path

root = Path(sys.argv[1]).resolve()
target = (root / sys.argv[2]).resolve()

if target != root and root not in target.parents:
    raise SystemExit("resolved path escapes the supplied root")

print(target)
PY
}

release_count_matching_signoff() {
  worktree="$1"
  commit="$2"

  expected="Signed-off-by: $(
    release_clean_git \
      -C "$worktree" \
      show \
      -s \
      --format='%an <%ae>' \
      "$commit"
  )"

  release_clean_git \
    -C "$worktree" \
    show \
    -s \
    --format='%B' \
    "$commit" |
    grep \
      -Fxc \
      "$expected" ||
    true
}

release_validate_patch_inventory() {
  manifest="$1"
  patch_root="$2"

  python3 \
    - "$manifest" "$patch_root" << 'PY'
import json
import sys
from pathlib import Path

manifest = json.loads(Path(sys.argv[1]).read_text(encoding="utf-8"))
root = Path(sys.argv[2]).resolve()
validation = manifest["validation"]

apply_files = validation["patch_apply_files"]
reference_files = validation["patch_reference_files"]
expected = sorted(apply_files + reference_files)
observed = sorted(path.name for path in root.glob("*.patch") if path.is_file())

if observed != expected:
    print(f"Expected direct patch files: {expected}")
    print(f"Observed direct patch files: {observed}")
    raise SystemExit("direct patch inventory differs from the manifest")

for patch_name in expected:
    path = (root / patch_name).resolve()
    if path.parent != root or not path.is_file():
        raise SystemExit(f"declared patch file is unavailable: {patch_name}")

print(f"Patch apply files:     {len(apply_files)}")
print(f"Patch reference files: {len(reference_files)}")
print("PASS: direct patch inventory matches the manifest roles.")
PY
}

release_patch_paths() {
  manifest="$1"
  patch_root="$2"
  expression="$3"

  while IFS= read -r patch_name; do
    [ -n "$patch_name" ] || continue
    resolved="$(release_resolve_path "$patch_root" "$patch_name")"

    if [ "$(dirname "$resolved")" != "$(cd "$patch_root" && pwd)" ]; then
      release_fail "declared patch is not directly under the patch root"
      return 1
    fi

    printf '%s\n' "$resolved"
  done < <(
    release_manifest_array "$manifest" "$expression"
  )
}

release_check_reference_patches_forward() {
  target_worktree="$1"
  manifest="$2"
  patch_root="$3"

  mapfile -t reference_patches < <(
    release_patch_paths "$manifest" "$patch_root" validation.patch_reference_files
  )

  if [ "${#reference_patches[@]}" -eq 0 ]; then
    release_notice "no reference-only patches are declared."
    return 0
  fi

  for patch_file in "${reference_patches[@]}"; do
    printf 'Checking reference patch against upstream: %s\n' "$(basename "$patch_file")"
    release_clean_git -C "$target_worktree" apply --check "$patch_file" || return 1
  done

  release_pass "reference patches apply independently to the upstream tree."
}

release_check_reference_patches_reverse() {
  target_worktree="$1"
  manifest="$2"
  patch_root="$3"

  mapfile -t reference_patches < <(
    release_patch_paths "$manifest" "$patch_root" validation.patch_reference_files
  )

  if [ "${#reference_patches[@]}" -eq 0 ]; then
    return 0
  fi

  for patch_file in "${reference_patches[@]}"; do
    printf 'Checking reference patch is contained in aggregate tree: %s\n' "$(basename "$patch_file")"
    release_clean_git -C "$target_worktree" apply --reverse --check "$patch_file" || return 1
  done

  release_pass "reference patches are contained in the aggregate result."
}

release_apply_patch_series() (
  target_worktree="$1"
  manifest="$2"
  patch_root="$3"
  application_mode="$4"

  case "$application_mode" in
    worktree | round-trip) ;;
    *)
      release_fail "unsupported patch application mode: ${application_mode}"
      exit 2
      ;;
  esac

  release_validate_patch_inventory "$manifest" "$patch_root" || exit 1
  patch_format="$(release_manifest_get "$manifest" validation.patch_series_format)"

  mapfile -t patch_files < <(
    release_patch_paths "$manifest" "$patch_root" validation.patch_apply_files
  )

  printf 'Patch series format: %s\n' "$patch_format"
  printf 'Applied patch count: %s\n' "${#patch_files[@]}"

  case "$patch_format" in
    raw-diff)
      for patch_file in "${patch_files[@]}"; do
        printf 'Applying aggregate raw diff: %s\n' "$(basename "$patch_file")"

        if [ "$application_mode" = "round-trip" ]; then
          release_clean_git -C "$target_worktree" apply --check --index "$patch_file" || exit 1
          release_clean_git -C "$target_worktree" apply --index "$patch_file" || exit 1
        else
          release_clean_git -C "$target_worktree" apply --check "$patch_file" || exit 1
          release_clean_git -C "$target_worktree" apply "$patch_file" || exit 1
        fi
      done
      ;;
    mail)
      release_clean_git \
        -c \
        commit.gpgsign=false \
        -c \
        user.name='Tailscale Synology release validator' \
        -c \
        user.email='validator@localhost.invalid' \
        -C "$target_worktree" \
        am \
        --3way \
        "${patch_files[@]}"
      apply_rc=$?
      if [ "$apply_rc" -ne 0 ]; then
        release_clean_git -C "$target_worktree" am --abort > /dev/null 2>&1 || true
        exit "$apply_rc"
      fi
      ;;
    *)
      release_fail "unsupported manifest patch format: ${patch_format}"
      exit 1
      ;;
  esac
)
