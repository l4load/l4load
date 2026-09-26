# Routed VIP trial

Run `sudo bash lab/bgp/run.sh` on disposable Ubuntu 24.04 with `bird2` and
`iproute2`. Two directors independently advertise one synthetic /32 to a router.
The trial waits for both eBGP sessions, disables the primary route, checks the
router kernel next-hop, then restores it. [Observed result](results/2026-09-26-route.json).
The disable command simulates withdrawal. Set `L4LOAD_BGP_TRAFFIC=1` and install
`ipvsadm` and `nftables` to test IPVS traffic and health-driven withdrawal.
[One virtual result](results/2026-09-26-health-traffic.json) passed fresh TCP/UDP
before the fault, on the standby, and after return. No continuous-flow loss,
session preservation, BFD, hardware capacity, or production SLO was measured.
