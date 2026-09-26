# Policy updates under denied traffic

[Run 36227151660](https://github.com/l4load/l4load/actions/runs/36227151660),
source `dfc8918597c074f41d59ac4bbc4d144c6061a52e`. Both engines use the same
builder and sequential UDP echo probe. No packet capture. YANET is pinned to
`dacf4015f794e978c74200bb49f35472114d66aa`, using AF_PACKET.

At 65,536 IPv4 source/VIP pairs:

| Engine | Background | Apply, s | Probes during apply | RTT p99, ms |
|---|---|---:|---:|---:|
| nftables/IPVS | none | 0.909 | 173 | 0.178 |
| nftables/IPVS | denied UDP | 0.909 | 173 | 0.191 |
| YANET | none | 44.912 | 8,428 | 1.229 |
| YANET | denied UDP | 37.224 | 6,981 | 2.606 |

All 28,722 nftables and 28,899 YANET useful exchanges in the loaded passes
succeeded. Denied generators averaged 100,001–100,007 messages/s across their
whole runs; recorded process checks bracket each nonempty update. This does not
measure exact ingress rate within an update or exclude transient deny gaps.
Clearing the policy runs after the generator stops. Sixteen summary rows were
independently recomputed from CSVs; decoded sample hashes were checked.

One run per condition, fixed order and shared virtual CPUs cannot establish a
causal speedup, capacity or production advantage. Useful traffic waits for each
reply and sleeps 5 ms, so this is not fixed offered load. Application duration
includes adapter/CLI work, not packet activation latency. Native paths differ:
nft set replacement versus full YANET firewall reload. Child CPU/RSS omits daemon
and kernel resources and must not be compared as total engine cost. No optimal
tuning, physical-NIC performance, saturation limit or research novelty is claimed.

`samples.tar.gz` retains four CSVs; `audit.json` contains recomputed observations,
and `evidence.json` retains update and generator records. `SHA256SUMS` covers
these files. Reproduce with the workflow's no-load and loaded bulk steps.
