#!/usr/bin/env bash
set -u

REPO_ROOT="$(
  cd \
    "$(dirname "${BASH_SOURCE[0]}")/../.." &&
    pwd
)"
BASELINE="$(
  python3 - "$REPO_ROOT/release/upgrade-baseline.json" << 'PY'
import json
import sys
from pathlib import Path

print(json.loads(Path(sys.argv[1]).read_text(encoding="utf-8"))["candidate"]["commit"])
PY
)"
SHELL_FILES=()

while IFS= read -r shell_file; do
  [ -f "$REPO_ROOT/$shell_file" ] && SHELL_FILES+=("$shell_file")
done < <(
  {
    git -C "$REPO_ROOT" diff \
      --name-only \
      --diff-filter=ACMR \
      "$BASELINE" \
      -- \
      '*.sh' \
      '*.bash'
    printf '%s\n' \
      .githooks/pre-commit \
      .githooks/commit-msg \
      release/dist/synology/files/scripts/start-stop-status \
      release/dist/synology/files/scripts/tailscale-netfilter-reconciler \
      release/dist/synology/files/scripts/tailscale-synology-bootstrap
  } | sort -u
)

[ "${#SHELL_FILES[@]}" -gt 0 ] || {
  echo "FAIL: changed shell inventory is empty." >&2
  exit 1
}

cd "$REPO_ROOT" || exit 1
shellcheck --severity=style "${SHELL_FILES[@]}" || exit 1
echo "PASS: canonical changed-shell ShellCheck passed at every severity."
