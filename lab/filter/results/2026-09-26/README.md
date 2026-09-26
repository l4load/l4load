# Snapshot continuity observation

[Run 36224173886](https://github.com/l4load/l4load/actions/runs/36224173886),
source `fcff44fd1ac6507eb31120dfe940324637939cd5`. The retained CSV contains
2,399 sequential UDP exchanges, all successful. Summaries were recomputed from
raw timestamps and RTTs; SHA256SUMS covers the retained files.

| Pairs | Application seconds | Probes sent during update | Lost | p99 RTT, ms |
|---:|---:|---:|---:|---:|
| 1,024 | 0.0642 | 12 | 0 | 0.0826 |
| 16,384 | 0.1877 | 36 | 0 | 0.0895 |
| 65,536 | 0.6990 | 134 | 0 | 0.0957 |
| 0 (clear) | 0.1140 | 22 | 0 | 0.0842 |

Application time includes Python startup, validation and nft invocation. Probes
sleep 5 ms between exchanges; this is low-rate continuity, not saturation or a
comparison with another engine. Small-sample p99 is not a stable tail estimate.
Child RSS is cumulative and excludes kernel memory. No physical NIC, concurrent
attack, TCP-session preservation or autonomous reconnect was qualified here.
