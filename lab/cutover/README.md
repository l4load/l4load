# VIP cutover observation

On the disposable IPVS lab, run `sudo env L4LOAD_CUTOVER=1 bash lab/ipvs/run.sh`.
Two independent IPVS tables share the backend topology; only the first has a
health controller. Change the synthetic VIP route to the second director and
back, recording fresh TCP/UDP and retained TCP connections separately.

`CUTOVER_OBSERVATION_COMPLETE` means the experiment completed, not lossless
migration. Read `cutover.jsonl`: a disrupted connection is not reused afterward,
so later recovery of that connection is unmeasured.

Add `L4LOAD_SYNC=1` to enable native IPVS connection synchronisation on a dedicated
veth link. Before each route change, the trial checks that all established TCP
source/VIP/backend mappings exist on the receiver, then swaps sync roles.
The lab sends updates for every incoming packet (`sync_threshold=0 1`); this is
not a production tuning recommendation. `SYNC_CUTOVER_PASS` requires every
retained-session check to pass, in addition to new TCP/UDP traffic.

[The comparison passed](https://github.com/l4load/l4load/actions/runs/36169152717):
without sync, four sessions reset on cutover and four created on the second
director reset on rollback. With sync, four original sessions survived cutover,
all eight existing sessions survived rollback, and twelve passed the final
exchange. These are short, planned transitions after a readback barrier.
Add `L4LOAD_SYNC_LOSS=1` with sync enabled to break replication before opening
connections. [The recovery trial passed](https://github.com/l4load/l4load/actions/runs/36171124968):
the barrier rejected handoff without changing the route or sync roles; four
original sessions remained usable. After restoring the link and sending traffic,
twelve sessions survived cutover, sixteen survived rollback, and twenty passed
the final exchange. Fresh TCP/UDP checks passed throughout.

Idle-session recovery, abrupt failure, automatic failover, sustained load,
cross-engine migration and production HA remain unqualified.

`L4LOAD_FORWARDING_FAILURE=1` with cutover enabled and sync disabled injects an
ingress blackhole while Keepalived remains alive. TCP and UDP timeouts plus drop
counters verify the failure; the harness then changes the route to the second
director, checks new flows, removes the fault and verifies return to the first.
`failure-timing.json` includes probe timeouts and verification overhead. This
qualifies an orchestrated recovery experiment, not an autonomous failure detector,
retained-session recovery or a production failover-time guarantee.

[The forwarding-failure trial passed](https://github.com/l4load/l4load/actions/runs/36224483206):
new TCP/UDP probes recovered after route replacement while the original controller
remained alive. Detection plus recovery verification took 2.06 seconds, including
two one-second probe timeouts. This is one synthetic observation, not an HA SLO.

Combine the fault flag with `L4LOAD_SYNC=1` to keep one TCP connection per backend
exchanging throughout the fault and recovery, with a 10-second socket timeout.
The experiment verifies replication before injection and prepares sync roles;
it does not model a stale replica or autonomous failover. No reconnect is allowed.
`failure-sessions.jsonl` records exchanges and maximum RTT per connection.

[The retained-session trial passed](https://github.com/l4load/l4load/actions/runs/36225087250/job/108357440531):
both sockets completed 16 exchanges without reconnecting; one exchange took
3.309 seconds. Sockets are serviced sequentially, so this does not measure each
flow's stall independently. Connection survival is not uninterrupted delivery.

`L4LOAD_VRRP=1` connects both directors to one synthetic L2 segment. Keepalived
VRRP owns a floating next-hop address and tracks TCP/UDP replies from a separate
probe namespace per director. A primary ingress blackhole leaves its backend
checker running; the trial requires the address and fresh traffic to move to
the backup, then return after the fault clears.
[One virtual job](https://github.com/l4load/l4load/actions/runs/36232798802/job/108379009383)
observed four dropped probe packets and 3.590 seconds from injection to verified
TCP/UDP recovery; [phase data](results/2026-09-26-vrrp.json) preserve address
ownership and traffic results. Retained sessions, independent path failures,
physical L2 behavior and a production failover SLO remain unqualified.
