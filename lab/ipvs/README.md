# IPVS lifecycle trial

Disposable Ubuntu 24.04 only: install keepalived and ipvsadm, stop the packaged
keepalived service, then run `sudo bash lab/ipvs/run.sh`. Requires kernel modules
ip_vs, ip_vs_rr and ipip. The test creates and cleans up five network namespaces.
Package versions, kernel, configuration, table snapshots and logs are recorded.

One IPv4 VIP and two IPIP backends serve TCP/UDP. Keepalived checks HTTP 200 at
`/health` on a separate port. Tests cover connection failure, HTTP 404 with the
server still running, recovery, weight-zero reload and rollback. Fresh flows must
avoid excluded backends; two established TCP sessions must retain their backend,
payload and client address across each transition.

With `-I`, a graceful controller stop preserves forwarding but freezes health
decisions. A direct restart failed to exclude a backend that became unhealthy
while the controller was stopped. The tested recovery zeroes the four retained
destination weights before startup and waits for healthy weights to return.
Existing sessions survive; new flows pause during that gate. This is a bounded
synthetic recipe, not seamless restart or a general reconciliation service.

| Evidence, 2026-09-25 | Result |
|---|---|
| [Direct restart](https://github.com/l4load/l4load/actions/runs/36130108789) | Failed to converge unhealthy weight within 15 seconds |
| [Gated restart](https://github.com/l4load/l4load/actions/runs/36130540624/job/108056535442) | 448 fresh exchanges and two persistent sessions passed with TCP health checks |
| [HTTP health](https://github.com/l4load/l4load/actions/runs/36130798955/job/108057346193) | 576 fresh exchanges and two persistent sessions passed, including HTTP 404/recovery |

Counts demonstrate short functional coverage only. Sustained traffic, abrupt
controller failure, invalid configuration, IPv6, HA and capacity remain unqualified.
Health checks cannot protect traffic while the controller is stopped. The observed
restart limitation is scoped to the recorded package/configuration.
