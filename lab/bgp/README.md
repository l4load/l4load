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

Set `L4LOAD_BGP_TRAFFIC=4` for [established-session handoff](results/2026-09-26-session.json).
IPVS replicates connection state over a dedicated link. One TCP socket survived
route failover and failback, but an exchange paused for up to 3.35 s in this
virtual run. This does not qualify sync-link failure or session retention at scale.

Set `L4LOAD_BGP_TRAFFIC=5` for [sync-link loss before session setup](results/2026-09-26-sync-loss.json).
The older TCP socket reset after routed failover; new TCP/UDP flows passed on
standby. Loss after a session has already replicated remains untested.

Set `L4LOAD_BGP_TRAFFIC=6` for [bidirectional native sync](results/2026-09-26-dual-sync.json).
Both IPVS sync roles ran on each director. One TCP socket survived routed
failover and failback without a sync-role swap; a reply paused for 3.32 s.
State-table scale and sync traffic remain unqualified.

Set `L4LOAD_BGP_TRAFFIC=7` for the [routed unit trial](results/2026-09-26-routed-unit.json).
The installed BIRD config starts with VIP withdrawal; the systemd unit
controls BFD, forwarding health and both native sync roles. One TCP socket
survived failover/failback. Stopping the unit withdrew the route; restarting it
restored the route and fresh TCP/UDP traffic. The lab prepares IPVS services
and uses a stub base unit; full two-node installation and rollback remain unqualified.

Set `L4LOAD_BGP_TRAFFIC=8` for the [installed pair trial](results/2026-09-26-installed-pair.json).
Both directors use installed Keepalived/IPVS and BIRD units. The trial covers
failover, retained TCP state, unit restarts, a backend drain and configuration
rollback. It remains a short virtual-network result.

Set `L4LOAD_BGP_LOAD=1` alongside mode 8 for the
[denied-load trial](results/2026-09-26-attack-pair.json). Both directors run the
installed nftables filter while fresh TCP/UDP traffic crosses a routed failure.
The recorded 30-second run is a functional stress observation, not a capacity
or comparative ranking.
[Per-phase filter counters and service cgroups](results/2026-09-26-attack-phases.json)
show the denied rate during failover and where packets were dropped. Kernel
dataplane CPU remains outside the service accounting.

Set `L4LOAD_BGP_SOAK=1` with mode 8 and `L4LOAD_BGP_LOAD=1` for the
[routed soak trial](results/2026-09-26-soak.json). After failover and recovery,
it runs about one minute of TCP and UDP requests at 1000 messages/s each while
the filter denies about 100,000 packets/s. The recorded virtual run lost no
steady-state messages. It does not measure useful traffic at that rate during
the failover, physical throughput, or total host CPU.
