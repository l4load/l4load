# YANET baseline

The workflow builds public YANET at `6b30c2f376c5148a661eadb57fd316d3b453e085`
in its pinned builder image, then runs upstream TCP/UDP, IPv4-real, reload and
backend-operation packet tests through the upstream socket driver. No NIC,
hugepages or corporate resources are used. DPDK remains part of this baseline.

This follows the upstream autotest build with LTO disabled and two compiler jobs
to limit CI build resources. It is a functional qualification step, not the
matched DSR echo scenario or a performance comparison. Capture compiler/package
versions, recursive source revisions, environment and raw logs on every run.
Execution is pending; no passing result is claimed.
