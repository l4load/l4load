# IPVS lifecycle trial

Disposable Ubuntu 24.04 only: install keepalived and ipvsadm, stop the packaged
keepalived service, then run `sudo bash lab/ipvs/run.sh`. Requires kernel modules
ip_vs, ip_vs_rr and ipip. CI records package versions and kernel; the inspected
upstream Keepalived master is not assumed to match the distribution package.

One VIP and two IPIP backends use the same TCP/UDP payload and client-address
checks as the Katran smoke. Three phases: both healthy, backend 1 health endpoint
down, recovered. Each phase sends 32 TCP and 32 UDP exchanges with distinct source
ports. The application on backend 1 stays alive when its health endpoint stops.
Keepalived must set both backend-1 IPVS weights to zero, direct all new test flows
to backend 2, then restore both backends after health recovery.

Kernel table snapshots, package versions, daemon logs and results are retained.
This is functional lifecycle coverage, not a throughput comparison or production
qualification. Existing-session drain, reload, controller failure, IPv6 and HA
remain untested. All namespaces/processes created by the test are cleaned up.

[First verified run](https://github.com/l4load/l4load/actions/runs/36128690604/job/108050671742),
2026-09-25: all 192 exchanges passed. Healthy and recovered phases each split
TCP/UDP 16/16; with backend-1 health down all 32 flows per protocol reached backend 2.
Every response preserved client IP and payload. Counts demonstrate coverage only.
