#!/usr/bin/env bash
set -u

REPO_ROOT="$(
  cd \
    "$(dirname "${BASH_SOURCE[0]}")/../.." &&
    pwd
)"

SOURCE_ENV_ROOT=""

usage() {
  cat << 'USAGE'
Usage:
  bash tests/governance/automation-contract.sh \
    --source-environment /path/to/accepted-source-worktree
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

if [ -z "$SOURCE_ENV_ROOT" ]; then
  echo "FAIL: --source-environment is required." >&2
  exit 2
fi

if [ ! -d "$SOURCE_ENV_ROOT/.git" ] &&
  [ ! -f "$SOURCE_ENV_ROOT/.git" ]; then
  printf 'FAIL: source environment is not a Git worktree: %s\n' \
    "$SOURCE_ENV_ROOT" >&2
  exit 1
fi

python3 \
  - \
  "$REPO_ROOT" \
  "$SOURCE_ENV_ROOT" << 'PY'
from __future__ import annotations

import re
import sys
from pathlib import Path


CONTROL_ROOT = Path(sys.argv[1]).resolve()
SOURCE_ROOT = Path(sys.argv[2]).resolve()
GUIDE = CONTROL_ROOT / "docs/governance/automation.md"
EXPECTED_ROWS = 9
HEADER = (
    "Workflow",
    "File",
    "Root",
    "Ownership",
    "Triggers",
    "Status",
    "Ruleset",
    "Proves",
    "Does not prove",
)


def fail(message: str) -> None:
    print(f"FAIL: {message}", file=sys.stderr)
    raise SystemExit(1)


def unquote(value: str) -> str:
    value = value.strip()
    if len(value) >= 2 and value[0] == value[-1] and value[0] in {'"', "'"}:
        return value[1:-1]
    return value


def parse_table() -> list[dict[str, str]]:
    if not GUIDE.is_file():
        fail(f"automation catalogue is missing: {GUIDE}")

    rows = []
    in_table = False

    for line in GUIDE.read_text(encoding="utf-8").splitlines():
        if not line.startswith("|"):
            if in_table and rows:
                break
            continue

        cells = tuple(cell.strip() for cell in line.strip().strip("|").split("|"))

        if cells == HEADER:
            in_table = True
            continue

        if not in_table or all(re.fullmatch(r"-+", cell) for cell in cells):
            continue

        if len(cells) != len(HEADER):
            fail(f"catalogue row has {len(cells)} columns, expected {len(HEADER)}")

        rows.append(dict(zip(HEADER, cells, strict=True)))

    if len(rows) != EXPECTED_ROWS:
        fail(f"catalogue has {len(rows)} workflow rows, expected {EXPECTED_ROWS}")

    return rows


def parse_workflow(path: Path) -> tuple[str, set[str], set[str]]:
    if not path.is_file():
        fail(f"documented workflow is missing: {path}")

    lines = path.read_text(encoding="utf-8").splitlines()
    display_name = ""
    triggers: set[str] = set()
    statuses: set[str] = set()
    in_on = False
    in_jobs = False
    current_job = ""

    for line in lines:
        if not display_name:
            match = re.match(r"^name:\s*(.+?)\s*$", line)
            if match:
                display_name = unquote(match.group(1))

        if re.fullmatch(r"on:\s*", line):
            in_on = True
            in_jobs = False
            continue

        if re.fullmatch(r"jobs:\s*", line):
            in_jobs = True
            in_on = False
            current_job = ""
            continue

        if line and not line.startswith((" ", "\t", "#")):
            in_on = False
            if not line.startswith("jobs:"):
                in_jobs = False

        if in_on:
            match = re.match(r"^  ([A-Za-z_][A-Za-z0-9_-]*):", line)
            if match:
                triggers.add(match.group(1))

        if in_jobs:
            job_match = re.match(r"^  ([A-Za-z_][A-Za-z0-9_-]*):\s*$", line)
            if job_match:
                current_job = job_match.group(1)
                statuses.add(current_job)
                continue

            name_match = re.match(r"^    name:\s*(.+?)\s*$", line)
            if current_job and name_match:
                statuses.discard(current_job)
                statuses.add(unquote(name_match.group(1)))

    if not display_name:
        fail(f"workflow has no top-level display name: {path}")
    if not triggers:
        fail(f"workflow has no parsed triggers: {path}")
    if not statuses:
        fail(f"workflow has no parsed jobs: {path}")

    return display_name, triggers, statuses


rows = parse_table()
seen_names: set[str] = set()
seen_paths: set[tuple[str, str]] = set()

for row in rows:
    name = row["Workflow"].strip("`")
    relative = row["File"].strip("`")
    root_name = row["Root"].strip("`")
    documented_triggers = {
        item.strip(" `") for item in row["Triggers"].split(",") if item.strip()
    }
    documented_status = row["Status"].strip("`")

    if root_name == "control":
        root = CONTROL_ROOT
    elif root_name == "accepted-source":
        root = SOURCE_ROOT
    else:
        fail(f"unsupported catalogue root for {name}: {root_name}")

    key = (root_name, relative)
    if name in seen_names:
        fail(f"duplicate workflow display name: {name}")
    if key in seen_paths:
        fail(f"duplicate workflow path: {root_name}:{relative}")

    seen_names.add(name)
    seen_paths.add(key)

    actual_name, actual_triggers, actual_statuses = parse_workflow(root / relative)
    if name != actual_name:
        fail(f"display name mismatch for {relative}: {name!r} != {actual_name!r}")
    if documented_triggers != actual_triggers:
        fail(
            f"trigger mismatch for {relative}: "
            f"{sorted(documented_triggers)} != {sorted(actual_triggers)}"
        )

    if documented_status == "multiple jobs":
        if len(actual_statuses) < 2:
            fail(f"{relative} documents multiple jobs but exposes {sorted(actual_statuses)}")
    elif documented_status not in actual_statuses:
        fail(
            f"status mismatch for {relative}: {documented_status!r} is not in "
            f"{sorted(actual_statuses)}"
        )

print(f"PASS: automation catalogue matches {EXPECTED_ROWS} pinned workflow definitions.")
PY
