# Load harness

Experimental sockperf qualification in the existing disposable IPVS DSR lab.
Run `sudo env L4LOAD_LOAD=1 bash lab/ipvs/run.sh` with the normal prerequisites
and packaged sockperf. The functional echo check runs first; owned echo servers
are then replaced by sockperf. This mode exits before the lifecycle scenarios.

TCP/UDP, 64-byte messages, requested 1k/10k messages per second, three five-second
repetitions. Replies sample every message; report full RTT, not RTT/2. Retain
raw logs/CSV, actual rates, errors and package/kernel/CPU metadata. A zero exit
status is not evidence that the requested rate or an application SLO was met.
Each summary records its CSV filename, byte count and SHA-256 for archive checks;
the digest does not replace the samples or validate their contents.

This first run qualifies the tool integration only. Shared-runner scheduling,
generator/receiver limits, CPU placement, paired engines and sustained load
remain uncontrolled; do not rank engines from it.
See [sockperf under-load semantics](https://github.com/Mellanox/sockperf/wiki/UnderLoad).

The integration workflow also runs pinned Katran generic XDP after IPVS on the
same host. Packet capture is disabled during load. This checks reuse of the
same traffic tool; fixed engine order, unpinned CPU placement and single-flow
trials still prevent a controlled ranking. YANET uses the same generator in its pinned builder container via
`L4LOAD_LOAD=1 unshare --ipc bash lab/yanet/run.sh upstream/yanet af-packet`.
That is a separate environment/run, not a paired ranking. Capture stays disabled
during load; native checksum and MTU settings still apply.

The shared-environment workflow runs all three engines sequentially inside the
same pinned builder container on one host. It records package versions and uses
the installed libbpf for Katran's map API. This removes the previous userspace
mismatch; [36 cases passed](https://github.com/l4load/l4load/actions/runs/36152260708).
Fixed order, shared CPUs, scheduler noise,
short duration and low rates still prevent capacity or superiority claims.

Ordered trials use three cyclic engine orders so each engine occupies each
position once. `L4LOAD_TRIAL=round-1` adds an output suffix; an existing directory
is rejected instead of overwritten. The order/UTC log and observed affinity,
cgroup path and available limits accompany reports. These records do not prove
CPU isolation or account for veth softirq placement.
[All 108 cases passed](https://github.com/l4load/l4load/actions/runs/36155111339)
without reported drops; the elevated YANET 10k p99 persisted in every order.

The placement experiment runs each engine with inherited affinity, then
`L4LOAD_CPUS=3`, then inherited affinity again on the same runner. Only sockperf
client/server placement changes. CPU topology, requested placement and server
affinity are recorded; all samples have size/SHA-256 in their summary. CPU 3 is
a logical CPU, not a dedicated physical core. This also moves sender-side veth
processing and may contend with SMT siblings; it does not isolate dataplanes.
Qualification is pending. The earlier cyclic-order workflow remains reproducible
at commit `3b5c268e33dca4c927514b19d004719bbbaa478d`.
