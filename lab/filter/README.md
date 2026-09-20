# Filter lifecycle trial

On a disposable Ubuntu 24.04 runner with the IPVS lab prerequisites and nftables,
run `sudo env L4LOAD_FILTER=1 bash lab/ipvs/run.sh`.

Native nftables ingress filtering matches an IPv4 source/VIP pair before IPVS.
The trial checks TCP/UDP forwarding, a temporary deny with kernel drop counters,
unaffected traffic from another source, rejection of an invalid transaction,
expiry without a controller and table removal. `FILTER_LIFECYCLE_PASS` requires
all checks; results are in `lab/results/ipvs`.

[The nftables trial passed](https://github.com/l4load/l4load/actions/runs/36172967453).
[YANET passed the same deny/allow probes](https://github.com/l4load/l4load/actions/runs/36174467560),
including rejected reload and explicit rollback. Only nftables expiry was tested;
these results establish neither equivalent full features nor a performance winner.

This is an experiment, not a Shield release. Prefixes, IPv6, fragments, tenant
isolation, reboot persistence, overload and comparison with YANET are unqualified.
Do not infer DDoS capacity from a short connectivity test.

Upstream references: [timeouts](https://wiki.nftables.org/wiki-nftables/index.php/Element_timeouts),
[ingress families](https://wiki.nftables.org/wiki-nftables/index.php/Nftables_families),
[transactions](https://wiki.nftables.org/wiki-nftables/index.php/Atomic_rule_replacement).
