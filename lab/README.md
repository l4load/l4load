# Lab

- [Katran](katran/README.md): IPv4 TCP/UDP DSR forwarding and source identity.
- [Keepalived/IPVS](ipvs/README.md): health exclusion, recovery, established sessions,
  configured drain and rollback.

Run only on disposable Linux hosts. Each trial records versions, real execution
time and raw results under `lab/results/`. These are functional checks, not NIC
throughput measurements. `baselines.json` pins comparison candidates; a pin does
not imply an executed test. Matched YANET comparison remains incomplete.
