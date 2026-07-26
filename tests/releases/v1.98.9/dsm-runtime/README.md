# DSM runtime acceptance

This directory records production runtime acceptance of the final Synology DSM
v1.98.9 downstream release commit:

`20c86229955a3d03de01901aee1499cab87c571d`

The tested sideload package was:

`tailscale-x86_64-1.98.96-700098096-dsm7.spk`

## Result

The package passed runtime acceptance on a Synology DS920+ running DSM 7.3.2:

- DSM accepted the package as an upgrade even though its package version exactly
  matched the installed version;
- the installed binary changed to the final signed release commit;
- the persistent Tailscale state remained byte-identical;
- node identity and Tailscale addressing were preserved;
- the binary change intentionally made the root-bootstrap approval stale;
- reapplying the administrator bootstrap completed successfully;
- `tailscaled` ran as UID 0 using the expected executable and arguments;
- the netfilter reconciler ran using the expected script;
- LocalAPI access and retained routing preferences were validated;
- `filter/ts-input`, `filter/ts-forward` and `nat/ts-postrouting` were present.

`acceptance.env` is the portable machine-readable result.

## Evidence policy

The complete source archive is intentionally retained outside Git because it
contains tailnet-specific status, preferences, host inventory and detailed
runtime logs.

The repository retains:

- the exact source archive SHA-256 digest;
- the original 43-entry source evidence manifest;
- the independent post-transfer verification result;
- selected package, bootstrap, process and netfilter evidence that is safe to
  publish;
- node-specific Tailscale addresses redacted from retained iptables rule
  excerpts while preserving the rule structure;
- synthetic terminal spaces introduced when converting the final
  `/proc/<pid>/cmdline` NUL separator to text removed from the published
  command-line excerpts;
- a sanitised acceptance record that preserves the validation conclusions
  without publishing tailnet-specific identifiers.

`provenance/source-archive.sha256` identifies the retained source archive.
`provenance/source-evidence-SHA256SUMS` describes the complete original bundle.

## Reusable validator

`scripts/nas/validate-synology-runtime.sh` implements the corrected runtime
validation pattern.

Process checks use package PID files and `/proc/<pid>/cmdline`; they do not use
the incomplete `ps w` process view observed on DSM.
