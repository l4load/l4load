# Routed VIP trial

Run `sudo bash lab/bgp/run.sh` on disposable Ubuntu 24.04 with `bird2` and
`iproute2`. Two directors independently advertise one synthetic /32 to a router.
The trial waits for both eBGP sessions, disables the primary route, checks the
router kernel next-hop, then restores it. [Observed result](results/2026-09-26-route.json).
The disable command simulates withdrawal. Set `L4LOAD_BGP_TRAFFIC=1` and install
`ipvsadm` and `nftables` to test IPVS traffic and health-driven withdrawal.
[One virtual result](results/2026-09-26-health-traffic.json) passed fresh TCP/UDP
before the fault, on the standby, and after return. That first run did not
measure handoff loss, session preservation, BFD or hardware capacity.

[The traffic run](results/2026-09-26-useful.json) records individual fresh-flow
attempts during withdrawal and recovery. It requests 100 attempts/s per protocol,
but sequential 250 ms timeouts lower the actual fault-phase rate. It does not
establish loss at a fixed offered rate or sustained capacity.

Set `L4LOAD_BGP_TRAFFIC=2` for [independent scheduled attempts](results/2026-09-26-fixed.json).
In one virtual run the generator held about 100 actual starts/s per protocol
through the fault. This is a short functional envelope, not a capacity limit.

Set `L4LOAD_BGP_TRAFFIC=3` for [single-hop BFD loss](results/2026-09-26-bfd.json).
The director gates its VIP advertisement on its local BFD state. The trial drops
BFD packets both ways while IPVS traffic remains reachable. It does not qualify
multihop BFD or physical link failure.
