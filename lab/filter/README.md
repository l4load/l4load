# Filter lifecycle trial

On a disposable Ubuntu 24.04 runner with the IPVS lab prerequisites and nftables,
run `sudo env L4LOAD_FILTER=1 bash lab/ipvs/run.sh`.

Native nftables ingress filtering matches an IPv4 source/VIP pair before IPVS.
The trial checks TCP/UDP forwarding, a temporary deny with kernel drop counters,
unaffected traffic from another source, rejection of an invalid transaction,
expiry without a controller and table removal. `FILTER_LIFECYCLE_PASS` requires
all checks; results are in `lab/results/ipvs`.

The snapshot check replaces the complete deny set, rejects malformed input without
changing it, and applies an empty snapshot to remove stale denies. Run the helper
with a JSON list of `[source IPv4, VIP IPv4]` pairs on stdin; it submits one nft
transaction against the installed profile. Snapshot entries have no expiry.
This tests state replacement, not a controller transport or reconnect protocol.

The HTTPS reconnect trial uses a disposable certificate and local server. It
checks application, untrusted TLS, a truncated response containing valid JSON,
server loss, malformed JSON after reconnection and a valid
empty snapshot, probing both denied and permitted traffic after each step.
`FILTER_RECONNECT_PASS` qualifies that sequence, not multi-writer ordering,
source freshness, automatic retries or a production policy service.

`L4LOAD_FILTER_SNAPSHOTS=1` additionally replaces 1,024, 16,384 and 65,536
synthetic pairs, then clears them while a sequential UDP echo probe runs.
`snapshot-updates.json` records application intervals; `snapshot-traffic.csv`
records every exchange and timeout.
`snapshot-summary.json` reports samples sent during each application interval,
their losses and p99, plus child CPU time and cumulative child peak RSS on Linux.
RSS is not isolated per update and excludes kernel set memory; CPU excludes the
concurrently running probe. Intervals with no samples fail qualification.
The probe pauses 5 ms between exchanges and waits at most 200 ms per reply:
it measures continuity, not offered-load capacity.
The bulk marker requires zero observed permitted-packet loss and deny/allow
checks after each update. It does not prove no transient policy gap, reconnect
ordering, retained TCP sessions or hardware performance.

[The bulk trial passed](results/2026-09-26/): 65,536 pairs applied in 0.699 seconds,
with 134 probes sent during that interval and no observed losses. Raw samples,
per-update summaries and environment versions are preserved; this single low-rate
observation does not establish capacity or superiority over another engine.

[A matched native-update observation](results/2026-09-26-comparison/) applied
65,536 pairs in 0.910 s with nftables and 44.466 s with YANET firewall reload.
Both preserved the observed low-rate UDP exchanges. This measures those update
paths in one virtual run; it does not rank forwarding capacity or optimal tuning.

The current bulk trial also probes addresses from the beginning, middle and end
of each generated range. Each new source must forward before its first inclusion,
be denied after application, and forward again after clearing. This catches some
partial-application errors; it is sampled coverage, not exhaustive verification
of all pairs or proof of transient policy atomicity.

[The nftables trial passed](https://github.com/l4load/l4load/actions/runs/36172967453).
[YANET passed the same deny/allow probes](https://github.com/l4load/l4load/actions/runs/36174467560),
including rejected reload and explicit rollback. Only nftables expiry was tested;
these results establish neither equivalent full features nor a performance winner.

This is an experiment, not a Shield release. Prefixes, IPv6, fragments, tenant
isolation, reboot persistence and overload protection are unqualified.
Do not infer DDoS capacity from a short connectivity test.

`L4LOAD_FILTER_LOAD=1` additionally measures 64-byte UDP at 1,000 allowed
messages/s, alternating no background traffic and 100,000 requested denied
messages/s for three repetitions. The YANET workflow runs both engines in the
same builder environment. Each allowed interval lasts five seconds inside a
longer denied-generator run; its reported average is not an exact ingress rate
for that interval. Results include achieved rates, drops, p99 and raw CSVs.
`FILTER_LOAD_OBSERVATION_COMPLETE` means data collection completed, not an SLO
pass. Shared CPU/generator contention, fixed engine order and short duration
limit interpretation.

[The corrected run completed](https://github.com/l4load/l4load/actions/runs/36177713642).
All twelve trials reported zero allowed-message loss; denied generators averaged
100,003–100,007 messages/s. Ranges below are the three per-run p99 RTT values,
not confidence intervals or saturation limits.

| Engine | No background, µs | Denied background, µs |
|---|---:|---:|
| nftables/IPVS | 42–44 | 45–75 |
| YANET AF_PACKET | 92–1003 | 510–1040 |

YANET's baseline varies substantially. These observations do not isolate the
cause of delay or establish physical-NIC performance or production superiority.
An earlier run captured packets only for YANET and is excluded from comparison.
[Raw samples and summaries](results/2026-09-25/) retain all twelve CSVs with hashes.

Upstream references: [timeouts](https://wiki.nftables.org/wiki-nftables/index.php/Element_timeouts),
[ingress families](https://wiki.nftables.org/wiki-nftables/index.php/Nftables_families),
[transactions](https://wiki.nftables.org/wiki-nftables/index.php/Atomic_rule_replacement).

`L4LOAD_SNAPSHOT_LOAD=1` adds 100,000 requested denied UDP messages/s to
each nonempty bulk update. The sentinel deny is installed before the generator;
each generator must remain alive across the update and finish successfully.
Logs retain its achieved whole-run rate, lifetime and update boundaries; these
do not establish the exact rate within the update. Empty-policy withdrawal runs
after generators exit. Useful traffic remains the sequential echo probe, not a
capacity test. The YANET workflow retains a separate no-load bulk pass.
