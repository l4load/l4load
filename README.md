# L4Load

Independent L4 networking tools. Experimental; not production-ready.

Balance work starts with existing dataplanes: configure, test and tune before
implementing an engine. The [Katran DSR scenario](lab/katran/README.md) exercises
one IPv4 VIP and two backends over TCP/UDP without DPDK. Shield, Pulse and Fabric
are planned. No comparative performance results are available yet.

The [Keepalived/IPVS lifecycle trial](lab/ipvs/README.md) adds health-driven backend
exclusion and recovery, verified with TCP/UDP and kernel table snapshots. Neither
trial establishes production readiness or performance superiority.

The [Katran control-plane experiment](lab/katran-control/README.md) reproduces
an API/kernel-state mismatch under permanent injected write rejection. It is a
fault experiment, not a production-incidence or novelty claim.

The [IPv4 IPVS profile](profiles/ipvs/README.md) exposes the exact configuration
used by the lifecycle tests, with deployment prerequisites and operational limits.

## Run the trials

Use disposable Linux hosts and the instructions in the [lab](lab/README.md).
The trials need root privileges and create isolated network namespaces.
See [comparison criteria](docs/benchmarks.md) before interpreting results.

## Site

`python3 scripts/build_site.py` builds `site/index.html` from this revision.
The site repository receives that generated file and its source revision.

Apache-2.0. See [LICENSE](LICENSE).
