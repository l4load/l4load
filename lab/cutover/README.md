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
