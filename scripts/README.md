# Scripts

Planned script groups:

- `patch/` — export, apply, refresh and compare patch series
- `build/` — build and inspect candidate SPKs
- `nas/` — human-invoked installation and acceptance tooling

## NAS tools

- `nas/validate-synology-runtime.sh` — validate an installed Synology Tailscale
  package using bootstrap state, LocalAPI, PID files, `/proc` command lines,
  persistent state and required netfilter chains.
