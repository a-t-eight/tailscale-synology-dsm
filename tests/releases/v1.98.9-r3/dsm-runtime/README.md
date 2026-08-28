# DSM 7.4.1 attended acceptance

The accepted sideload artifact was tested on DSM 7.4.1. The Task 5 resource boundary preserved DSM-managed resources, rejected a linked mutation attempt, and entered through the outer root-owned bootstrap. The manifest binding, UID 0 runtime, root-owned promoted target, transaction cleanup, LocalAPI and tailnet readiness all passed.

The operator also recorded idempotent install, package restart, remove then re-bootstrap, attended reboot recovery, TUN operation, IPv4 and IPv6 netfilter hooks, and functional network operation. This record deliberately excludes identifying runtime details and raw transcripts.

Not tested or claimed: upgrade from r2, rollback, uninstall, and volume migration.
