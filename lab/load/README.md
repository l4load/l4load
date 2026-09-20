# Load harness

Experimental sockperf qualification in the existing disposable IPVS DSR lab.
Run `sudo env L4LOAD_LOAD=1 bash lab/ipvs/run.sh` with the normal prerequisites
and packaged sockperf. The functional echo check runs first; owned echo servers
are then replaced by sockperf. This mode exits before the lifecycle scenarios.

TCP/UDP, 64-byte messages, requested 1k/10k messages per second, three five-second
repetitions. Replies sample every message; report full RTT, not RTT/2. Retain
raw logs/CSV, actual rates, errors and package/kernel/CPU metadata. A zero exit
status is not evidence that the requested rate or an application SLO was met.

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
