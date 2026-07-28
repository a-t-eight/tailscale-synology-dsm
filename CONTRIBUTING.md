# Contributing

## Scope

This repository maintains an unofficial downstream Tailscale build for
supported Synology DSM systems.

Before proposing a change, identify its destination:

- upstream source remains on `main`;
- downstream control assets belong on `synology/main`;
- applied downstream source changes belong on `work/*-synology` and
  `release/*-synology`;
- release-specific evidence belongs under `tests/releases/`;
- permanent release summaries belong under `docs/releases/`.

Do not place downstream files or patches on `main`.

## Commit requirements

Every downstream commit must:

- contain one logical change;
- have a good cryptographic signature;
- contain exactly one `Signed-off-by` trailer;
- avoid generated patch edits;
- preserve the branch invariants in `AGENTS.md`.

Create a signed and signed-off commit with:

```text
git commit -S -s
```

The signed commit stack is authoritative. Correct source commits first, then
regenerate patches with `git format-patch`.

## Validation

Run the canonical repository validation before opening a pull request:

```text
bash scripts/validate-repository.sh --bootstrap
```

The validation covers:

- shell syntax;
- ShellCheck errors;
- formatting of governance-owned shell scripts;
- Markdown policy;
- YAML policy;
- GitHub Actions syntax and pinned Action references;
- whitespace and governance metadata.

Hardware-dependent acceptance remains a separate manual gate.

## Pull requests

A pull request must state:

- the branch and release scope;
- the exact source or control commit;
- changed paths;
- validation performed;
- security, privilege, networking and upgrade impact;
- whether DSM hardware testing is required;
- whether release artefacts or evidence are affected.

Do not squash or rebase a reviewed signed commit when the workflow requires its
exact commit identity to be retained.

## Production safety

Automation must not:

- install or upgrade packages on a production NAS;
- run the root bootstrap;
- alter production firewall state;
- remove `/dev/net/tun`;
- reboot DSM;
- publish a stable release;
- approve its own changes.

Those actions require explicit human control.
