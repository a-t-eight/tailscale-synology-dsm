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


def reject_duplicate_json_members(pairs):
    result = {}
    for key, value in pairs:
        if key in result:
            raise ValueError("duplicate JSON member")
        result[key] = value
    return result


def reject_nonstandard_json_constant(_constant):
    raise ValueError("non-standard JSON constant")


def load_json(path):
    return json.loads(
        path.read_text(encoding="utf-8"),
        object_pairs_hook=reject_duplicate_json_members,
        parse_constant=reject_nonstandard_json_constant,
    )


manifest = Path(sys.argv[1])
expression = sys.argv[2]
data = load_json(manifest)

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


def reject_duplicate_json_members(pairs):
    result = {}
    for key, value in pairs:
        if key in result:
            raise ValueError("duplicate JSON member")
        result[key] = value
    return result


def reject_nonstandard_json_constant(_constant):
    raise ValueError("non-standard JSON constant")


def load_json(path):
    return json.loads(
        path.read_text(encoding="utf-8"),
        object_pairs_hook=reject_duplicate_json_members,
        parse_constant=reject_nonstandard_json_constant,
    )


data = load_json(Path(sys.argv[1]))
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


def reject_duplicate_json_members(pairs):
    result = {}
    for key, value in pairs:
        if key in result:
            raise ValueError("duplicate JSON member")
        result[key] = value
    return result


def reject_nonstandard_json_constant(_constant):
    raise ValueError("non-standard JSON constant")


def load_json(path):
    return json.loads(
        path.read_text(encoding="utf-8"),
        object_pairs_hook=reject_duplicate_json_members,
        parse_constant=reject_nonstandard_json_constant,
    )


path = Path(sys.argv[1])
data = load_json(path)

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
    "validation.ssh_allowed_signers_path",
    "validation.ssh_allowed_signers_sha256",
    "validation.ssh_signer_fingerprints",
    "validation.ssh_signer_principals",
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
    git interpret-trailers --parse |
    grep \
      -Fxc \
      "$expected" ||
    true
}

release_count_signoffs() {
  worktree="$1"
  commit="$2"

  release_clean_git \
    -C "$worktree" \
    show \
    -s \
    --format='%B' \
    "$commit" |
    git interpret-trailers --parse |
    grep \
      -Eic \
      '^Signed-off-by:[[:space:]]' ||
    true
}

release_validate_production_contract() (
  if [ "$#" -ne 3 ]; then
    release_fail \
      "release_validate_production_contract requires MANIFEST CONTROL_WORKTREE SOURCE_REPO"
    exit 2
  fi

  manifest="$1"
  control_worktree="$2"
  source_repo="$3"
  frozen_accepted_commit="20c86229955a3d03de01901aee1499cab87c571d"
  frozen_accepted_tree="6d022c18f27a42aab553697c69c852bebd8594b8"
  frozen_accepted_tag="release/synology-v1.98.96-r1"
  frozen_accepted_branch="release/v1.98.9-synology"
  frozen_accepted_revision="r1"
  frozen_historical_tag="release/synology-v1.98.96"
  frozen_tested_model="DS920+"
  frozen_synology_platform="geminilake"
  frozen_minimum_dsm="7.3-81180"
  frozen_package_architecture="x86_64"
  frozen_netfilter_package_min_version="1.0.0-11"
  frozen_package_version="1.98.96"
  frozen_package_build_number="700098096"
  frozen_package_full_version="1.98.96-700098096"
  frozen_package_filename="tailscale-x86_64-1.98.96-700098096-dsm7.spk"
  frozen_package_sha256="bed218b4d0099102e9c3be18456d8a94be9a92b4a29295a9dab33932570cbce0"
  frozen_allowed_signers_sha256="7f6e0b0e70dd002171512380426103ca322c28a30ed2bde5815395f3c7e329c8"
  failures=0

  contract_fail() {
    release_fail "$1"
    failures=$((failures + 1))
  }

  for command_name in git python3 sha256sum; do
    if ! release_require_command "$command_name"; then
      failures=$((failures + 1))
    fi
  done

  if ! release_require_worktree "$source_repo"; then
    failures=$((failures + 1))
  fi

  if [ ! -s "$manifest" ]; then
    contract_fail "release manifest is missing or empty: ${manifest}"
  fi

  if [ "$failures" -ne 0 ]; then
    exit 1
  fi

  patch_root="$(
    release_resolve_path \
      "$control_worktree" \
      "$(release_manifest_get "$manifest" paths.patch_series)"
  )"
  evidence_root="$(
    release_resolve_path \
      "$control_worktree" \
      "$(release_manifest_get "$manifest" paths.evidence)"
  )"
  release_record="$(
    release_resolve_path \
      "$control_worktree" \
      "$(release_manifest_get "$manifest" paths.release_record)"
  )"
  allowed_signers="$(
    release_resolve_path \
      "$control_worktree" \
      "$(
        release_manifest_get \
          "$manifest" \
          validation.ssh_allowed_signers_path
      )"
  )"

  support_matrix="${control_worktree}/support-matrix.yaml"
  patch_base="${patch_root}/BASE"
  patch_manifest="${patch_root}/manifest.json"
  reproducible_manifest="${evidence_root}/reproducible-build/manifest.json"
  acceptance_environment="${evidence_root}/dsm-runtime/acceptance.env"
  candidate_checksum="${evidence_root}/dsm-runtime/runtime/candidate-spk.sha256"

  for required_path in \
    "$support_matrix" \
    "$patch_base" \
    "$patch_manifest" \
    "$reproducible_manifest" \
    "$acceptance_environment" \
    "$candidate_checksum" \
    "$allowed_signers" \
    "$release_record"; do
    if [ ! -s "$required_path" ]; then
      contract_fail \
        "production-contract input is missing or empty: ${required_path}"
    fi
  done

  if [ "$failures" -ne 0 ]; then
    exit 1
  fi

  accepted_commit="$(
    release_manifest_get "$manifest" downstream.release_commit
  )"
  accepted_tree="$(
    release_manifest_get "$manifest" downstream.release_tree
  )"
  accepted_branch="$(
    release_manifest_get "$manifest" branches.release
  )"
  accepted_tag="$(
    release_manifest_get "$manifest" tags.release
  )"
  expected_signers_sha256="$(
    release_manifest_get \
      "$manifest" \
      validation.ssh_allowed_signers_sha256
  )"
  observed_signers_sha256="$(
    sha256sum "$allowed_signers" |
      awk '{ print $1 }'
  )"

  if [ "$accepted_branch" != "$frozen_accepted_branch" ]; then
    contract_fail "accepted release branch differs from frozen contract"
  fi

  if [ "$observed_signers_sha256" != "$expected_signers_sha256" ]; then
    contract_fail \
      "allowed-signers checksum differs from the release manifest"
  fi

  if [ "$expected_signers_sha256" != "$frozen_allowed_signers_sha256" ]; then
    contract_fail \
      "manifest allowed-signers checksum differs from frozen contract"
  fi

  if [ "$observed_signers_sha256" != "$frozen_allowed_signers_sha256" ]; then
    contract_fail \
      "allowed-signers checksum differs from frozen contract"
  fi

  observed_commit="$(
    release_clean_git \
      -C "$source_repo" \
      rev-parse \
      --verify \
      --quiet \
      "${accepted_commit}^{commit}" ||
      true
  )"

  if [ "$observed_commit" != "$accepted_commit" ]; then
    contract_fail "accepted release commit is unavailable locally"
  else
    observed_tree="$(
      release_clean_git \
        -C "$source_repo" \
        rev-parse \
        "${accepted_commit}^{tree}"
    )"

    if [ "$observed_tree" != "$accepted_tree" ]; then
      contract_fail \
        "accepted release commit tree differs from the release manifest"
    fi

    if ! release_clean_git \
      -C "$source_repo" \
      -c gpg.format=ssh \
      -c "gpg.ssh.allowedSignersFile=${allowed_signers}" \
      verify-commit \
      "$accepted_commit"; then
      contract_fail "accepted release commit signature is invalid"
    fi

    matching_signoffs="$(
      release_count_matching_signoff \
        "$source_repo" \
        "$accepted_commit"
    )"
    total_signoffs="$(
      release_count_signoffs \
        "$source_repo" \
        "$accepted_commit"
    )"

    if [ "$total_signoffs" -ne 1 ] ||
      [ "$matching_signoffs" -ne 1 ]; then
      contract_fail \
        "accepted release commit must contain exactly one Signed-off-by trailer matching its author"
    fi
  fi

  branch_values=()

  for branch_ref in \
    "refs/heads/${accepted_branch}" \
    "refs/remotes/origin/${accepted_branch}"; do
    branch_value="$(
      release_clean_git \
        -C "$source_repo" \
        rev-parse \
        --verify \
        --quiet \
        "${branch_ref}^{commit}" ||
        true
    )"

    if [ -n "$branch_value" ]; then
      branch_values+=("$branch_value")
    fi
  done

  if [ "${#branch_values[@]}" -eq 0 ]; then
    contract_fail "accepted release branch is unavailable locally"
  else
    for branch_value in "${branch_values[@]}"; do
      if [ "$branch_value" != "$accepted_commit" ]; then
        contract_fail \
          "accepted release branch differs from the manifest commit"
      fi
    done
  fi

  tag_type="$(
    release_clean_git \
      -C "$source_repo" \
      cat-file \
      -t \
      "refs/tags/${accepted_tag}" \
      2> /dev/null ||
      true
  )"

  if [ "$tag_type" != "tag" ]; then
    contract_fail \
      "accepted release tag is absent or is not annotated"
  else
    tag_commit="$(
      release_clean_git \
        -C "$source_repo" \
        rev-parse \
        "refs/tags/${accepted_tag}^{commit}"
    )"
    tag_tree="$(
      release_clean_git \
        -C "$source_repo" \
        rev-parse \
        "refs/tags/${accepted_tag}^{tree}"
    )"

    if [ "$tag_commit" != "$accepted_commit" ]; then
      contract_fail "accepted release tag resolves to the wrong commit"
    fi

    if [ "$tag_tree" != "$accepted_tree" ]; then
      contract_fail "accepted release tag resolves to the wrong tree"
    fi

    if ! release_clean_git \
      -C "$source_repo" \
      -c gpg.format=ssh \
      -c "gpg.ssh.allowedSignersFile=${allowed_signers}" \
      verify-tag \
      "refs/tags/${accepted_tag}"; then
      contract_fail "accepted release tag signature is invalid"
    fi
  fi

  if ! python3 \
    - \
    "$manifest" \
    "$support_matrix" \
    "$patch_base" \
    "$patch_manifest" \
    "$reproducible_manifest" \
    "$acceptance_environment" \
    "$candidate_checksum" \
    "$release_record" \
    "$allowed_signers" \
    "$frozen_accepted_commit" \
    "$frozen_accepted_tree" \
    "$frozen_accepted_tag" \
    "$frozen_accepted_branch" \
    "$frozen_accepted_revision" \
    "$frozen_historical_tag" \
    "$frozen_tested_model" \
    "$frozen_synology_platform" \
    "$frozen_minimum_dsm" \
    "$frozen_package_architecture" \
    "$frozen_netfilter_package_min_version" \
    "$frozen_package_version" \
    "$frozen_package_build_number" \
    "$frozen_package_full_version" \
    "$frozen_package_filename" \
    "$frozen_package_sha256" << 'PY'; then
from __future__ import annotations

import base64
import hashlib
import json
import re
import sys
from pathlib import Path

(
    manifest_path,
    support_path,
    base_path,
    patch_manifest_path,
    reproducible_path,
    acceptance_path,
    candidate_path,
    release_record_path,
    allowed_signers_path,
) = map(Path, sys.argv[1:10])
(
    frozen_accepted_commit,
    frozen_accepted_tree,
    frozen_accepted_tag,
    frozen_accepted_branch,
    frozen_accepted_revision,
    frozen_historical_tag,
    frozen_tested_model,
    frozen_synology_platform,
    frozen_minimum_dsm,
    frozen_package_architecture,
    frozen_netfilter_package_min_version,
    frozen_package_version,
    frozen_package_build_number,
    frozen_package_full_version,
    frozen_package_filename,
    frozen_package_sha256,
) = sys.argv[10:]

failures: list[str] = []


def reject_duplicate_json_members(pairs):
    result = {}
    for key, value in pairs:
        if key in result:
            raise ValueError("duplicate JSON member")
        result[key] = value
    return result


def reject_nonstandard_json_constant(_constant):
    raise ValueError("non-standard JSON constant")


def load_json(path: Path):
    return json.loads(
        path.read_text(encoding="utf-8"),
        object_pairs_hook=reject_duplicate_json_members,
        parse_constant=reject_nonstandard_json_constant,
    )


def fail(message: str) -> None:
    failures.append(message)


def equal(observed, expected, message: str) -> None:
    if observed != expected:
        fail(f"{message}: observed={observed!r} expected={expected!r}")


def parse_pairs(path: Path) -> dict[str, str]:
    result: dict[str, str] = {}

    for number, raw in enumerate(
        path.read_text(encoding="utf-8").splitlines(),
        start=1,
    ):
        if not raw:
            continue
        if "=" not in raw:
            raise ValueError(f"{path}:{number}: expected key=value")
        key, value = raw.split("=", 1)
        if not key or key in result:
            raise ValueError(f"{path}:{number}: invalid or duplicate key")
        result[key] = value

    return result


def parse_allowed_signers(path: Path) -> tuple[list[str], list[str]]:
    principals: set[str] = set()
    fingerprints: set[str] = set()

    for number, raw in enumerate(
        path.read_text(encoding="utf-8").splitlines(),
        start=1,
    ):
        line = raw.strip()
        if not line or line.startswith("#"):
            continue

        parts = line.split()
        if len(parts) != 3 or not parts[1].startswith("ssh-"):
            raise ValueError(
                f"{path}:{number}: unsupported allowed-signers entry"
            )

        entry_principals, _key_type, encoded_key = parts
        for principal in entry_principals.split(","):
            if not principal:
                raise ValueError(
                    f"{path}:{number}: empty allowed-signers principal"
                )
            principals.add(principal)

        try:
            key_blob = base64.b64decode(encoded_key, validate=True)
        except ValueError as error:
            raise ValueError(
                f"{path}:{number}: invalid allowed-signers key"
            ) from error
        fingerprint = base64.b64encode(
            hashlib.sha256(key_blob).digest()
        ).decode("ascii").rstrip("=")
        fingerprints.add(f"SHA256:{fingerprint}")

    return sorted(principals), sorted(fingerprints)


def manifest_string_set(value, field: str) -> list[str]:
    if not isinstance(value, list) or not all(
        isinstance(item, str) and item for item in value
    ):
        raise ValueError(f"manifest {field} must be an array of strings")
    if len(value) != len(set(value)):
        raise ValueError(f"manifest {field} contains duplicates")
    return sorted(value)


def parse_support(path: Path) -> list[dict[str, object]]:
    production_fields = {
        "status",
        "model",
        "synology_platform",
        "package_arch",
        "dsm_min_version",
        "upstream_version",
        "downstream_package_version",
        "release_branch",
        "downstream_commit",
        "netfilter_package_min_version",
        "validation",
    }
    unsupported_fields = {"status", "package_arch", "reason"}
    validation_fields = {
        "upgrade",
        "controlled_restart",
        "tun_reconstruction",
        "reboot",
        "ipv4_netfilter",
        "ipv6_netfilter",
    }
    entries: list[dict[str, object]] = []
    current: dict[str, object] | None = None
    nested_key: str | None = None
    seen_schema = False
    seen_platforms = False

    def noncanonical(number: int, raw: str) -> None:
        raise ValueError(
            "support-matrix contains noncanonical content "
            f"at line {number}: {raw!r}"
        )

    for number, raw in enumerate(
        path.read_text(encoding="utf-8").splitlines(),
        start=1,
    ):
        if raw == "" or re.fullmatch(r" *#.*", raw):
            continue

        if raw == "schema_version: 1":
            if seen_schema or seen_platforms or entries:
                noncanonical(number, raw)
            seen_schema = True
            continue

        if raw == "platforms:":
            if not seen_schema or seen_platforms or entries:
                noncanonical(number, raw)
            seen_platforms = True
            continue

        if not seen_platforms:
            noncanonical(number, raw)

        start = re.fullmatch(
            r"  - status: (production|unsupported)",
            raw,
        )
        if start:
            current = {"status": start.group(1)}
            entries.append(current)
            nested_key = None
            continue

        field = re.fullmatch(
            r"    ([a-z_][a-z0-9_]*): "
            r"([A-Za-z0-9][A-Za-z0-9_+./:@= -]*)",
            raw,
        )
        if current is not None and field is not None:
            field_name = field.group(1)
            allowed_fields = (
                production_fields
                if current["status"] == "production"
                else unsupported_fields
            )
            if field_name not in allowed_fields or field_name == "validation":
                noncanonical(number, raw)
            if field_name in current:
                raise ValueError(
                    f"support-matrix {field_name} occurs more than once"
                )
            nested_key = None
            current[field_name] = field.group(2)
            continue

        mapping = re.fullmatch(r"    ([a-z_][a-z0-9_]*):", raw)
        if current is not None and mapping is not None:
            field_name = mapping.group(1)
            if current["status"] != "production" or field_name != "validation":
                noncanonical(number, raw)
            if field_name in current:
                raise ValueError(
                    f"support-matrix {field_name} occurs more than once"
                )
            nested_key = field_name
            current[nested_key] = {}
            continue

        nested = re.fullmatch(
            r"      ([a-z_][a-z0-9_]*): "
            r"([A-Za-z0-9][A-Za-z0-9_+./:@= -]*)",
            raw,
        )
        if current is not None and nested_key is not None and nested is not None:
            nested_values = current[nested_key]
            if not isinstance(nested_values, dict):
                raise ValueError(f"support-matrix {nested_key} is not a mapping")
            nested_name = nested.group(1)
            if nested_name not in validation_fields:
                noncanonical(number, raw)
            if nested_name in nested_values:
                raise ValueError(
                    "support-matrix "
                    f"{nested_key}.{nested_name} occurs more than once"
                )
            nested_values[nested_name] = nested.group(2)
            continue

        noncanonical(number, raw)

    if not seen_schema or not seen_platforms:
        raise ValueError("support-matrix lacks its canonical document header")

    return entries


def release_record_fields(text: str, field: str) -> list[str]:
    pattern = re.compile(
        rf"^\|\s*{re.escape(field)}\s*\|\s*(.*?)\s*\|$",
        re.MULTILINE,
    )
    return [
        match.replace("`", "").strip()
        for match in pattern.findall(text)
    ]


def release_record_accepted_package(
    text: str,
) -> tuple[str, str] | None:
    introduction = "The production-accepted sideload package is:"
    boundary = "The separately generated Package Center reference package"
    if text.count(introduction) != 1 or text.count(boundary) != 1:
        return None

    section = text.split(introduction, 1)[1].split(boundary, 1)[0]
    match = re.fullmatch(
        r"\s*```text[ \t]*\n([^\n]+)\n```"
        r"\s*SHA-256:\s*"
        r"```text[ \t]*\n([^\n]+)\n```\s*",
        section,
    )
    if match is None:
        return None

    return match.group(1).strip(), match.group(2).strip()


try:
    manifest = load_json(manifest_path)
    support_entries = parse_support(support_path)
    historical_base = parse_pairs(base_path)
    historical_manifest = load_json(patch_manifest_path)
    reproducible = load_json(reproducible_path)
    acceptance = parse_pairs(acceptance_path)
    release_record = release_record_path.read_text(encoding="utf-8")
    allowed_principals, allowed_fingerprints = parse_allowed_signers(
        allowed_signers_path
    )
    manifest_principals = manifest_string_set(
        manifest["validation"]["ssh_signer_principals"],
        "validation.ssh_signer_principals",
    )
    manifest_fingerprints = manifest_string_set(
        manifest["validation"]["ssh_signer_fingerprints"],
        "validation.ssh_signer_fingerprints",
    )
    candidate_lines = [
        line
        for line in candidate_path.read_text(encoding="utf-8").splitlines()
        if line
    ]
except (KeyError, TypeError, ValueError, json.JSONDecodeError) as error:
    print(f"FAIL: production-contract metadata could not be read: {error}")
    raise SystemExit(1) from error

accepted_commit = manifest["downstream"]["release_commit"]
accepted_tree = manifest["downstream"]["release_tree"]
accepted_branch = manifest["branches"]["release"]
accepted_revision = manifest["downstream"]["revision"]
accepted_tag = manifest["tags"]["release"]
accepted_package_version = manifest["package"]["version"]
accepted_build_number = manifest["package"]["build_number"]
accepted_filename = manifest["package"]["filename"]
accepted_sha256 = manifest["package"]["sha256"]
accepted_version = manifest["package"]["full_version"]

print(f"Accepted release tag: {accepted_tag}")

equal(
    accepted_commit,
    frozen_accepted_commit,
    "accepted release commit differs from frozen contract",
)
equal(
    accepted_tree,
    frozen_accepted_tree,
    "accepted release tree differs from frozen contract",
)
equal(
    accepted_tag,
    frozen_accepted_tag,
    "accepted release tag differs from frozen contract",
)
equal(
    accepted_revision,
    frozen_accepted_revision,
    "accepted release revision differs from frozen contract",
)
equal(
    accepted_tag,
    f"release/synology-v{accepted_package_version}-{accepted_revision}",
    "accepted release tag differs from package version and revision",
)
equal(
    accepted_package_version,
    frozen_package_version,
    "accepted package version differs from frozen contract",
)
equal(
    accepted_build_number,
    frozen_package_build_number,
    "accepted package build number differs from frozen contract",
)
equal(
    accepted_version,
    f"{accepted_package_version}-{accepted_build_number}",
    "package full_version does not equal package.version-build_number",
)
equal(
    accepted_version,
    frozen_package_full_version,
    "accepted package full version differs from frozen contract",
)
equal(
    accepted_filename,
    frozen_package_filename,
    "accepted package filename differs from frozen contract",
)
equal(
    accepted_sha256,
    frozen_package_sha256,
    "accepted package SHA-256 differs from frozen contract",
)
equal(
    allowed_principals,
    manifest_principals,
    "allowed-signers principals differ from authoritative manifest set",
)
equal(
    allowed_fingerprints,
    manifest_fingerprints,
    "allowed-signers fingerprints differ from authoritative manifest set",
)

production_entries = [
    entry for entry in support_entries if entry.get("status") == "production"
]
historical_support = historical_manifest.get("support")

if not isinstance(historical_support, dict):
    fail("historical manifest support is not a mapping")
else:
    for field in (
        "tested_model",
        "synology_platform",
        "minimum_dsm",
        "package_arch",
        "netfilter_package_min_version",
    ):
        equal(
            historical_support.get(field),
            historical_base.get(field),
            f"historical support {field} differs between BASE and manifest.json",
        )

for field, expected in (
    ("tested_model", frozen_tested_model),
    ("synology_platform", frozen_synology_platform),
    ("minimum_dsm", frozen_minimum_dsm),
    ("package_arch", frozen_package_architecture),
    ("netfilter_package_min_version", frozen_netfilter_package_min_version),
):
    equal(
        historical_base.get(field),
        expected,
        f"historical support {field} differs from frozen contract",
    )

if len(production_entries) != 1:
    fail("support-matrix must contain exactly one production entry")
else:
    production = production_entries[0]
    for field in (
        "status",
        "model",
        "synology_platform",
        "package_arch",
        "dsm_min_version",
        "upstream_version",
        "downstream_package_version",
        "release_branch",
        "downstream_commit",
        "netfilter_package_min_version",
        "validation",
    ):
        if field not in production:
            fail(f"support-matrix {field} must occur exactly once")

    equal(
        production.get("upstream_version"),
        manifest["upstream"]["tag"],
        "support-matrix upstream_version differs from release manifest",
    )
    equal(
        production.get("downstream_package_version"),
        accepted_version,
        "support-matrix package version differs from accepted package",
    )
    equal(
        production.get("release_branch"),
        accepted_branch,
        "support-matrix release_branch differs from accepted release branch",
    )
    equal(
        production.get("downstream_commit"),
        accepted_commit,
        "support-matrix downstream_commit differs from accepted release commit",
    )
    equal(
        production.get("package_arch"),
        manifest["package"]["architecture"],
        "support-matrix package_arch differs from accepted package",
    )
    equal(
        production.get("dsm_min_version"),
        manifest["synology"]["minimum_dsm"],
        "support-matrix minimum DSM differs from release manifest",
    )
    equal(
        historical_base.get("minimum_dsm"),
        manifest["synology"]["minimum_dsm"],
        "historical support minimum_dsm differs from release manifest",
    )
    equal(
        production.get("dsm_min_version"),
        historical_base.get("minimum_dsm"),
        "support-matrix minimum DSM differs from historical support",
    )

    for support_field, manifest_field, historical_field in (
        ("model", "tested_models", "tested_model"),
        ("synology_platform", "platforms", "synology_platform"),
    ):
        values = manifest["synology"][manifest_field]
        if not isinstance(values, list) or len(values) != 1:
            fail(f"manifest synology.{manifest_field} must contain one value")
        else:
            equal(
                production.get(support_field),
                values[0],
                f"support-matrix {support_field} differs from release manifest",
            )
            equal(
                historical_base.get(historical_field),
                values[0],
                f"historical support {historical_field} differs from release manifest",
            )
            equal(
                production.get(support_field),
                historical_base.get(historical_field),
                f"support-matrix {support_field} differs from historical support",
            )

    architectures = manifest["synology"]["architectures"]
    if not isinstance(architectures, list) or len(architectures) != 1:
        fail("manifest synology.architectures must contain one value")
    else:
        equal(
            production.get("package_arch"),
            architectures[0],
            "support-matrix package_arch differs from supported architecture",
        )
        equal(
            historical_base.get("package_arch"),
            architectures[0],
            "historical support package_arch differs from release manifest",
        )
        equal(
            production.get("package_arch"),
            historical_base.get("package_arch"),
            "support-matrix package_arch differs from historical support",
        )

    dependency_match = re.search(
        r">=\s*([^\s]+)$",
        manifest["synology"]["netfilter_dependency"],
    )
    if not dependency_match:
        fail("manifest netfilter dependency lacks a minimum version")
    else:
        equal(
            production.get("netfilter_package_min_version"),
            dependency_match.group(1),
            "support-matrix netfilter minimum differs from release manifest",
        )
        equal(
            historical_base.get("netfilter_package_min_version"),
            dependency_match.group(1),
            "historical support netfilter_package_min_version differs from release manifest",
        )
        equal(
            production.get("netfilter_package_min_version"),
            historical_base.get("netfilter_package_min_version"),
            "support-matrix netfilter minimum differs from historical support",
        )

    support_validation = production.get("validation")
    if not isinstance(support_validation, dict):
        fail("support-matrix production validation is not a mapping")
    else:
        for field in (
            "upgrade",
            "controlled_restart",
            "tun_reconstruction",
            "reboot",
            "ipv4_netfilter",
            "ipv6_netfilter",
        ):
            if field not in support_validation:
                fail(
                    f"support-matrix validation.{field} must occur exactly once"
                )
            else:
                equal(
                    support_validation[field],
                    "passed",
                    f"support-matrix validation.{field} is not passed",
                )

historical_tag = historical_base.get("release_tag")
print(f"Historical patch lineage tag: {historical_tag}")
equal(
    historical_tag,
    frozen_historical_tag,
    "historical patch lineage tag differs from frozen contract",
)
if historical_tag == accepted_tag:
    fail("historical patch lineage tag must differ from accepted release tag")
equal(
    historical_manifest.get("release", {}).get("tag"),
    historical_tag,
    "historical patch lineage tag differs between BASE and manifest.json",
)

for base_field, expected, message in (
    ("release_commit", accepted_commit, "historical BASE commit differs from accepted release"),
    ("release_tree", accepted_tree, "historical BASE tree differs from accepted release"),
    ("release_branch", frozen_accepted_branch, "historical BASE branch differs from frozen contract"),
    ("package_version", accepted_version, "historical BASE package version differs from accepted release"),
    ("sideload_sha256", accepted_sha256, "historical BASE package SHA-256 differs from accepted release"),
):
    equal(historical_base.get(base_field), expected, message)

historical_release = historical_manifest.get("release", {})
for field, expected, message in (
    ("commit", accepted_commit, "historical manifest commit differs from accepted release"),
    ("tree", accepted_tree, "historical manifest tree differs from accepted release"),
    ("branch", frozen_accepted_branch, "historical manifest branch differs from frozen contract"),
    ("package_version", accepted_version, "historical manifest package version differs from accepted release"),
):
    equal(historical_release.get(field), expected, message)

historical_sideload = historical_manifest.get("reproducible_build", {}).get(
    "sideload", {}
)
equal(
    historical_sideload.get("filename"),
    accepted_filename,
    "historical manifest package filename differs from accepted package",
)
equal(
    historical_sideload.get("sha256"),
    accepted_sha256,
    "historical manifest package SHA-256 differs from accepted package",
)

equal(
    reproducible.get("release_commit"),
    accepted_commit,
    "reproducible-build commit differs from accepted release",
)
equal(
    reproducible.get("release_tree"),
    accepted_tree,
    "reproducible-build tree differs from accepted release",
)
reproducible_sideload = reproducible.get("sideload", {})
equal(
    reproducible_sideload.get("filename"),
    accepted_filename,
    "reproducible-build sideload filename differs from accepted package",
)
equal(
    reproducible_sideload.get("sha256"),
    accepted_sha256,
    "reproducible-build sideload SHA-256 differs from accepted package",
)
equal(
    reproducible_sideload.get("independent_builds_identical"),
    True,
    "reproducible-build independent-build result is not true",
)
equal(
    reproducible.get("source_evidence_checksums_valid"),
    True,
    "reproducible-build source evidence checksums are not valid",
)

expected_record_title = (
    "# Tailscale Synology DSM "
    f"{manifest['package']['version']}-{manifest['downstream']['revision']} "
    "release closeout"
)
record_title = release_record.splitlines()[0] if release_record else None
equal(
    record_title,
    expected_record_title,
    "permanent release record title differs from accepted release",
)

for field, expected, message in (
    (
        "Upstream Tailscale release",
        manifest["upstream"]["tag"],
        "permanent release record upstream tag differs from accepted release",
    ),
    (
        "Synology package version",
        accepted_version,
        "permanent release record package version differs from accepted release",
    ),
    (
        "Release revision",
        manifest["downstream"]["revision"],
        "permanent release record revision differs from accepted release",
    ),
    (
        "Final release commit",
        frozen_accepted_commit,
        "permanent release record commit differs from frozen contract",
    ),
    (
        "Final release tree",
        frozen_accepted_tree,
        "permanent release record tree differs from frozen contract",
    ),
    (
        "Integration branch",
        manifest["control"]["branch"],
        "permanent release record integration branch differs from release manifest",
    ),
    (
        "Release branch",
        frozen_accepted_branch,
        "permanent release record release branch differs from frozen contract",
    ),
    (
        "Target platform",
        f"Synology DSM 7, {manifest['package']['architecture']}",
        "permanent release record target platform differs from accepted package",
    ),
    (
        "Minimum DSM version",
        manifest["synology"]["minimum_dsm"],
        "permanent release record minimum DSM differs from release manifest",
    ),
):
    observed_fields = release_record_fields(release_record, field)
    if len(observed_fields) != 1:
        fail(f"permanent release record {field} must occur exactly once")
    else:
        equal(observed_fields[0], expected, message)

record_package = release_record_accepted_package(release_record)
if record_package is None:
    fail("permanent release record accepted package identity must occur exactly once")
else:
    record_filename, record_sha256 = record_package
    equal(
        record_filename,
        frozen_package_filename,
        "permanent release record filename differs from frozen contract",
    )
    equal(
        record_sha256,
        frozen_package_sha256,
        "permanent release record package SHA-256 differs from frozen contract",
    )

equal(
    acceptance.get("validation_failures"),
    "0",
    "DSM acceptance validation_failures is not zero",
)
equal(
    acceptance.get("release_commit"),
    accepted_commit,
    "DSM acceptance commit differs from accepted release",
)
equal(
    acceptance.get("package_version"),
    accepted_version,
    "DSM acceptance package version differs from accepted package",
)
equal(
    acceptance.get("candidate_spk_sha256"),
    accepted_sha256,
    "DSM acceptance package SHA-256 differs from accepted package",
)

for field, expected in (
    ("same_version_install", "accepted"),
    ("bootstrap_refresh", "required_and_completed"),
    ("bootstrap_state", "current"),
    ("privilege_mode", "root"),
    ("runtime_uid", "0"),
    ("node_identity_preserved", "true"),
    ("tailscale_ipv4_preserved", "true"),
    ("persistent_state_preserved", "true"),
    ("localapi_operational", "true"),
    ("tailscaled_process_validated", "true"),
    ("netfilter_reconciler_validated", "true"),
    ("filter_ts_input", "present"),
    ("filter_ts_forward", "present"),
    ("nat_ts_postrouting", "present"),
    ("preferences_preserved", "true"),
):
    equal(
        acceptance.get(field),
        expected,
        f"DSM acceptance {field} differs from accepted result",
    )
equal(
    acceptance.get("acceptance"),
    "PASS",
    "DSM acceptance verdict is not PASS",
)

if len(candidate_lines) != 1 or len(candidate_lines[0].split()) != 2:
    fail("candidate SPK checksum record must contain exactly one digest and filename")
else:
    candidate_digest, candidate_filename = candidate_lines[0].split()
    equal(
        candidate_digest,
        accepted_sha256,
        "candidate SPK checksum differs from accepted package",
    )
    if candidate_filename.startswith("*"):
        if candidate_filename != f"*{accepted_filename}":
            fail("candidate SPK filename uses an invalid checksum marker")
    else:
        equal(
            candidate_filename,
            accepted_filename,
            "candidate SPK filename differs from accepted package",
        )

if failures:
    for message in failures:
        print(f"FAIL: {message}")
    raise SystemExit(1)

print("PASS: structured living metadata, immutable evidence and patch lineage agree.")
PY
    failures=$((failures + 1))
  fi

  if [ "$failures" -eq 0 ]; then
    release_pass \
      "accepted-release identity and historical patch lineage are coherent."
    exit 0
  fi

  exit 1
)

release_validate_patch_inventory() {
  manifest="$1"
  patch_root="$2"

  python3 \
    - "$manifest" "$patch_root" << 'PY'
import json
import sys
from pathlib import Path


def reject_duplicate_json_members(pairs):
    result = {}
    for key, value in pairs:
        if key in result:
            raise ValueError("duplicate JSON member")
        result[key] = value
    return result


def reject_nonstandard_json_constant(_constant):
    raise ValueError("non-standard JSON constant")


def load_json(path):
    return json.loads(
        path.read_text(encoding="utf-8"),
        object_pairs_hook=reject_duplicate_json_members,
        parse_constant=reject_nonstandard_json_constant,
    )


manifest = load_json(Path(sys.argv[1]))
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
      release_clean_git -C "$target_worktree" am --3way "${patch_files[@]}"
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

release_absolute_path() {
  python3 - "$1" << 'PY'
import sys
from pathlib import Path

print(Path(sys.argv[1]).expanduser().resolve(strict=False))
PY
}

release_validate_version_preparation_manifest() {
  manifest="$1"
  schema="$2"
  baseline="$3"

  python3 - "$manifest" "$schema" "$baseline" << 'PY'
import json
import re
import sys
from pathlib import Path, PurePosixPath


def reject_duplicate_members(pairs):
    result = {}
    for key, value in pairs:
        if key in result:
            raise ValueError(f"duplicate JSON member: {key}")
        result[key] = value
    return result


def reject_constant(value):
    raise ValueError(f"non-standard JSON constant: {value}")


def load(path):
    return json.loads(
        Path(path).read_text(encoding="utf-8"),
        object_pairs_hook=reject_duplicate_members,
        parse_constant=reject_constant,
    )


manifest = load(sys.argv[1])
schema = load(sys.argv[2])
baseline = load(sys.argv[3])

required = set(schema["required"])
if set(manifest) != required:
    raise SystemExit("version-preparation manifest fields differ from the schema")
if manifest["schema_version"] != 1:
    raise SystemExit("unsupported version-preparation manifest schema")

sha = re.compile(r"^[0-9a-f]{40}$")
digest = re.compile(r"^[0-9a-f]{64}$")
tag = re.compile(r"^v[0-9]+\.[0-9]+\.[0-9]+(?:-[0-9A-Za-z.-]+)?$")
version = re.compile(r"^[0-9]+\.[0-9]+\.[0-9]+(?:-[0-9A-Za-z.-]+)?$")
revision = re.compile(r"^r[1-9][0-9]*$")

source = manifest["source"]
if set(source) != {
    "repository",
    "previous_upstream_commit",
    "previous_release_commit",
}:
    raise SystemExit("manifest source fields differ")
if not source["repository"]:
    raise SystemExit("manifest source repository is empty")
for field in ("previous_upstream_commit", "previous_release_commit"):
    if not sha.fullmatch(source[field]):
        raise SystemExit(f"manifest source {field} is not a full Git SHA")

upstream = manifest["upstream"]
if set(upstream) != {"tag", "commit"}:
    raise SystemExit("manifest upstream fields differ")
if not tag.fullmatch(upstream["tag"]) or not sha.fullmatch(upstream["commit"]):
    raise SystemExit("manifest upstream identity is invalid")

identity = manifest["version"]
if set(identity) != {"upstream", "downstream_revision"}:
    raise SystemExit("manifest version fields differ")
if not version.fullmatch(identity["upstream"]):
    raise SystemExit("manifest upstream version is invalid")
if not revision.fullmatch(identity["downstream_revision"]):
    raise SystemExit("manifest downstream revision is invalid")
if upstream["tag"] != f"v{identity['upstream']}":
    raise SystemExit("manifest tag and version differ")

prepared = manifest["prepared"]
if set(prepared) != {"branch", "commit", "tree", "worktree"}:
    raise SystemExit("manifest prepared fields differ")
expected_branch = (
    f"work/v{identity['upstream']}-synology-"
    f"{identity['downstream_revision']}"
)
if prepared["branch"] != expected_branch:
    raise SystemExit("manifest prepared branch differs from version identity")
if not sha.fullmatch(prepared["commit"]) or not sha.fullmatch(prepared["tree"]):
    raise SystemExit("manifest prepared Git identity is invalid")
if not prepared["worktree"]:
    raise SystemExit("manifest prepared worktree is empty")

logical = manifest["logical_commits"]
patches = manifest["patches"]
if not logical or len(logical) != len(patches):
    raise SystemExit("logical commit and patch counts must be equal and non-zero")
for index, item in enumerate(logical, start=1):
    if set(item) != {"order", "source_commit", "prepared_commit", "subject"}:
        raise SystemExit("logical commit fields differ")
    if item["order"] != index:
        raise SystemExit("logical commits are not consecutively ordered")
    if not sha.fullmatch(item["source_commit"]) or not sha.fullmatch(item["prepared_commit"]):
        raise SystemExit("logical commit identity is invalid")
    if not item["subject"]:
        raise SystemExit("logical commit subject is empty")

for index, item in enumerate(patches, start=1):
    if set(item) != {"order", "filename", "sha256"}:
        raise SystemExit("patch fields differ")
    if item["order"] != index:
        raise SystemExit("patches are not consecutively ordered")
    filename = item["filename"]
    pure = PurePosixPath(filename)
    if (
        pure.name != filename
        or not re.fullmatch(r"[0-9]{4}-.+\.patch", filename)
        or not digest.fullmatch(item["sha256"])
    ):
        raise SystemExit("patch artifact identity is invalid")

if manifest["synology_contract"] != baseline["synology_contract"]:
    raise SystemExit("manifest Synology contract differs from the baseline")
if manifest["safety"] != baseline["safety"]:
    raise SystemExit("manifest safety contract differs from the baseline")
if set(manifest["safety"].values()) != {False}:
    raise SystemExit("manifest safety capabilities must all be false")

validation = manifest["validation"]
if set(validation) != {
    "source_range_linear",
    "signed_commits",
    "single_signoff_commits",
    "patch_round_trip",
    "round_trip_tree",
}:
    raise SystemExit("manifest validation fields differ")
if validation["round_trip_tree"] != prepared["tree"]:
    raise SystemExit("manifest round-trip tree differs from prepared tree")
for field in (
    "source_range_linear",
    "signed_commits",
    "single_signoff_commits",
    "patch_round_trip",
):
    if validation[field] is not True:
        raise SystemExit(f"manifest validation is not true: {field}")

print("PASS: version-preparation manifest satisfies the strict schema contract.")
PY
}
