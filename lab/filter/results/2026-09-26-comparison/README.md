# Native policy update comparison

[Run 36224787284](https://github.com/l4load/l4load/actions/runs/36224787284),
source `fb85075f127d21f1a499fc6dddcd6e9d208ce360`, pinned YANET
`dacf4015f794e978c74200bb49f35472114d66aa`. Both engines ran sequentially in
the same builder: identical IPv4 source/VIP pairs and UDP echo client, no packet
capture. nftables used a set transaction; YANET used full native firewall reload.

| Pairs | nftables application, s | YANET application, s | nftables / YANET probes during update |
|---:|---:|---:|---:|
| 1,024 | 0.0646 | 0.5157 | 13 / 98 |
| 16,384 | 0.2924 | 3.5094 | 56 / 670 |
| 65,536 | 0.9098 | 44.4655 | 174 / 8,407 |
| 0 (clear) | 0.1142 | 0.6243 | 22 / 118 |

All 2,435 nftables and 11,562 YANET exchanges returned matching responses. At
65,536 pairs, RTT p99 for probes sent during application was 0.1634 ms and
1.0672 ms respectively. All eight summary rows were recomputed from the CSVs;
archive members and source CSV hashes were verified. See SHA256SUMS.

This compares the implemented update paths, not optimal possible tuning or
maximum forwarding capacity. The client waits for each reply and sleeps 5 ms;
this is not fixed offered load. Only one run per engine, fixed order, different
sample sizes and shared virtual resources were tested. Application time includes
adapter work and CLI completion, not packet-level policy activation latency or
transient deny gaps. No concurrent attack was generated. Child CPU/RSS excludes
the YANET daemon and kernel memory and is not comparable as engine totals.
No hardware advantage, production readiness or research novelty is established.
