#!/usr/bin/env bash
set -u

REPOSITORY=""
PR_NUMBER=""
CONTROL_BRANCH="synology/main"
WORK_BRANCH=""
EXPECTED_BASE=""
EXPECTED_HEAD=""
REVIEW_EVIDENCE=""
REVIEW_EVIDENCE_SHA256=""
PR_WORKTREE=""
CONTROL_WORKTREE=""
SOURCE_WORKTREE=""
EVIDENCE_DIR=""
REMOTE_NAME="origin"
CONFIRM_INTEGRATE=0
DRY_RUN=0
RESUME=0
FIXTURE=""
REQUIRED_CHECKS=()

GIT="$(command -v git || true)"
GH="$(command -v gh || true)"
PYTHON="$(command -v python3 || true)"
SHA256SUM="$(command -v sha256sum || true)"

FAILURES=0
TEMP_ROOT=""
STATE_FILE=""

usage() {
  cat << 'USAGE'
Usage:
  bash scripts/governance/integrate-signed-pr.sh \
    --repository OWNER/REPO \
    --pr-number NUMBER \
    --control-branch BRANCH \
    --work-branch BRANCH \
    --expected-base SHA \
    --expected-head SHA \
    --review-evidence PATH \
    --review-evidence-sha256 SHA256 \
    --pr-worktree PATH \
    --control-worktree PATH \
    --source-worktree PATH \
    --evidence-dir PATH \
    --required-check NAME \
    [--required-check NAME ...] \
    [--remote NAME] \
    [--dry-run | --confirm-integrate | --resume]

Fixture mode for repository-owned tests:
  bash scripts/governance/integrate-signed-pr.sh \
    --fixture PATH

The live command never calls a GitHub merge, squash or rebase endpoint. It
updates the protected ref only with an exact expected-old force-with-lease.
USAGE
}

fail_check() {
  printf 'FAIL: %s\n' "$1" >&2
  FAILURES=$((FAILURES + 1))
}

pass_check() {
  printf 'PASS: %s\n' "$1"
}

notice_check() {
  printf 'NOTICE: %s\n' "$1"
}

cleanup() {
  if [ -n "$TEMP_ROOT" ] &&
    [ -d "$TEMP_ROOT" ]; then
    rm \
      -rf \
      -- \
      "$TEMP_ROOT"
  fi
}

trap cleanup EXIT

require_value() {
  option="$1"
  remaining="$2"

  if [ "$remaining" -lt 2 ]; then
    printf 'FAIL: %s requires a value.\n' "$option" >&2
    exit 2
  fi
}

while [ "$#" -gt 0 ]; do
  case "$1" in
    --repository)
      require_value "$1" "$#"
      REPOSITORY="$2"
      shift
      ;;
    --pr-number)
      require_value "$1" "$#"
      PR_NUMBER="$2"
      shift
      ;;
    --control-branch)
      require_value "$1" "$#"
      CONTROL_BRANCH="$2"
      shift
      ;;
    --work-branch)
      require_value "$1" "$#"
      WORK_BRANCH="$2"
      shift
      ;;
    --expected-base)
      require_value "$1" "$#"
      EXPECTED_BASE="$2"
      shift
      ;;
    --expected-head)
      require_value "$1" "$#"
      EXPECTED_HEAD="$2"
      shift
      ;;
    --review-evidence)
      require_value "$1" "$#"
      REVIEW_EVIDENCE="$2"
      shift
      ;;
    --review-evidence-sha256)
      require_value "$1" "$#"
      REVIEW_EVIDENCE_SHA256="$2"
      shift
      ;;
    --pr-worktree)
      require_value "$1" "$#"
      PR_WORKTREE="$2"
      shift
      ;;
    --control-worktree)
      require_value "$1" "$#"
      CONTROL_WORKTREE="$2"
      shift
      ;;
    --source-worktree)
      require_value "$1" "$#"
      SOURCE_WORKTREE="$2"
      shift
      ;;
    --evidence-dir)
      require_value "$1" "$#"
      EVIDENCE_DIR="$2"
      shift
      ;;
    --required-check)
      require_value "$1" "$#"
      REQUIRED_CHECKS+=("$2")
      shift
      ;;
    --remote)
      require_value "$1" "$#"
      REMOTE_NAME="$2"
      shift
      ;;
    --confirm-integrate)
      CONFIRM_INTEGRATE=1
      ;;
    --dry-run)
      DRY_RUN=1
      ;;
    --resume)
      RESUME=1
      ;;
    --fixture)
      require_value "$1" "$#"
      FIXTURE="$2"
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

validate_snapshot() {
  snapshot_path="$1"
  phase="$2"

  "$PYTHON" \
    - \
    "$snapshot_path" \
    "$phase" << 'PY'
from __future__ import annotations

import json
import sys
from pathlib import Path

snapshot_path, phase = sys.argv[1:]
data = json.loads(Path(snapshot_path).read_text(encoding="utf-8"))

required = data.get("required_checks") or []
checks = data.get("check_runs") or []
check_by_name = {}
for item in checks:
    name = item.get("name")
    if not name:
        continue
    current = check_by_name.get(name)
    key = (item.get("started_at") or "", item.get("id") or 0)
    current_key = (
        (current or {}).get("started_at") or "",
        (current or {}).get("id") or 0,
    )
    if current is None or key > current_key:
        check_by_name[name] = item

preconditions = [
    data.get("schema_version") == 1,
    data.get("repository") == data.get("review_evidence", {}).get("repository"),
    data.get("control_branch") == data.get("review_evidence", {}).get("control_branch"),
    data.get("expected_base") == data.get("review_evidence", {}).get("base_commit"),
    data.get("expected_head") == data.get("review_evidence", {}).get("reviewed_commit"),
    data.get("work_branch") == data.get("review_evidence", {}).get("implementation_branch"),
    sorted(data.get("changed_paths") or [])
    == sorted(data.get("review_evidence", {}).get("changed_paths") or []),
    data.get("patch_sha256")
    == data.get("review_evidence", {}).get("review_patch_sha256"),
    sorted(required)
    == sorted(data.get("review_evidence", {}).get("required_checks") or []),
    data.get("review_evidence", {}).get("authorises_integration") is True,
    data.get("review_evidence", {}).get("validation_failures") == 0,
    data.get("remote_control") == data.get("expected_base"),
    data.get("control_head") == data.get("expected_base"),
    data.get("control_clean") is True,
    data.get("source_clean") is True,
    data.get("pr_worktree_clean") is True,
    data.get("pr_branch") == data.get("work_branch"),
    data.get("pr_head") == data.get("expected_head"),
    data.get("pr_parent") == data.get("expected_base"),
    data.get("head_signature") == "G",
    data.get("github_head_verified") is True,
    data.get("github_head_verification_reason") == "valid",
    data.get("matching_signoff_count") == 1,
    data.get("pull_request", {}).get("number") == data.get("pr_number"),
    data.get("pull_request", {}).get("state") == "open",
    data.get("pull_request", {}).get("draft") is False,
    data.get("pull_request", {}).get("merged") is False,
    data.get("pull_request", {}).get("base_ref") == data.get("control_branch"),
    data.get("pull_request", {}).get("base_sha") == data.get("expected_base"),
    data.get("pull_request", {}).get("head_ref") == data.get("work_branch"),
    data.get("pull_request", {}).get("head_sha") == data.get("expected_head"),
    data.get("pull_request", {}).get("commits") == 1,
    data.get("pull_request", {}).get("changed_files")
    == len(data.get("changed_paths") or []),
    data.get("issue_comment_count") == 0,
    data.get("review_comment_count") == 0,
    data.get("changes_requested_count") == 0,
    data.get("unresolved_thread_count") == 0,
    data.get("required_signatures_rule") is True,
    data.get("pull_request_rule") is True,
    data.get("non_fast_forward_rule") is True,
    data.get("matching_always_bypass") is True,
    all(
        name in check_by_name
        and check_by_name[name].get("status") == "completed"
        and check_by_name[name].get("conclusion") == "success"
        for name in required
    ),
]

if phase == "fixture":
    failed = [str(index + 1) for index, value in enumerate(preconditions) if not value]
    if failed:
        raise SystemExit("fixture precondition failure: " + ", ".join(failed))
    print("PASS: fixture satisfies the exact pre-integration contract.")
    raise SystemExit(0)

if phase == "pre":
    failed = [str(index + 1) for index, value in enumerate(preconditions) if not value]
    if failed:
        raise SystemExit("pre-integration contract failure: " + ", ".join(failed))
    print("PASS: exact signed pull-request integration contract is satisfied.")
    raise SystemExit(0)

if phase != "post":
    raise SystemExit(f"unsupported snapshot phase: {phase}")

new_check = data.get("new_push_check") or {}
terminal = data.get("pull_request_terminal") or {}
postconditions = [
    data.get("remote_control") == data.get("expected_head"),
    data.get("github_head_verified") is True,
    new_check.get("name") == "repository-governance",
    new_check.get("status") == "completed",
    new_check.get("conclusion") == "success",
    new_check.get("is_new") is True,
    terminal.get("mode") in {"github-merged", "comment-close"},
    terminal.get("state") == "closed",
]
if terminal.get("mode") == "github-merged":
    postconditions.extend(
        [
            terminal.get("merged") is True,
            terminal.get("merge_commit_sha") == data.get("expected_head"),
        ]
    )
else:
    postconditions.extend(
        [
            terminal.get("merged") is False,
            terminal.get("fallback_comment_id") is not None,
        ]
    )

failed = [str(index + 1) for index, value in enumerate(postconditions) if not value]
if failed:
    raise SystemExit("post-integration contract failure: " + ", ".join(failed))
print("PASS: protected ref, new push check and PR terminal state are exact.")
PY
}

if [ -n "$FIXTURE" ]; then
  if [ ! -s "$FIXTURE" ]; then
    printf 'FAIL: fixture is unavailable: %s\n' "$FIXTURE" >&2
    exit 1
  fi

  if [ -z "$PYTHON" ]; then
    echo "FAIL: python3 is unavailable." >&2
    exit 1
  fi

  validate_snapshot "$FIXTURE" fixture
  exit $?
fi

mode_count=$((CONFIRM_INTEGRATE + DRY_RUN + RESUME))
if [ "$mode_count" -ne 1 ]; then
  echo "FAIL: select exactly one of --dry-run, --confirm-integrate or --resume." >&2
  exit 2
fi

for value_name in \
  REPOSITORY \
  PR_NUMBER \
  CONTROL_BRANCH \
  WORK_BRANCH \
  EXPECTED_BASE \
  EXPECTED_HEAD \
  REVIEW_EVIDENCE \
  REVIEW_EVIDENCE_SHA256 \
  PR_WORKTREE \
  CONTROL_WORKTREE \
  SOURCE_WORKTREE \
  EVIDENCE_DIR; do
  eval "value=\${${value_name}}"
  if [ -z "$value" ]; then
    fail_check "required value is absent: ${value_name}"
  fi
done

if [ "${#REQUIRED_CHECKS[@]}" -eq 0 ]; then
  fail_check "at least one --required-check is required"
fi

for command_path in \
  "$GIT" \
  "$GH" \
  "$PYTHON" \
  "$SHA256SUM"; do
  if [ -z "$command_path" ]; then
    fail_check "required command is unavailable"
  fi
done

for worktree in \
  "$PR_WORKTREE" \
  "$CONTROL_WORKTREE" \
  "$SOURCE_WORKTREE"; do
  if [ ! -d "$worktree/.git" ] &&
    [ ! -f "$worktree/.git" ]; then
    fail_check "required worktree is unavailable: ${worktree}"
  fi
done

if [ ! -s "$REVIEW_EVIDENCE" ]; then
  fail_check "review evidence is unavailable: ${REVIEW_EVIDENCE}"
fi

if [ "$FAILURES" -ne 0 ]; then
  echo "STOP: signed integration preflight failed."
  exit 1
fi

if ! "$GH" auth status > /dev/null 2>&1; then
  echo "FAIL: GitHub CLI authentication is unavailable." >&2
  exit 1
fi

mkdir \
  -p \
  "$EVIDENCE_DIR"

safe_head="${EXPECTED_HEAD//[^0-9a-fA-F]/_}"
STATE_FILE="${EVIDENCE_DIR}/integrate-signed-pr-${PR_NUMBER}-${safe_head}.state.json"

if [ -e "$STATE_FILE" ] &&
  [ "$RESUME" -ne 1 ]; then
  printf 'STOP: integration state already exists; use --resume after inspection: %s\n' "$STATE_FILE" >&2
  exit 1
fi

TEMP_ROOT="$(mktemp -d "${TMPDIR:-/tmp}/integrate-signed-pr.XXXXXX")"
PRE_SNAPSHOT="${TEMP_ROOT}/pre-snapshot.json"
POST_SNAPSHOT="${TEMP_ROOT}/post-snapshot.json"
PRE_CHECK_IDS="${TEMP_ROOT}/pre-check-ids.json"
PR_JSON="${TEMP_ROOT}/pr.json"
COMMIT_JSON="${TEMP_ROOT}/commit.json"
CHECKS_JSON="${TEMP_ROOT}/checks.json"

capture_pre_snapshot() {
  "$PYTHON" \
    - \
    "$GIT" \
    "$GH" \
    "$SHA256SUM" \
    "$REPOSITORY" \
    "$PR_NUMBER" \
    "$CONTROL_BRANCH" \
    "$WORK_BRANCH" \
    "$EXPECTED_BASE" \
    "$EXPECTED_HEAD" \
    "$REVIEW_EVIDENCE" \
    "$REVIEW_EVIDENCE_SHA256" \
    "$PR_WORKTREE" \
    "$CONTROL_WORKTREE" \
    "$SOURCE_WORKTREE" \
    "$REMOTE_NAME" \
    "$PRE_SNAPSHOT" \
    "$PRE_CHECK_IDS" \
    "${REQUIRED_CHECKS[@]}" << 'PY'
from __future__ import annotations

import fnmatch
import hashlib
import json
import subprocess
import sys
from pathlib import Path

(
    git,
    gh,
    sha256sum,
    repository,
    pr_number,
    control_branch,
    work_branch,
    expected_base,
    expected_head,
    review_evidence_path,
    review_evidence_sha,
    pr_worktree,
    control_worktree,
    source_worktree,
    remote_name,
    output_path,
    check_ids_path,
    *required_checks,
) = sys.argv[1:]
pr_number_int = int(pr_number)


def run(command: list[str], *, check: bool = True) -> str:
    process = subprocess.run(command, check=False, capture_output=True, text=True)
    if check and process.returncode != 0:
        raise SystemExit(
            f"command failed ({process.returncode}): {' '.join(command)}: {process.stderr.strip()}"
        )
    return process.stdout


def api(path: str, *, method: str | None = None, fields: list[str] | None = None):
    command = [gh, "api"]
    if method:
        command.extend(["--method", method])
    command.append(path)
    for field in fields or []:
        command.extend(["-f", field])
    return json.loads(run(command))


def git_value(worktree: str, *args: str) -> str:
    return run([git, "-C", worktree, *args]).strip()

review_path = Path(review_evidence_path)
observed_review_sha = hashlib.sha256(review_path.read_bytes()).hexdigest()
if observed_review_sha != review_evidence_sha:
    raise SystemExit("review evidence checksum differs")
review = json.loads(review_path.read_text(encoding="utf-8"))
changed_paths = sorted(review.get("changed_paths") or [])
if not changed_paths:
    raise SystemExit("review evidence changed path allowlist is empty")

remote_line = run(
    [
        git,
        "-C",
        pr_worktree,
        "ls-remote",
        "--exit-code",
        "--heads",
        remote_name,
        f"refs/heads/{control_branch}",
    ]
).strip()
remote_control = remote_line.split()[0]

pr_head = git_value(pr_worktree, "rev-parse", "HEAD")
pr_parent = git_value(pr_worktree, "rev-parse", "HEAD^")
pr_branch = git_value(pr_worktree, "branch", "--show-current")
head_signature = git_value(pr_worktree, "show", "-s", "--format=%G?", "HEAD")
author = git_value(pr_worktree, "show", "-s", "--format=%an <%ae>", "HEAD")
message = git_value(pr_worktree, "show", "-s", "--format=%B", "HEAD")
signoff = f"Signed-off-by: {author}"
matching_signoff_count = sum(1 for line in message.splitlines() if line == signoff)
local_paths = sorted(
    line
    for line in git_value(
        pr_worktree,
        "diff-tree",
        "--no-commit-id",
        "--name-only",
        "-r",
        "HEAD",
    ).splitlines()
    if line
)
if local_paths != changed_paths:
    raise SystemExit("local changed paths differ from review evidence")
patch = run(
    [
        git,
        "-C",
        pr_worktree,
        "diff",
        "--binary",
        "--full-index",
        expected_base,
        expected_head,
        "--",
        *changed_paths,
    ]
).encode()
patch_sha = hashlib.sha256(patch).hexdigest()

pr = api(f"repos/{repository}/pulls/{pr_number}")
commit = api(f"repos/{repository}/commits/{expected_head}")
verification = ((commit.get("commit") or {}).get("verification") or {})
issue_comments = api(f"repos/{repository}/issues/{pr_number}/comments?per_page=100")
review_comments = api(f"repos/{repository}/pulls/{pr_number}/comments?per_page=100")
reviews = api(f"repos/{repository}/pulls/{pr_number}/reviews?per_page=100")
check_data = api(f"repos/{repository}/commits/{expected_head}/check-runs?per_page=100")
check_runs = check_data.get("check_runs") or []
Path(check_ids_path).write_text(
    json.dumps(sorted(item.get("id") for item in check_runs if item.get("id") is not None))
    + "\n",
    encoding="utf-8",
)

owner, name = repository.split("/", 1)
graphql = run(
    [
        gh,
        "api",
        "graphql",
        "-f",
        "query=query($owner:String!,$name:String!,$number:Int!){repository(owner:$owner,name:$name){pullRequest(number:$number){reviewThreads(first:100){nodes{isResolved}}}}}",
        "-F",
        f"owner={owner}",
        "-F",
        f"name={name}",
        "-F",
        f"number={pr_number}",
    ]
)
threads = (
    json.loads(graphql)
    .get("data", {})
    .get("repository", {})
    .get("pullRequest", {})
    .get("reviewThreads", {})
    .get("nodes", [])
)
unresolved_thread_count = sum(1 for item in threads if item.get("isResolved") is not True)

user = api("user")
rulesets = api(f"repos/{repository}/rulesets?includes_parents=true")
details = [api(f"repos/{repository}/rulesets/{item['id']}") for item in rulesets]
ref = f"refs/heads/{control_branch}"
applicable = []
for ruleset in details:
    if ruleset.get("target") != "branch" or ruleset.get("enforcement") != "active":
        continue
    ref_name = ((ruleset.get("conditions") or {}).get("ref_name") or {})
    includes = ref_name.get("include") or ["~ALL"]
    excludes = ref_name.get("exclude") or []

    def matches(pattern: str) -> bool:
        return pattern in {"~ALL", "~DEFAULT_BRANCH"} or fnmatch.fnmatch(
            ref, pattern
        ) or fnmatch.fnmatch(control_branch, pattern)

    if not any(matches(pattern) for pattern in includes):
        continue
    if any(matches(pattern) for pattern in excludes):
        continue
    applicable.append(ruleset)

rule_types = {
    rule.get("type")
    for ruleset in applicable
    for rule in ruleset.get("rules") or []
    if rule.get("type")
}
matching_bypass = any(
    actor.get("actor_type") == "User"
    and actor.get("actor_id") == user.get("id")
    and actor.get("bypass_mode") == "always"
    for ruleset in applicable
    for actor in ruleset.get("bypass_actors") or []
)

snapshot = {
    "schema_version": 1,
    "repository": repository,
    "pr_number": pr_number_int,
    "control_branch": control_branch,
    "work_branch": work_branch,
    "expected_base": expected_base,
    "expected_head": expected_head,
    "review_evidence": review,
    "required_checks": required_checks,
    "changed_paths": local_paths,
    "patch_sha256": patch_sha,
    "remote_control": remote_control,
    "control_head": git_value(control_worktree, "rev-parse", "HEAD"),
    "control_clean": not bool(
        git_value(control_worktree, "status", "--short", "--untracked-files=all")
    ),
    "source_clean": not bool(
        git_value(source_worktree, "status", "--short", "--untracked-files=all")
    ),
    "pr_worktree_clean": not bool(
        git_value(pr_worktree, "status", "--short", "--untracked-files=all")
    ),
    "pr_branch": pr_branch,
    "pr_head": pr_head,
    "pr_parent": pr_parent,
    "head_signature": head_signature,
    "github_head_verified": verification.get("verified"),
    "github_head_verification_reason": verification.get("reason"),
    "matching_signoff_count": matching_signoff_count,
    "pull_request": {
        "number": pr.get("number"),
        "state": pr.get("state"),
        "draft": pr.get("draft"),
        "merged": pr.get("merged"),
        "base_ref": (pr.get("base") or {}).get("ref"),
        "base_sha": (pr.get("base") or {}).get("sha"),
        "head_ref": (pr.get("head") or {}).get("ref"),
        "head_sha": (pr.get("head") or {}).get("sha"),
        "commits": pr.get("commits"),
        "changed_files": pr.get("changed_files"),
    },
    "issue_comment_count": len(issue_comments),
    "review_comment_count": len(review_comments),
    "changes_requested_count": sum(
        1 for item in reviews if item.get("state") == "CHANGES_REQUESTED"
    ),
    "unresolved_thread_count": unresolved_thread_count,
    "required_signatures_rule": "required_signatures" in rule_types,
    "pull_request_rule": "pull_request" in rule_types,
    "non_fast_forward_rule": "non_fast_forward" in rule_types,
    "matching_always_bypass": matching_bypass,
    "check_runs": [
        {
            "id": item.get("id"),
            "name": item.get("name"),
            "status": item.get("status"),
            "conclusion": item.get("conclusion"),
            "started_at": item.get("started_at"),
            "completed_at": item.get("completed_at"),
            "url": item.get("html_url"),
        }
        for item in check_runs
    ],
}
Path(output_path).write_text(
    json.dumps(snapshot, indent=2, sort_keys=True) + "\n", encoding="utf-8"
)
PY
}

if [ "$RESUME" -ne 1 ]; then
  printf '=== Validate exact signed pull-request state ===\n'
  capture_pre_snapshot
  validate_snapshot "$PRE_SNAPSHOT" pre || exit 1

  if [ "$DRY_RUN" -eq 1 ]; then
    TIMESTAMP="$(date -u '+%Y%m%dT%H%M%SZ')"
    PLAN="${EVIDENCE_DIR}/integrate-signed-pr-plan-${PR_NUMBER}-${TIMESTAMP}.json"
    cp "$PRE_SNAPSHOT" "$PLAN"
    pass_check "dry-run integration plan is exact."
    printf 'Plan evidence: %s\n' "$PLAN"
    notice_check "no protected ref, PR, worktree or branch was changed."
    exit 0
  fi

  printf '\n=== Update protected ref with exact force-with-lease ===\n'
  "$GIT" \
    -C "$PR_WORKTREE" \
    push \
    --force-with-lease="refs/heads/${CONTROL_BRANCH}:${EXPECTED_BASE}" \
    "$REMOTE_NAME" \
    "${EXPECTED_HEAD}:refs/heads/${CONTROL_BRANCH}"
  PUSH_RC=$?
  printf 'Protected-ref update status: %s\n' "$PUSH_RC"

  if [ "$PUSH_RC" -ne 0 ]; then
    echo "STOP: exact protected-ref update failed; no resume state was created." >&2
    exit "$PUSH_RC"
  fi

  "$PYTHON" \
    - \
    "$STATE_FILE" \
    "$REPOSITORY" \
    "$PR_NUMBER" \
    "$CONTROL_BRANCH" \
    "$WORK_BRANCH" \
    "$EXPECTED_BASE" \
    "$EXPECTED_HEAD" \
    "$REVIEW_EVIDENCE" \
    "$REVIEW_EVIDENCE_SHA256" \
    "$PRE_CHECK_IDS" << 'PY'
import json
import sys
from datetime import datetime, timezone
from pathlib import Path

(
    state_path,
    repository,
    pr_number,
    control_branch,
    work_branch,
    expected_base,
    expected_head,
    evidence_path,
    evidence_sha,
    check_ids_path,
) = sys.argv[1:]
state = {
    "schema_version": 1,
    "updated_at_utc": datetime.now(timezone.utc).isoformat(),
    "phase": "remote-integrated",
    "repository": repository,
    "pr_number": int(pr_number),
    "control_branch": control_branch,
    "work_branch": work_branch,
    "expected_base": expected_base,
    "expected_head": expected_head,
    "review_evidence": {"path": evidence_path, "sha256": evidence_sha},
    "pre_existing_check_ids": json.loads(
        Path(check_ids_path).read_text(encoding="utf-8")
    ),
}
Path(state_path).write_text(
    json.dumps(state, indent=2, sort_keys=True) + "\n", encoding="utf-8"
)
PY
  pass_check "protected ref now points to the exact reviewed signed commit."
  notice_check "resume state was written before post-integration operations."
else
  if [ ! -s "$STATE_FILE" ]; then
    printf 'FAIL: resume state is unavailable: %s\n' "$STATE_FILE" >&2
    exit 1
  fi

  "$PYTHON" \
    - \
    "$STATE_FILE" \
    "$REPOSITORY" \
    "$PR_NUMBER" \
    "$CONTROL_BRANCH" \
    "$WORK_BRANCH" \
    "$EXPECTED_BASE" \
    "$EXPECTED_HEAD" \
    "$REVIEW_EVIDENCE" \
    "$REVIEW_EVIDENCE_SHA256" << 'PY'
import json
import sys
from pathlib import Path

(
    state_path,
    repository,
    pr_number,
    control_branch,
    work_branch,
    expected_base,
    expected_head,
    evidence_path,
    evidence_sha,
) = sys.argv[1:]
data = json.loads(Path(state_path).read_text(encoding="utf-8"))
checks = [
    data.get("schema_version") == 1,
    data.get("phase") in {"remote-integrated", "push-check-passed", "pr-terminal"},
    data.get("repository") == repository,
    data.get("pr_number") == int(pr_number),
    data.get("control_branch") == control_branch,
    data.get("work_branch") == work_branch,
    data.get("expected_base") == expected_base,
    data.get("expected_head") == expected_head,
    data.get("review_evidence", {}).get("path") == evidence_path,
    data.get("review_evidence", {}).get("sha256") == evidence_sha,
]
if not all(checks):
    raise SystemExit("resume state contract differs")
print("PASS: resume state contract is exact.")
PY

  OBSERVED_REVIEW_SHA="$($SHA256SUM "$REVIEW_EVIDENCE" | awk '{ print $1 }')"
  RESUME_REMOTE_LINE="$($GIT -C "$CONTROL_WORKTREE" ls-remote --exit-code --heads "$REMOTE_NAME" "refs/heads/${CONTROL_BRANCH}" 2> /dev/null)"
  RESUME_REMOTE_RC=$?
  RESUME_REMOTE_HEAD="$(printf '%s\n' "$RESUME_REMOTE_LINE" | awk 'NR == 1 { print $1 }')"
  RESUME_PR_HEAD="$($GIT -C "$PR_WORKTREE" rev-parse HEAD)"
  RESUME_PR_SIGNATURE="$($GIT -C "$PR_WORKTREE" show -s --format='%G?' HEAD)"
  RESUME_PR_STATUS="$($GIT -C "$PR_WORKTREE" status --short --untracked-files=all)"
  RESUME_CONTROL_HEAD="$($GIT -C "$CONTROL_WORKTREE" rev-parse HEAD)"
  RESUME_CONTROL_STATUS="$($GIT -C "$CONTROL_WORKTREE" status --short --untracked-files=all)"
  RESUME_SOURCE_STATUS="$($GIT -C "$SOURCE_WORKTREE" status --short --untracked-files=all)"

  if [ "$OBSERVED_REVIEW_SHA" != "$REVIEW_EVIDENCE_SHA256" ] ||
    [ "$RESUME_REMOTE_RC" -ne 0 ] ||
    [ "$RESUME_REMOTE_HEAD" != "$EXPECTED_HEAD" ] ||
    [ "$RESUME_PR_HEAD" != "$EXPECTED_HEAD" ] ||
    [ "$RESUME_PR_SIGNATURE" != "G" ] ||
    [ -n "$RESUME_PR_STATUS" ] ||
    { [ "$RESUME_CONTROL_HEAD" != "$EXPECTED_BASE" ] &&
      [ "$RESUME_CONTROL_HEAD" != "$EXPECTED_HEAD" ]; } ||
    [ -n "$RESUME_CONTROL_STATUS" ] ||
    [ -n "$RESUME_SOURCE_STATUS" ]; then
    echo "STOP: resume repository or evidence state differs." >&2
    exit 1
  fi

  pass_check "resume protected head, signed worktree and evidence checksum are exact."
fi

printf '\n=== Require a new protected-branch push check ===\n'
PRE_IDS_FILE="${TEMP_ROOT}/resume-pre-check-ids.json"
"$PYTHON" - "$STATE_FILE" "$PRE_IDS_FILE" << 'PY'
import json
import sys
from pathlib import Path

data = json.loads(Path(sys.argv[1]).read_text(encoding="utf-8"))
Path(sys.argv[2]).write_text(
    json.dumps(data.get("pre_existing_check_ids") or []) + "\n", encoding="utf-8"
)
PY

NEW_CHECK_JSON="${TEMP_ROOT}/new-check.json"
NEW_CHECK_PASSED=0
for attempt in $(seq 1 90); do
  "$GH" api "repos/${REPOSITORY}/commits/${EXPECTED_HEAD}/check-runs?per_page=100" > "$CHECKS_JSON"
  CHECK_RESULT="$(
    $PYTHON - "$CHECKS_JSON" "$PRE_IDS_FILE" "$NEW_CHECK_JSON" << 'PY'
import json
import sys
from pathlib import Path

data = json.loads(Path(sys.argv[1]).read_text(encoding="utf-8"))
pre_ids = set(json.loads(Path(sys.argv[2]).read_text(encoding="utf-8")))
runs = [
    item
    for item in data.get("check_runs") or []
    if item.get("name") == "repository-governance" and item.get("id") not in pre_ids
]
if not runs:
    print("pending:new-check")
    raise SystemExit(0)
run = sorted(
    runs, key=lambda item: (item.get("started_at") or "", item.get("id") or 0)
)[-1]
summary = {
    "id": run.get("id"),
    "name": run.get("name"),
    "status": run.get("status"),
    "conclusion": run.get("conclusion"),
    "started_at": run.get("started_at"),
    "completed_at": run.get("completed_at"),
    "url": run.get("html_url"),
    "is_new": True,
}
Path(sys.argv[3]).write_text(
    json.dumps(summary, indent=2, sort_keys=True) + "\n", encoding="utf-8"
)
if run.get("status") != "completed":
    print("pending:repository-governance")
elif run.get("conclusion") == "success":
    print("success")
else:
    print(f"failed:{run.get('conclusion')}")
PY
  )"
  printf 'Push-check poll %s: %s\n' "$attempt" "$CHECK_RESULT"
  case "$CHECK_RESULT" in
    success)
      NEW_CHECK_PASSED=1
      break
      ;;
    failed:*)
      echo "STOP: new protected-branch push check failed; preserve state and resume after repair." >&2
      exit 1
      ;;
  esac
  sleep 10
done

if [ "$NEW_CHECK_PASSED" -ne 1 ]; then
  echo "STOP: no new successful repository-governance push check completed; preserve state." >&2
  exit 1
fi
pass_check "new repository-governance push check succeeded."

"$PYTHON" - "$STATE_FILE" "$NEW_CHECK_JSON" << 'PY'
import json
import sys
from datetime import datetime, timezone
from pathlib import Path

state_path = Path(sys.argv[1])
data = json.loads(state_path.read_text(encoding="utf-8"))
data["phase"] = "push-check-passed"
data["updated_at_utc"] = datetime.now(timezone.utc).isoformat()
data["new_push_check"] = json.loads(Path(sys.argv[2]).read_text(encoding="utf-8"))
state_path.write_text(json.dumps(data, indent=2, sort_keys=True) + "\n", encoding="utf-8")
PY

printf '\n=== Record deterministic pull-request terminal state ===\n'
TERMINAL_JSON="${TEMP_ROOT}/terminal.json"
TERMINAL_READY=0

if "$PYTHON" - "$STATE_FILE" "$TERMINAL_JSON" << 'PY'; then
import json
import sys
from pathlib import Path

data = json.loads(Path(sys.argv[1]).read_text(encoding="utf-8"))
terminal = data.get("pull_request_terminal")
if data.get("phase") == "pr-terminal" and isinstance(terminal, dict):
    Path(sys.argv[2]).write_text(
        json.dumps(terminal, indent=2, sort_keys=True) + "\n", encoding="utf-8"
    )
    raise SystemExit(0)
raise SystemExit(1)
PY
  TERMINAL_READY=1
fi

if [ "$TERMINAL_READY" -ne 1 ]; then
  for attempt in $(seq 1 12); do
    "$GH" api "repos/${REPOSITORY}/pulls/${PR_NUMBER}" > "$PR_JSON"
    if "$PYTHON" - "$PR_JSON" "$EXPECTED_HEAD" "$TERMINAL_JSON" << 'PY'; then
import json
import sys
from pathlib import Path

pr = json.loads(Path(sys.argv[1]).read_text(encoding="utf-8"))
expected_head = sys.argv[2]
if pr.get("state") == "closed" and pr.get("merged") is True:
    if pr.get("merge_commit_sha") != expected_head:
        raise SystemExit("merged PR records an unexpected merge commit")
    result = {
        "mode": "github-merged",
        "state": "closed",
        "merged": True,
        "merge_commit_sha": pr.get("merge_commit_sha"),
        "fallback_comment_id": None,
    }
    Path(sys.argv[3]).write_text(
        json.dumps(result, indent=2, sort_keys=True) + "\n", encoding="utf-8"
    )
    raise SystemExit(0)
raise SystemExit(1)
PY
      TERMINAL_READY=1
      break
    fi
    sleep 5
  done
fi

if [ "$TERMINAL_READY" -ne 1 ]; then
  FALLBACK_BODY="Exact signed integration completed outside GitHub's merge endpoint. Protected branch ${CONTROL_BRANCH} advanced from ${EXPECTED_BASE} to reviewed signed commit ${EXPECTED_HEAD} under an exact force-with-lease. A new repository-governance push check succeeded. This pull request is being closed as the auditable terminal fallback."
  COMMENT_JSON="${TEMP_ROOT}/fallback-comment.json"
  "$GH" api \
    --method POST \
    "repos/${REPOSITORY}/issues/${PR_NUMBER}/comments" \
    -f "body=${FALLBACK_BODY}" > "$COMMENT_JSON"
  "$GH" api \
    --method PATCH \
    "repos/${REPOSITORY}/pulls/${PR_NUMBER}" \
    -f 'state=closed' > "$PR_JSON"
  "$PYTHON" \
    - \
    "$COMMENT_JSON" \
    "$PR_JSON" \
    "$TERMINAL_JSON" << 'PY'
import json
import sys
from pathlib import Path

comment = json.loads(Path(sys.argv[1]).read_text(encoding="utf-8"))
pr = json.loads(Path(sys.argv[2]).read_text(encoding="utf-8"))
checks = [
    comment.get("id") is not None,
    pr.get("state") == "closed",
    pr.get("merged") is False,
]
if not all(checks):
    raise SystemExit("comment-and-close fallback did not converge")
result = {
    "mode": "comment-close",
    "state": "closed",
    "merged": False,
    "merge_commit_sha": pr.get("merge_commit_sha"),
    "fallback_comment_id": comment.get("id"),
}
Path(sys.argv[3]).write_text(
    json.dumps(result, indent=2, sort_keys=True) + "\n", encoding="utf-8"
)
PY
fi

"$PYTHON" - "$STATE_FILE" "$TERMINAL_JSON" << 'PY'
import json
import sys
from datetime import datetime, timezone
from pathlib import Path

state_path = Path(sys.argv[1])
data = json.loads(state_path.read_text(encoding="utf-8"))
data["phase"] = "pr-terminal"
data["updated_at_utc"] = datetime.now(timezone.utc).isoformat()
data["pull_request_terminal"] = json.loads(
    Path(sys.argv[2]).read_text(encoding="utf-8")
)
state_path.write_text(json.dumps(data, indent=2, sort_keys=True) + "\n", encoding="utf-8")
PY
pass_check "pull-request terminal state is recorded."

printf '\n=== Validate post-integration remote state ===\n'
"$GIT" \
  -C "$CONTROL_WORKTREE" \
  fetch \
  --prune \
  "$REMOTE_NAME"
REMOTE_CONTROL="$($GIT -C "$CONTROL_WORKTREE" rev-parse "refs/remotes/${REMOTE_NAME}/${CONTROL_BRANCH}^{commit}")"
if [ "$REMOTE_CONTROL" != "$EXPECTED_HEAD" ]; then
  echo "STOP: protected branch differs after integration; preserve state." >&2
  exit 1
fi
"$GH" api "repos/${REPOSITORY}/commits/${EXPECTED_HEAD}" > "$COMMIT_JSON"
"$PYTHON" \
  - \
  "$POST_SNAPSHOT" \
  "$REPOSITORY" \
  "$PR_NUMBER" \
  "$CONTROL_BRANCH" \
  "$WORK_BRANCH" \
  "$EXPECTED_BASE" \
  "$EXPECTED_HEAD" \
  "$REMOTE_CONTROL" \
  "$COMMIT_JSON" \
  "$NEW_CHECK_JSON" \
  "$TERMINAL_JSON" << 'PY'
import json
import sys
from pathlib import Path

(
    output_path,
    repository,
    pr_number,
    control_branch,
    work_branch,
    expected_base,
    expected_head,
    remote_control,
    commit_path,
    check_path,
    terminal_path,
) = sys.argv[1:]
commit = json.loads(Path(commit_path).read_text(encoding="utf-8"))
verification = ((commit.get("commit") or {}).get("verification") or {})
result = {
    "schema_version": 1,
    "repository": repository,
    "pr_number": int(pr_number),
    "control_branch": control_branch,
    "work_branch": work_branch,
    "expected_base": expected_base,
    "expected_head": expected_head,
    "remote_control": remote_control,
    "github_head_verified": verification.get("verified"),
    "new_push_check": json.loads(Path(check_path).read_text(encoding="utf-8")),
    "pull_request_terminal": json.loads(
        Path(terminal_path).read_text(encoding="utf-8")
    ),
}
Path(output_path).write_text(
    json.dumps(result, indent=2, sort_keys=True) + "\n", encoding="utf-8"
)
PY
validate_snapshot "$POST_SNAPSHOT" post || exit 1

printf '\n=== Fast-forward persistent control and validate ===\n'
"$GIT" \
  -C "$CONTROL_WORKTREE" \
  merge \
  --ff-only \
  "refs/remotes/${REMOTE_NAME}/${CONTROL_BRANCH}"
if [ "$($GIT -C "$CONTROL_WORKTREE" rev-parse HEAD)" != "$EXPECTED_HEAD" ]; then
  echo "STOP: persistent control did not reach the reviewed head; preserve state." >&2
  exit 1
fi

bash \
  "$CONTROL_WORKTREE/scripts/validate-repository.sh" \
  --source-environment \
  "$SOURCE_WORKTREE" \
  --fast || exit $?

GIT_CONFIG_GLOBAL=/dev/null \
  GIT_CONFIG_SYSTEM=/dev/null \
  bash \
  "$CONTROL_WORKTREE/scripts/release/validate-release.sh" \
  --control-worktree \
  "$CONTROL_WORKTREE" \
  --source-worktree \
  "$SOURCE_WORKTREE" \
  --role \
  accepted \
  --fast \
  --round-trip || exit $?
pass_check "persistent control and accepted-release validation passed."

printf '\n=== Remove exact temporary branch and worktree state ===\n'
if [ "$($GIT -C "$PR_WORKTREE" rev-parse HEAD)" != "$EXPECTED_HEAD" ] ||
  [ -n "$($GIT -C "$PR_WORKTREE" status --short --untracked-files=all)" ]; then
  echo "STOP: PR worktree differs; cleanup was not performed." >&2
  exit 1
fi
"$GIT" \
  -C "$CONTROL_WORKTREE" \
  worktree \
  remove \
  "$PR_WORKTREE"
LOCAL_BRANCH_HEAD="$($GIT -C "$CONTROL_WORKTREE" rev-parse "refs/heads/${WORK_BRANCH}^{commit}" 2> /dev/null || true)"
if [ "$LOCAL_BRANCH_HEAD" != "$EXPECTED_HEAD" ]; then
  echo "STOP: local work branch differs; it was not deleted." >&2
  exit 1
fi
"$GIT" \
  -C "$CONTROL_WORKTREE" \
  branch \
  -D \
  "$WORK_BRANCH"
REMOTE_WORK="$($GIT -C "$CONTROL_WORKTREE" ls-remote --exit-code --heads "$REMOTE_NAME" "refs/heads/${WORK_BRANCH}" 2> /dev/null)"
REMOTE_WORK_RC=$?
if [ "$REMOTE_WORK_RC" -eq 0 ] &&
  [ -n "$REMOTE_WORK" ]; then
  REMOTE_WORK_SHA="$(printf '%s\n' "$REMOTE_WORK" | awk 'NR == 1 { print $1 }')"
  if [ "$REMOTE_WORK_SHA" != "$EXPECTED_HEAD" ]; then
    echo "STOP: remote work branch moved; it was not deleted." >&2
    exit 1
  fi
  "$GIT" \
    -C "$CONTROL_WORKTREE" \
    push \
    "$REMOTE_NAME" \
    --delete \
    "$WORK_BRANCH" || exit $?
elif [ "$REMOTE_WORK_RC" -ne 2 ]; then
  echo "STOP: remote work branch state could not be resolved." >&2
  exit 1
fi
pass_check "exact temporary worktree and branch state was removed."

printf '\n=== Generate permanent integration evidence ===\n'
TIMESTAMP="$(date -u '+%Y%m%dT%H%M%SZ')"
REPORT="${EVIDENCE_DIR}/signed-protected-integration-${PR_NUMBER}-${TIMESTAMP}.md"
EVIDENCE="${EVIDENCE_DIR}/signed-protected-integration-${PR_NUMBER}-${TIMESTAMP}.json"
"$PYTHON" \
  - \
  "$REPORT" \
  "$EVIDENCE" \
  "$STATE_FILE" \
  "$PRE_SNAPSHOT" \
  "$POST_SNAPSHOT" \
  "$REVIEW_EVIDENCE" \
  "$REVIEW_EVIDENCE_SHA256" << 'PY'
import json
import sys
from datetime import datetime, timezone
from pathlib import Path

(
    report_path,
    evidence_path,
    state_path,
    pre_path,
    post_path,
    review_path,
    review_sha,
) = sys.argv[1:]
pre = json.loads(Path(pre_path).read_text(encoding="utf-8"))
post = json.loads(Path(post_path).read_text(encoding="utf-8"))
state = json.loads(Path(state_path).read_text(encoding="utf-8"))
state["phase"] = "complete"
state["updated_at_utc"] = datetime.now(timezone.utc).isoformat()
state["final_evidence"] = str(evidence_path)
Path(state_path).write_text(
    json.dumps(state, indent=2, sort_keys=True) + "\n", encoding="utf-8"
)
result = {
    "schema_version": 1,
    "timestamp_utc": datetime.now(timezone.utc).isoformat(),
    "repository": pre["repository"],
    "control_branch": pre["control_branch"],
    "pull_request": {
        "number": pre["pr_number"],
        **post["pull_request_terminal"],
    },
    "previous_control_commit": pre["expected_base"],
    "integrated_signed_commit": pre["expected_head"],
    "review_evidence": {"path": review_path, "sha256": review_sha},
    "review_patch_sha256": pre["patch_sha256"],
    "changed_paths": pre["changed_paths"],
    "required_checks": pre["required_checks"],
    "new_push_check": post["new_push_check"],
    "force_with_lease": {
        "expected_old": pre["expected_base"],
        "replacement": pre["expected_head"],
        "succeeded": True,
    },
    "persistent_control_updated": True,
    "post_integration_validation": {
        "repository": "passed",
        "accepted_release_round_trip": "passed",
    },
    "cleanup": {
        "temporary_worktree_removed": True,
        "local_branch_removed": True,
        "remote_branch_absent": True,
    },
    "github_merge_endpoint_called": False,
    "package_built": False,
    "package_published": False,
    "release_created": False,
    "tag_created": False,
    "repository_settings_changed": False,
    "dsm_mutated": False,
    "validation_failures": 0,
}
Path(evidence_path).write_text(
    json.dumps(result, indent=2, sort_keys=True) + "\n", encoding="utf-8"
)
lines = [
    "# Signed protected integration",
    "",
    f"- pull request: #{pre['pr_number']};",
    f"- previous protected head: `{pre['expected_base']}`;",
    f"- integrated reviewed signed commit: `{pre['expected_head']}`;",
    f"- reviewed patch SHA-256: `{pre['patch_sha256']}`;",
    f"- terminal mode: `{post['pull_request_terminal']['mode']}`;",
    f"- new push check ID: `{post['new_push_check']['id']}`.",
    "",
    "The protected ref was updated with an exact expected-old force-with-lease.",
    "No GitHub merge, squash or rebase endpoint was called. Repository and",
    "accepted-release validation passed before exact temporary-state cleanup.",
    "",
    f"Machine-readable evidence: `{evidence_path}`",
    "",
]
Path(report_path).write_text("\n".join(lines), encoding="utf-8")
PY

REPORT_SHA="$($SHA256SUM "$REPORT" | awk '{ print $1 }')"
EVIDENCE_SHA="$($SHA256SUM "$EVIDENCE" | awk '{ print $1 }')"
printf 'Markdown report:  %s\n' "$REPORT"
printf 'JSON evidence:    %s\n' "$EVIDENCE"
printf 'Report SHA-256:  %s\n' "$REPORT_SHA"
printf 'Evidence SHA-256:%s\n' " $EVIDENCE_SHA"
pass_check "exact reviewed signed commit integration is complete."
notice_check "no package, release, tag, repository-setting or DSM mutation occurred."
