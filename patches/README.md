# Patch artifacts

Each version directory contains three related representations.

- `maintenance.patch` is the recommended cumulative maintenance and adaptation
  patch.
- `release-tree.patch` reconstructs the accepted release tree exactly.
- `history/` contains the exact ordered `git format-patch` development history.

The signed downstream commit stack remains authoritative.

Generated patch files must not be manually edited. Correct the source commits or
generation process, then regenerate and round-trip validate every representation.
