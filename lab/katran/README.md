# Katran DSR smoke

Run `sudo bash lab/katran/run.sh /path/to/katran` on disposable Ubuntu 24.04
with clang, libbpf1, bpftool, iproute2, tcpdump and Python 3. Checkout upstream
revision `4546144594d11d7bf342d008e7b94922fc9bbaa3`; the script rejects changes.
The Katran DSR workflow provisions that environment.

Client -> router -> Katran -> router -> two IPIP backends; replies bypass Katran.
The unmodified GPL-2.0 upstream BPF source is compiled separately, not vendored
or relicensed. The Python glue only sets maps and exercises TCP/UDP echo traffic.

This is IPv4 functional coverage: 32 TCP and 32 UDP exchanges, both backends,
payload integrity and original client address. Generic XDP on veth, a static
alternating ring and the upstream fallback LRU are deliberate lab simplifications,
not a production control plane, Maglev evaluation or throughput measurement.
No failover, reload, IPv6 or NIC qualification is claimed.

Evidence in `lab/results/katran`: real UTC start, revisions, kernel/compiler,
object checksum, result, attachment and forwarding capture. The script cleans up
its namespaces and BPF pins; it must not run on a production host.
