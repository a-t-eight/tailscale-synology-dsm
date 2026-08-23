#!/usr/bin/env bash
set -u

REPO_ROOT="$(
  cd \
    "$(dirname "${BASH_SOURCE[0]}")/../.." &&
    pwd
)"

python3 - \
  "${REPO_ROOT}/.github/workflows/vet.yml" \
  "${REPO_ROOT}/.github/workflows/test.yml" << 'PY'
import re
import sys
from pathlib import Path


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


vet_workflow = Path(sys.argv[1]).read_text(encoding="utf-8")
test_workflow = Path(sys.argv[2]).read_text(encoding="utf-8")

vet = job_block(vet_workflow, "vet")
windows = job_block(test_workflow, "windows")
fuzz = job_block(test_workflow, "fuzz")
merge_blocker = job_block(test_workflow, "merge_blocker")
check_mergeability_strict = job_block(test_workflow, "check_mergeability_strict")
check_mergeability = job_block(test_workflow, "check_mergeability")

failures: list[str] = []

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
