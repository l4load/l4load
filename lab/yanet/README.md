# YANET baseline

The workflow builds public YANET at `6b30c2f376c5148a661eadb57fd316d3b453e085`
in its pinned builder image, then runs upstream TCP/UDP, IPv4-real, reload and
backend-operation packet tests through the upstream socket driver. No NIC,
hugepages or corporate resources are used. DPDK remains part of this baseline.

This follows the upstream autotest build with LTO disabled and two compiler jobs
to limit CI build resources. It is a functional qualification step, not the
matched DSR echo scenario or a performance comparison. Capture compiler/package
versions, recursive source revisions, environment and raw logs on every run.
[Verified execution](https://github.com/l4load/l4load/actions/runs/36129923960/job/108054587993),
2026-09-25: all four suites completed, including packet expectations and state
checks. This does not establish live DSR return-path equivalence or throughput.
Later builds use ccache to avoid recompiling unchanged upstream code.

The pending live trial uses `run.sh upstream/yanet` after building that source.
It needs a disposable privileged Linux host, `/dev/net/tun` and the IPIP module.
One socket/TAP port joins the same synthetic client/backend subnets used by the
other trials. The adapter checks stream framing; it is not a throughput generator.
The IPv4 TCP/UDP echo and source-identity result is not yet verified.
