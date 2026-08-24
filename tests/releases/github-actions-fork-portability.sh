#!/usr/bin/env bash
set -u

REPO_ROOT="$(
  cd \
    "$(dirname "${BASH_SOURCE[0]}")/../.." &&
    pwd
)"

python3 - \
  "${REPO_ROOT}/.github/workflows/vet.yml" \
  "${REPO_ROOT}/.github/workflows/test.yml" \
  "${REPO_ROOT}/.github/workflows/synology-product.yml" \
  "${REPO_ROOT}/.github/workflows/docker-file-build.yml" \
  "${REPO_ROOT}/.github/workflows/natlab-integrationtest.yml" \
  "${REPO_ROOT}/.github/workflows/golangci-lint.yml" << 'PY'
import re
import sys
from pathlib import Path


def top_level_block(workflow: str, key: str) -> str:
    lines = workflow.splitlines()
    marker = re.compile(rf"^{re.escape(key)}:\s*(?:#.*)?$")
    start = next(
        (index for index, line in enumerate(lines) if marker.match(line)),
        None,
    )
    if start is None:
        return ""

    end = len(lines)
    for index in range(start + 1, len(lines)):
        if re.match(r"^[A-Za-z0-9_-]+:\s*(?:#.*)?$", lines[index]):
            end = index
            break
    return "\n".join(lines[start:end])


def mapping_block(text: str, key: str, indent: int) -> str:
    lines = text.splitlines()
    marker = f"{' ' * indent}{key}:"
    try:
        start = lines.index(marker)
    except ValueError:
        return ""

    end = len(lines)
    sibling = re.compile(
        rf"^{' ' * indent}[A-Za-z0-9_-]+:\s*(?:#.*)?$"
    )
    for index in range(start + 1, len(lines)):
        if sibling.match(lines[index]):
            end = index
            break
    return "\n".join(lines[start:end])


def mapping_keys(text: str, indent: int) -> list[str]:
    pattern = re.compile(
        rf"^{' ' * indent}([A-Za-z0-9_-]+):\s*(?:#.*)?$"
    )
    return [
        match.group(1)
        for line in text.splitlines()
        if (match := pattern.match(line))
    ]


def list_values(text: str, indent: int) -> list[str]:
    pattern = re.compile(rf"^{' ' * indent}-\s+(.+?)\s*$")
    return [
        match.group(1).strip("'\"")
        for line in text.splitlines()
        if (match := pattern.match(line))
    ]


def job_block(workflow: str, job: str) -> str:
    lines = workflow.splitlines()
    marker = f"  {job}:"
    try:
        start = lines.index(marker)
    except ValueError:
        raise SystemExit(f"FAIL: workflow job is missing: {job}")

    end = len(lines)
    for index in range(start + 1, len(lines)):
        if re.match(r"^  [A-Za-z0-9_-]+:\s*(?:#.*)?$", lines[index]):
            end = index
            break
    return "\n".join(lines[start:end])


def runs_on(job: str) -> list[str]:
    return re.findall(r"(?m)^    runs-on:\s*(.*?)\s*$", job)


def alls_green_allowed_skips(job: str) -> list[str]:
    with_blocks = re.findall(
        r"(?m)^      uses: re-actors/alls-green@[^\n]+\n"
        r"      with:\n"
        r"((?:        [^\n]+\n?)*)",
        job,
    )
    if len(with_blocks) != 1:
        return []
    return re.findall(
        r"(?m)^        allowed-skips:\s*(.*?)\s*$",
        with_blocks[0],
    )


def read_workflow(path: Path) -> str:
    if not path.is_file():
        return ""
    return path.read_text(encoding="utf-8")


def trigger_names(workflow: str) -> list[str]:
    return mapping_keys(top_level_block(workflow, "on"), 2)


def assert_triggers(
    failures: list[str],
    workflow_name: str,
    workflow: str,
    expected: list[str],
) -> None:
    observed = trigger_names(workflow)
    if observed != expected:
        failures.append(
            f"{workflow_name} triggers must be exactly {expected!r} "
            f"(observed: {observed!r})"
        )


vet_path = Path(sys.argv[1])
test_path = Path(sys.argv[2])
synology_product_path = Path(sys.argv[3])
docker_path = Path(sys.argv[4])
natlab_path = Path(sys.argv[5])
golangci_lint_path = Path(sys.argv[6])

vet_workflow = read_workflow(vet_path)
test_workflow = read_workflow(test_path)
synology_product_workflow = read_workflow(synology_product_path)
docker_workflow = read_workflow(docker_path)
natlab_workflow = read_workflow(natlab_path)
golangci_lint_workflow = read_workflow(golangci_lint_path)

vet = job_block(vet_workflow, "vet")
windows = job_block(test_workflow, "windows")
fuzz = job_block(test_workflow, "fuzz")
merge_blocker = job_block(test_workflow, "merge_blocker")
check_mergeability_strict = job_block(test_workflow, "check_mergeability_strict")
check_mergeability = job_block(test_workflow, "check_mergeability")
golangci_lint = job_block(golangci_lint_workflow, "golangci")

failures: list[str] = []

if not synology_product_workflow:
    failures.append(
        "focused Synology product workflow is missing: "
        ".github/workflows/synology-product.yml"
    )
else:
    assert_triggers(
        failures,
        "synology-product workflow",
        synology_product_workflow,
        ["pull_request", "workflow_dispatch"],
    )

    pull_request = mapping_block(
        top_level_block(synology_product_workflow, "on"),
        "pull_request",
        2,
    )
    branches = mapping_block(pull_request, "branches", 4)
    observed_bases = list_values(branches, 6)
    expected_bases = ["release/*-synology", "synology/main"]
    if observed_bases != expected_bases:
        failures.append(
            "synology-product pull_request bases must be exactly "
            f"{expected_bases!r} (observed: {observed_bases!r})"
        )

    jobs = top_level_block(synology_product_workflow, "jobs")
    observed_jobs = mapping_keys(jobs, 2)
    if observed_jobs != ["synology-product"]:
        failures.append(
            "synology-product workflow must contain exactly one job named "
            f"synology-product (observed jobs: {observed_jobs!r})"
        )
    else:
        product = job_block(synology_product_workflow, "synology-product")

        names = re.findall(r"(?m)^    name:\s*(.*?)\s*$", product)
        if names != ["synology-product"]:
            failures.append(
                "synology-product job name must be exactly synology-product "
                f"(observed: {names!r})"
            )

        product_runners = runs_on(product)
        if product_runners != ["ubuntu-24.04"]:
            failures.append(
                "synology-product job must use exactly ubuntu-24.04 "
                f"(observed runs-on: {product_runners!r})"
            )

        timeouts = re.findall(
            r"(?m)^    timeout-minutes:\s*(.*?)\s*$",
            product,
        )
        if timeouts != ["45"]:
            failures.append(
                "synology-product job must have timeout-minutes 45 "
                f"(observed: {timeouts!r})"
            )

        permissions = mapping_block(product, "permissions", 4)
        contents_permissions = re.findall(
            r"(?m)^      contents:\s*(.*?)\s*$",
            permissions,
        )
        if contents_permissions != ["read"]:
            failures.append(
                "synology-product job permissions must set contents to read "
                f"(observed: {contents_permissions!r})"
            )

        checkout_uses = re.findall(
            r"(?m)^        uses:\s*actions/checkout@([^\s#]+)",
            product,
        )
        expected_checkout = "de0fac2e4500dabe0009e67214ff5f5447ce83dd"
        if checkout_uses != [expected_checkout]:
            failures.append(
                "synology-product must use exactly one checkout pinned to "
                f"{expected_checkout} (observed: {checkout_uses!r})"
            )

        fetch_depths = re.findall(
            r"(?m)^          fetch-depth:\s*(.*?)\s*$",
            product,
        )
        if fetch_depths != ["0"]:
            failures.append(
                "synology-product checkout must set fetch-depth to 0 "
                f"(observed: {fetch_depths!r})"
            )

        required_commands = [
            "bash tests/releases/version-preparation-contract.sh",
            "bash tests/releases/prepare-version-workflow.sh all",
            "bash tests/releases/control-pre-commit.sh",
            "bash tests/releases/promoted-patch-inventory.sh",
            "bash tests/releases/github-actions-fork-portability.sh",
            "bash tests/releases/shellcheck.sh",
            "bash tests/releases/diff-check.sh",
            'export PATH="$PWD/tool:$PATH"',
            "./tool/go test -count=1",
            "./release/dist/synology",
            "./cmd/tailscale/cli",
            "./cmd/tailscaled",
            "./ipn/ipnlocal",
            "./util/linuxfw",
            "./wgengine/router",
            "git diff --check",
            "git status --porcelain=v1 --untracked-files=all",
        ]
        for command in required_commands:
            if command not in product:
                failures.append(
                    "synology-product job must invoke required gate: "
                    f"{command}"
                )

        required_inventory_contract = [
            "find release/dist/synology/tests",
            "-name '*-test.sh'",
            "LC_ALL=C sort",
            "${#synology_tests[@]}",
            "for test_script in \"${synology_tests[@]}\"",
            "bash \"$test_script\"",
        ]
        for snippet in required_inventory_contract:
            if snippet not in product:
                failures.append(
                    "synology-product shell-test inventory must contain: "
                    f"{snippet}"
                )

        if "command -v shellcheck" not in product or \
                "ShellCheck is required" not in product:
            failures.append(
                "synology-product must fail clearly when ShellCheck is unavailable"
            )

        shellcheck_contract = [
            "SHELLCHECK_VERSION: v0.11.0",
            (
                "SHELLCHECK_SHA256: "
                "8c3be12b05d5c177a04c29e3c78ce89ac86f1595681cab149b65b97c4e227198"
            ),
            (
                "https://github.com/koalaman/shellcheck/releases/download/"
                "${SHELLCHECK_VERSION}/shellcheck-${SHELLCHECK_VERSION}.linux.x86_64.tar.xz"
            ),
            "sha256sum --check -",
            'echo "$shellcheck_dir" >> "$GITHUB_PATH"',
            '"$shellcheck_dir/shellcheck" --version',
        ]
        for snippet in shellcheck_contract:
            if snippet not in product:
                failures.append(
                    "synology-product must install checksum-pinned "
                    f"ShellCheck 0.11.0: {snippet}"
                )

assert_triggers(
    failures,
    "full CI workflow",
    test_workflow,
    ["push", "merge_group", "workflow_dispatch"],
)
assert_triggers(
    failures,
    "golangci-lint workflow",
    golangci_lint_workflow,
    ["pull_request", "workflow_dispatch"],
)

lint_checkout_uses = re.findall(
    r"(?m)^      - uses:\s*actions/checkout@([^\s#]+)",
    golangci_lint,
)
if lint_checkout_uses != ["de0fac2e4500dabe0009e67214ff5f5447ce83dd"]:
    failures.append(
        "golangci-lint must use exactly one checksum-pinned checkout "
        f"(observed: {lint_checkout_uses!r})"
    )

lint_contract = [
    "fetch-depth: 0",
    "id: lint-base",
    'git merge-base HEAD "$PR_BASE_SHA"',
    'git rev-parse HEAD^',
    'git cat-file -e "${lint_base}^{commit}"',
    "--new-from-rev=${{ steps.lint-base.outputs.sha }}",
]
for snippet in lint_contract:
    if snippet not in golangci_lint:
        failures.append(
            "golangci-lint must derive its baseline locally for oversized "
            f"pull requests: {snippet}"
        )

if "only-new-issues: true" in golangci_lint:
    failures.append(
        "golangci-lint must not request GitHub's size-limited PR diff"
    )
assert_triggers(
    failures,
    "Dockerfile build workflow",
    docker_workflow,
    ["push", "workflow_dispatch"],
)
assert_triggers(
    failures,
    "natlab integration workflow",
    natlab_workflow,
    ["push", "merge_group", "workflow_dispatch"],
)

vet_runners = runs_on(vet)
if vet_runners != ["ubuntu-24.04"] or "self-hosted" in vet:
    failures.append(
        "vet job must use exactly ubuntu-24.04 and no self-hosted selector "
        f"(observed runs-on: {vet_runners!r})"
    )

windows_runners = runs_on(windows)
if windows_runners != ["windows-2022"] or "ci-windows-github-1" in windows:
    failures.append(
        "windows job must use exactly windows-2022 and no ci-windows-github-1 "
        f"selector (observed runs-on: {windows_runners!r})"
    )

fuzz_condition = (
    "github.event_name == 'pull_request' && "
    "github.repository == 'tailscale/tailscale'"
)
fuzz_conditions = re.findall(r"(?m)^    if:\s*(.*?)\s*$", fuzz)
if fuzz_conditions != [fuzz_condition]:
    failures.append(
        "fuzz job must run only for pull requests in tailscale/tailscale "
        f"(observed if: {fuzz_conditions!r})"
    )

allowed_skips = (
    "${{ github.repository != 'tailscale/tailscale' && "
    "'vm, fuzz' || '' }}"
)
for job_name, job in (
    ("merge_blocker", merge_blocker),
    ("check_mergeability", check_mergeability),
):
    observed = alls_green_allowed_skips(job)
    if observed != [allowed_skips]:
        failures.append(
            f"{job_name} must allow only skipped vm and fuzz jobs in downstream "
            f"forks (observed allowed-skips: {observed!r})"
        )

strict_allowed_skips = alls_green_allowed_skips(check_mergeability_strict)
if strict_allowed_skips:
    failures.append(
        "check_mergeability_strict must not allow skipped jobs "
        f"(observed allowed-skips: {strict_allowed_skips!r})"
    )

for failure in failures:
    print(f"FAIL: {failure}", file=sys.stderr)

if failures:
    print(f"Failures: {len(failures)}", file=sys.stderr)
    raise SystemExit(1)

print("PASS: GitHub Actions jobs use fork-portable runners and fuzz ownership.")
print("PASS: downstream PRs use one focused Synology product gate.")
print("PASS: inherited heavy compatibility workflows use explicit triggers.")
PY
PYTHON_RC=$?

if [ "$PYTHON_RC" -ne 0 ]; then
  exit "$PYTHON_RC"
fi

PKG_DEPS_PATH="release/dist/synology/files/PKG_DEPS"
ATTRIBUTES="$(
  git \
    -C "$REPO_ROOT" \
    check-attr \
    text \
    eol \
    -- \
    "$PKG_DEPS_PATH"
)"
ATTRIBUTES_RC=$?

if [ "$ATTRIBUTES_RC" -ne 0 ]; then
  printf 'FAIL: could not read effective Git attributes for %s\n' \
    "$PKG_DEPS_PATH" >&2
  exit "$ATTRIBUTES_RC"
fi

TEXT_ATTRIBUTE="$(
  printf '%s\n' "$ATTRIBUTES" |
    awk '$2 == "text:" { print $3 }'
)"
EOL_ATTRIBUTE="$(
  printf '%s\n' "$ATTRIBUTES" |
    awk '$2 == "eol:" { print $3 }'
)"

if [ "$TEXT_ATTRIBUTE" != "set" ] ||
  [ "$EOL_ATTRIBUTE" != "lf" ]; then
  printf 'FAIL: %s must have effective attributes text=set and eol=lf; got text=%s eol=%s\n' \
    "$PKG_DEPS_PATH" \
    "$TEXT_ATTRIBUTE" \
    "$EOL_ATTRIBUTE" >&2
  exit 1
fi

echo "PASS: PKG_DEPS uses LF checkout bytes on every platform."
