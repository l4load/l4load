# Comparisons

No competitive measurements have run. Existing trials qualify functional
behaviour; they do not establish throughput or latency advantages.

Targets: public [YANET](https://github.com/yanet-platform/yanet) for Balance and
Shield, [Katran](https://github.com/facebookincubator/katran) for XDP/DSR Balance.
Qualify YANET2 separately. Select Pulse/Fabric baselines for their actual workload.
Aim to outperform matched alternatives with a default deployment that needs no DPDK.

Match forwarding semantics, traffic, rules, state, CPU/memory budgets and topology.
Measure useful throughput, p99 latency, loss, CPU, memory, churn and update cost.
Shield also needs legitimate-traffic retention, false blocks and attack leakage.

Separate QEMU functional tests, virtualised measurements and physical NIC results.
Emulation is not a prediction of hardware speed. Pin source/build/config versions,
record the full environment and real execution time, run repeated paired trials,
retain raw results and report dispersion, regressions and unsupported scenarios.

Every milestone needs baseline evidence or an explicit comparison gap. A speed
claim requires equal semantics and a repeatable gain beyond measurement noise.
Also compare deployment dependencies, privileges and kernel/driver requirements.
