#!/usr/bin/env bash
set -u

REPO_ROOT="$(
  cd \
    "$(dirname "${BASH_SOURCE[0]}")/../.." &&
    pwd
)"
ENTRYPOINT="${REPO_ROOT}/scripts/governance/integrate-signed-pr.sh"
PYTHON="$(command -v python3 || true)"
TEMP_ROOT=""
FAILURES=0

fail_check() {
  printf 'FAIL: %s\n' "$1"
  FAILURES=$((FAILURES + 1))
}

pass_check() {
  printf 'PASS: %s\n' "$1"
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

if [ ! -x "$ENTRYPOINT" ]; then
  echo "FAIL: signed integration entrypoint is unavailable." >&2
  exit 1
fi

if [ -z "$PYTHON" ]; then
  echo "FAIL: python3 is unavailable." >&2
  exit 1
fi

TEMP_ROOT="$(mktemp -d "${TMPDIR:-/tmp}/test-integrate-signed-pr.XXXXXX")"
VALID_FIXTURE="${TEMP_ROOT}/valid.json"
MOVED_BASE_FIXTURE="${TEMP_ROOT}/moved-base.json"
UNSIGNED_FIXTURE="${TEMP_ROOT}/unsigned.json"
FAILED_CHECK_FIXTURE="${TEMP_ROOT}/failed-check.json"
UNRESOLVED_FIXTURE="${TEMP_ROOT}/unresolved.json"

"$PYTHON" \
  - \
  "$VALID_FIXTURE" \
  "$MOVED_BASE_FIXTURE" \
  "$UNSIGNED_FIXTURE" \
  "$FAILED_CHECK_FIXTURE" \
  "$UNRESOLVED_FIXTURE" << 'PY'
from __future__ import annotations

import copy
import json
import sys
from pathlib import Path

valid_path, moved_path, unsigned_path, failed_path, unresolved_path = sys.argv[1:]
base = "1" * 40
head = "2" * 40
paths = [
    "docs/governance/repository-governance.md",
    "scripts/governance/integrate-signed-pr.sh",
]
required = ["repository-governance", "release-operations"]
valid = {
    "schema_version": 1,
    "repository": "example/repository",
    "pr_number": 17,
    "control_branch": "synology/main",
    "work_branch": "governance/signed-protected-integration",
    "expected_base": base,
    "expected_head": head,
    "review_evidence": {
        "repository": "example/repository",
        "control_branch": "synology/main",
        "base_commit": base,
        "reviewed_commit": head,
        "implementation_branch": "governance/signed-protected-integration",
        "changed_paths": paths,
        "review_patch_sha256": "a" * 64,
        "required_checks": required,
        "authorises_integration": True,
        "validation_failures": 0,
    },
    "required_checks": required,
    "changed_paths": paths,
    "patch_sha256": "a" * 64,
    "remote_control": base,
    "control_head": base,
    "control_clean": True,
    "source_clean": True,
    "pr_worktree_clean": True,
    "pr_branch": "governance/signed-protected-integration",
    "pr_head": head,
    "pr_parent": base,
    "head_signature": "G",
    "github_head_verified": True,
    "github_head_verification_reason": "valid",
    "matching_signoff_count": 1,
    "pull_request": {
        "number": 17,
        "state": "open",
        "draft": False,
        "merged": False,
        "base_ref": "synology/main",
        "base_sha": base,
        "head_ref": "governance/signed-protected-integration",
        "head_sha": head,
        "commits": 1,
        "changed_files": len(paths),
    },
    "issue_comment_count": 0,
    "review_comment_count": 0,
    "changes_requested_count": 0,
    "unresolved_thread_count": 0,
    "required_signatures_rule": True,
    "pull_request_rule": True,
    "non_fast_forward_rule": True,
    "matching_always_bypass": True,
    "check_runs": [
        {
            "id": 101,
            "name": "repository-governance",
            "status": "completed",
            "conclusion": "success",
            "started_at": "2026-01-01T00:00:00Z",
        },
        {
            "id": 102,
            "name": "release-operations",
            "status": "completed",
            "conclusion": "success",
            "started_at": "2026-01-01T00:00:00Z",
        },
    ],
}

fixtures = {
    valid_path: valid,
    moved_path: copy.deepcopy(valid),
    unsigned_path: copy.deepcopy(valid),
    failed_path: copy.deepcopy(valid),
    unresolved_path: copy.deepcopy(valid),
}
fixtures[moved_path]["remote_control"] = "3" * 40
fixtures[unsigned_path]["head_signature"] = "N"
fixtures[unsigned_path]["github_head_verified"] = False
fixtures[unsigned_path]["github_head_verification_reason"] = "unsigned"
fixtures[failed_path]["check_runs"][0]["conclusion"] = "failure"
fixtures[unresolved_path]["unresolved_thread_count"] = 1

for path, data in fixtures.items():
    Path(path).write_text(json.dumps(data, indent=2, sort_keys=True) + "\n", encoding="utf-8")
PY

printf '=== Signed protected-integration synthetic tests ===\n'

if bash "$ENTRYPOINT" --fixture "$VALID_FIXTURE" > /dev/null; then
  pass_check "exact pre-integration fixture passed."
else
  fail_check "exact pre-integration fixture failed"
fi

for fixture_case in \
  "$MOVED_BASE_FIXTURE:moved protected base" \
  "$UNSIGNED_FIXTURE:unsigned reviewed head" \
  "$FAILED_CHECK_FIXTURE:failed required check" \
  "$UNRESOLVED_FIXTURE:unresolved review thread"; do
  fixture_path="${fixture_case%%:*}"
  description="${fixture_case#*:}"

  if bash "$ENTRYPOINT" --fixture "$fixture_path" > /dev/null 2>&1; then
    fail_check "${description} fixture was accepted"
  else
    pass_check "${description} fixture was rejected."
  fi
done

if grep \
  -nE \
  'gh[[:space:]]+pr[[:space:]]+merge|pulls/[^[:space:]]+/merge|merge_method=' \
  "$ENTRYPOINT" > /dev/null; then
  fail_check "entrypoint contains a forbidden GitHub merge primitive"
else
  pass_check "entrypoint contains no GitHub merge, squash or rebase endpoint."
fi

for required_pattern in \
  '--force-with-lease="refs/heads/${CONTROL_BRANCH}:${EXPECTED_BASE}"' \
  'pre_existing_check_ids' \
  'comment-close' \
  'remote-integrated' \
  '--resume'; do
  if grep \
    -Fq \
    -- \
    "$required_pattern" \
    "$ENTRYPOINT"; then
    pass_check "required integration control is present: ${required_pattern}"
  else
    fail_check "required integration control is absent: ${required_pattern}"
  fi
done

printf '\nSigned integration test failures: %s\n' "$FAILURES"

if [ "$FAILURES" -eq 0 ]; then
  echo "PASS: exact fixture passed and all unsafe fixtures were rejected."
  echo "PASS: lease, new-check, fallback and resume controls are present."
else
  echo "STOP: signed protected-integration synthetic tests failed."
fi

exit "$FAILURES"
