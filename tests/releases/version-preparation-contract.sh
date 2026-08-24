#!/usr/bin/env bash
set -u

REPO_ROOT="$(
  cd \
    "$(dirname "${BASH_SOURCE[0]}")/../.." &&
    pwd
)"
BASELINE="${REPO_ROOT}/release/upgrade-baseline.json"
SCHEMA="${REPO_ROOT}/release/version-preparation.schema.json"

fail() {
  printf 'FAIL: %s\n' "$1" >&2
  exit 1
}

for required_path in "$BASELINE" "$SCHEMA"; do
  if [ ! -s "$required_path" ]; then
    fail "required version-preparation contract is unavailable: ${required_path}"
  fi
done

python3 - "$REPO_ROOT" "$BASELINE" "$SCHEMA" << 'PY'
import hashlib
import json
import re
import subprocess
import sys
from pathlib import Path


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
        path.read_text(encoding="utf-8"),
        object_pairs_hook=reject_duplicate_members,
        parse_constant=reject_constant,
    )


root = Path(sys.argv[1])
baseline = load(Path(sys.argv[2]))
schema = load(Path(sys.argv[3]))

expected_top = {
    "schema_version",
    "candidate",
    "protected_blobs",
    "synology_contract",
    "safety",
}
if set(baseline) != expected_top:
    raise SystemExit(f"baseline top-level fields differ: {sorted(baseline)}")
if baseline["schema_version"] != 1:
    raise SystemExit("baseline schema_version must equal 1")

candidate = baseline["candidate"]
if candidate != {
    "commit": "8c9fe5239ee57a89ce687fc8c7608d3df91f6ede",
    "tree": "6d171c2a01c0fafb9567f3f4bc49bdd4f7ff7392",
}:
    raise SystemExit("candidate identity differs from the accepted r2 candidate")

expected_blobs = {
    "cmd/tailscale/cli/up.go": (
        "ace6ac3dbdcc42f18e3dadfacbc65cee1b1df311",
        "5da19848c5a76a2242c300b8accf6ae2100d96589d66869eb374fc12337e31c1",
    ),
    "cmd/tailscaled/tailscaled.go": (
        "6f0dcede86551dfb142f5a2a6944de92c1ecd756",
        "684e79377cbbe79dc3d3ad7bc8400f26101d1d958ce78a9a724ab4a3d1571990",
    ),
    "ipn/ipnlocal/local.go": (
        "b84205d914f2e47e4cefda1a4a0ce98202cd552f",
        "dbbec62dd501abb1262593e19b70868d3b5ca478d6a9d9e7848d1cfb1256a570",
    ),
    "util/linuxfw/iptables_runner.go": (
        "03d9b87a8c0c35d655e60b4456ba136116b6afd2",
        "96d2122b8929433cb0ac987587ebf969406fb3d64067378b2b3975b810aeb137",
    ),
    "wgengine/router/osrouter/router_linux.go": (
        "c48749734c5618bfe3973afbb2d00f75b34e0d13",
        "54339503f0d7e5598aa3b507a7c685408bcd84d6580bde69acf19a5e60154da0",
    ),
    "patches/v1.98.9/synology-netfilter.patch": (
        "b0a9474448b0f5bac5b24229ffe6827c4eebe897",
        "ad577d4032e3c14fa37b284b7e5116c364122471b1d9fdc2c906bf8ae198920f",
    ),
    "patches/v1.98.9/synology-netfilter.patch.sha256": (
        "5b88bba7a6ac4b8cea5d307bee5cdc9769e70ad4",
        "b0a7641e8297c79ea2c40ffddc82632cfbdaf83029b4552e42572b227a2b7fe4",
    ),
}

observed_entries = baseline["protected_blobs"]
if len(observed_entries) != 7:
    raise SystemExit("baseline must enumerate exactly seven protected blobs")
observed = {}
for entry in observed_entries:
    if set(entry) != {"path", "git_blob", "sha256"}:
        raise SystemExit(f"protected blob entry has unknown fields: {entry}")
    path = entry["path"]
    if path in observed:
        raise SystemExit(f"duplicate protected path: {path}")
    observed[path] = (entry["git_blob"], entry["sha256"])
if observed != expected_blobs:
    raise SystemExit("protected blob manifest differs from the accepted candidate")

for relative, (expected_git, expected_sha) in expected_blobs.items():
    path = root / relative
    if not path.is_file():
        raise SystemExit(f"protected file is missing: {relative}")
    actual_git = subprocess.check_output(
        ["git", "-C", str(root), "hash-object", relative], text=True
    ).strip()
    actual_sha = hashlib.sha256(path.read_bytes()).hexdigest()
    if actual_git != expected_git or actual_sha != expected_sha:
        raise SystemExit(f"protected file identity differs: {relative}")

contract = baseline["synology_contract"]
expected_contract = {
    "dependency_section": "iptables-netfilter-extensions",
    "dependency_minimum": "1.1.0-3",
    "dependency_os_minimum": "7.3-86009",
    "tailscale_os_minimum": "7.3-86009",
    "os_max_ver_allowed": False,
}
if contract != expected_contract:
    raise SystemExit("Synology product contract differs from the r2/new lineage")

pkg_deps = (root / "release/dist/synology/files/PKG_DEPS").read_bytes()
expected_pkg_deps = (
    b"[iptables-netfilter-extensions]\n"
    b"pkg_min_ver=1.1.0-3\n"
    b"os_min_ver=7.3-86009\n"
)
if pkg_deps != expected_pkg_deps:
    raise SystemExit("PKG_DEPS bytes differ from the r2/new-lineage contract")

expected_safety = {
    "allow_fetch": False,
    "allow_push": False,
    "allow_pull_request": False,
    "allow_tag": False,
    "allow_release": False,
    "allow_publish": False,
    "allow_spk_build": False,
    "allow_dependency_spk_build": False,
    "allow_nas_install": False,
    "allow_root_bootstrap": False,
    "allow_firewall_mutation": False,
    "allow_reboot": False,
}
if baseline["safety"] != expected_safety:
    raise SystemExit("baseline safety capabilities must all be present and false")

if schema.get("$schema") != "https://json-schema.org/draft/2020-12/schema":
    raise SystemExit("version-preparation schema must use JSON Schema 2020-12")
if schema.get("$id") != "https://a-t-eight.github.io/tailscale-synology-dsm/version-preparation.schema.json":
    raise SystemExit("version-preparation schema ID differs")
if schema.get("type") != "object" or schema.get("additionalProperties") is not False:
    raise SystemExit("version-preparation schema root must reject unknown members")
required = set(schema.get("required", []))
expected_required = {
    "schema_version",
    "source",
    "upstream",
    "version",
    "prepared",
    "logical_commits",
    "patches",
    "synology_contract",
    "validation",
    "safety",
}
if required != expected_required:
    raise SystemExit("version-preparation schema required fields differ")
if not re.fullmatch(r"[0-9a-f]{40}", candidate["commit"]):
    raise SystemExit("candidate commit is not a full lowercase SHA")

print("PASS: version-preparation baseline, protected blobs, schema, and safety contract are valid.")
PY
