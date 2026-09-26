# Paired denied-load trial, 2026-09-26

One four-vCPU GitHub runner, IPv4 UDP DSR, two backends, 64-byte messages, 300 s per trial. Order: IPVS, YANET AF_PACKET, YANET AF_PACKET, IPVS. Each trial offered 1,000 permitted and 100,000 denied messages/s; observed generator rates were within 0.002% of these targets. The permitted source was distinct from the blocked source.

| Engine | Useful received / sent, each trial | Useful p99 RTT | Runner busy |
| --- | --- | --- | --- |
| IPVS + nftables | 299,549/299,549; 299,547/299,547 | 65.509; 67.964 µs | 50.35%; 50.41% |
| YANET AF_PACKET | 299,550/299,550; 299,548/299,548 | 979.115; 844.812 µs | 78.58%; 78.25% |

Both preserved all observed useful probes at this rate. At a separate 65,536-pair policy update under the same offered load, IPVS/nftables took 0.907 s with 0/173 lost useful probes; YANET's native reload took 44.048 s with 1/8,242 lost and failed the continuity gate. Its policy did apply; the failure is loss during the update. The update mechanisms and exposure windows differ.

[Run](https://github.com/l4load/l4load/actions/runs/36252980697) · [raw artifact](https://github.com/l4load/l4load/actions/runs/36252980697/artifacts/10911010042) · [measurements](measurements.json). The artifact expires 2026-12-25; `measurements.json` records its digest and each CSV digest. The figures were extracted from the completed CI log and summary files; the four full CSVs remain in the artifact and were not independently replayed here.

This is one shared virtual host with two trials per engine. Runner busy includes traffic generators and control processes; it is not dataplane CPU. AF_PACKET and kernel IPVS use different packet paths. These data show a lower p99 and host load for this IPVS profile, not a hardware throughput ceiling, optimal YANET tuning, or a general performance ranking. The offered permitted rate and DSR scheduler are below and simpler than an unqualified production workload.
