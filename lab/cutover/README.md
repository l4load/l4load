# VIP cutover observation

On the disposable IPVS lab, run `sudo env L4LOAD_CUTOVER=1 bash lab/ipvs/run.sh`.
Two independent IPVS tables share the backend topology; only the first has a
health controller. Change the synthetic VIP route to the second director and
back, recording fresh TCP/UDP and retained TCP connections separately.

`CUTOVER_OBSERVATION_COMPLETE` means the experiment completed, not lossless
migration. Read `cutover.jsonl`: a disrupted connection is not reused afterward,
so later recovery of that connection is unmeasured. No state synchronisation,
automatic failover, cross-engine migration or production HA is qualified.
