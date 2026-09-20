# YANET baseline

The workflow evaluates public YANET PR #335 at `dacf4015f794e978c74200bb49f35472114d66aa`
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

The live trial uses `run.sh upstream/yanet` after building that source.
It needs a disposable privileged Linux host, `/dev/net/tun` and the IPIP module.
One socket/TAP port joins the same synthetic client/backend subnets used by the
other trials. The adapter checks stream framing; it is not a throughput generator.
[Live execution](https://github.com/l4load/l4load/actions/runs/36142209366/job/108094522813),
2026-09-25: 32 TCP and 32 UDP exchanges passed, split equally across both
backends with client IP and payload preserved. All four upstream suites also
passed. This uses upstream autotest table limits; the initial default-sized
configuration exhausted the runner's allocation budget.

Earlier runs intermittently failed the upstream reload packet expectation;
the cause is unresolved. Passing this run does not erase those failures.
The Python/TAP bridge and socket driver make this a functional baseline only.
Use a qualified native virtual-device path before measuring engine performance.

The base above was `6b30c2f376c5148a661eadb57fd316d3b453e085`. Its intermittent
reload failure matches the existing [upstream PR #335](https://github.com/yanet-platform/yanet/pull/335)
by ezhk. [Our before/after unit run](https://github.com/l4load/l4load/actions/runs/36144972495)
reproduced that PR's regression on the base and passed all three neighbor tests
with the upstream implementation. The workflow now pins that candidate and adds
five reload repetitions; their packet-level results are pending. This is not a
new L4Load patch or a claim of production qualification.

The native experiment uses DPDK AF_PACKET on a veth, with two symmetric queues
and hardware RSS disabled. The first run failed before forwarding: YANET's
9000-byte MTU exceeded the PMD's advertised 1500-byte limit. This branch changes
the build-time MTU to 1500 and records the exact diff in `build-profile.txt`.
Both socket and native cases use that build. Native forwarding is still pending;
jumbo frames and hardware performance are outside this virtual profile.
