# IPVS lifecycle trial

Disposable Ubuntu 24.04 only: install keepalived, ipvsadm and
prometheus-node-exporter, stop their packaged services, then run
`sudo bash lab/ipvs/run.sh`. Requires kernel modules
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

[Configuration trial](https://github.com/l4load/l4load/actions/runs/36132397199/job/108062445520)
passed 640 fresh exchanges and two persistent sessions. A candidate with port
70000 was rejected by `keepalived -t`, leaving the working file byte-identical.
Valid drain/rollback candidates use the same preflight, atomic rename and HUP.
This checks one malformed input, not every invalid configuration or update race.

Counts demonstrate short functional coverage only. Sustained traffic, host failure, concurrent configuration updates, HA and
capacity remain unqualified.

The [MH trial](https://github.com/l4load/l4load/actions/runs/36258566786)
loaded `mh-port,mh-fallback` for TCP and UDP. With one client IP and changing
source ports, 64/64 flows reached both backends; after one backend failed,
64/64 new flows reached the survivor, and 64/64 reached both after recovery.
This checks short functional behavior on one virtual host, not stable mapping
across restarts, persistence or workload capacity. Run with
`sudo env L4LOAD_MH=1 L4LOAD_TRIAL=mh bash lab/ipvs/run.sh`.
The [persistence trial](https://github.com/l4load/l4load/actions/runs/36259300786)
added a 300-second client template. All 64 fresh flows from one client IP
selected one backend; with default `expire_quiescent_template=0`, all 64 new
flows stayed pinned after its health weight became zero. Setting it to `1`
moved all 64 new flows to the survivor. The installed service now sets it on
start and reload; [lifecycle CI](https://github.com/l4load/l4load/actions/runs/36259478057)
checks the setting. This is one short virtual trial, not a capacity result.

In a [planned two-director cutover](https://github.com/l4load/l4load/actions/runs/36261617603),
the backup had all 16 persistent templates for eight synthetic clients and
both protocols before the route moved. Their backend mappings matched across
the cutover; 512 fresh TCP/UDP exchanges passed on each side. This does not
qualify abrupt failover, replication loss, backend-set changes or an HA SLO.
Health checks cannot protect traffic while the controller is stopped. The observed
restart limitation is scoped to the recorded package/configuration.

`sudo bash lab/ipvs/ipv6.sh` runs a separate IPv6-over-IPv6 DSR trial.
[Verified run](https://github.com/l4load/l4load/actions/runs/36134413105/job/108068928725):
192 TCP/UDP exchanges preserved source IP through healthy, failed TCP-health-port
and recovered phases. A subsequent [continuity trial](https://github.com/l4load/l4load/actions/runs/36141957631)
preserved two TCP sessions across health exclusion/recovery: 71 exchanges each
over 3.5 seconds. This is short functional coverage; IPv6 HTTP health, reload,
restart and sustained traffic remain unqualified.

[Process-tree crash trial](https://github.com/l4load/l4load/actions/runs/36135359918/job/108072010672)
passed 768 IPv4 exchanges and two persistent sessions. The test stopped the
supervisor, sent SIGKILL to every process in its isolated namespace, verified no
processes remained, and exercised gated restart after a health-port failure.
Kernel state survived; stale health decisions persisted until restart. This does
not qualify reboot, kernel failure or automatic service-manager recovery.

The datagram probe checks 64–4000-byte binary payloads on IPv4 and IPv6.
It records every attempt and route-cache change. Only `EMSGSIZE` with the
expected learned MTU permits one fresh-socket retry; timeout, corruption or
failed retry fails the trial. The first failures remain part of the evidence.
This checks PMTU feedback/recovery, not lossless delivery or all ICMP cases.

[Automatic service recovery](https://github.com/l4load/l4load/actions/runs/36137752964)
passed with `NRestarts=1`, a new controller PID, 832 fresh IPv4 exchanges and
678 continuous exchanges per retained TCP session. The disposable unit binds
to the owned network namespace and gates retained destinations before startup.
Cold installation, host reboot and HA remain unqualified. The earlier manual
termination trial does not by itself establish this service-manager result.

[Empty-table startup](https://github.com/l4load/l4load/actions/runs/36138065416)
passed after retained-session tests finished: the service rebuilt two VIP
services and four destinations, then forwarded 64 new exchanges. The full
IPv4 lifecycle now checks 896 fresh exchanges. Networking and packages were
already configured; this does not establish reboot or installation readiness.

[IPVS metrics](https://github.com/l4load/l4load/actions/runs/36140910330)
passed using the packaged node_exporter collector on namespace loopback.
Raw scrapes matched all four destination weights through health failure and
recovery. This qualifies collection, not retention, alerts or monitoring HA.
