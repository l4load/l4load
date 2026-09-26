# Balance with an ingress filter

Experimental IPv4 IPVS/IPIP balancing with nftables source/VIP denies, without
DPDK. Start on a dedicated, independently prepared Ubuntu 24.04 director.
Follow the [Balance prerequisites](ipvs/README.md) for kernel support, backend
tunnels, return routing, MTU and health endpoints. This does not provision the
network or qualify a production deployment.

Prepare a reviewed `candidate.conf`, an authoritative `pairs.json`, and an ingress
interface. Keep previous configurations outside the active paths. Fresh install:

```sh
sudo bash profiles/nftables/install.sh eth0
sudo python3 profiles/nftables/snapshot.py < pairs.json
sudo bash profiles/nftables/save.sh
sudo bash profiles/ipvs/install.sh candidate.conf
sudo mkdir -p /etc/systemd/system/l4load-ipvs.service.d
```

Create `/etc/systemd/system/l4load-ipvs.service.d/filter.conf` with:

```ini
[Unit]
Requires=l4load-filter.service
After=l4load-filter.service
```

Run `sudo systemctl daemon-reload`, then `sudo systemctl start l4load-ipvs`.
The dependency starts the saved filter first. Verify healthy IPVS destinations,
allowed TCP/UDP replies, denied-source timeouts and source-IP preservation from
an independent client. Check backend exclusion/recovery and application MTU
behaviour. Enable both units for boot only after these checks and after qualifying
interface readiness; `network-online.target` is not proof of every host's ordering.

For Balance changes or rollback, use `profiles/ipvs/update.sh` with the reviewed
new or previous configuration, then recheck kernel state and real traffic.
For policy changes or rollback, apply the reviewed new or previous pair list with
`snapshot.py`. Save explicitly only after verification: runtime updates and the
boot policy are separate. `systemctl reload l4load-filter` restores the saved
policy; a valid empty list removes bans. See [HTTPS delivery and persistence
semantics](nftables/README.md), including single-writer and nonexpiring-save limits.

To withdraw, stop and disable Balance, disable the filter unit, then delete only
`table netdev l4load` after reviewing the resulting exposure. Stopping Balance
retains IPVS forwarding by design: withdraw the VIP route and explicitly remove
its IPVS services as part of your network rollback. Do not transfer ownership to
another controller until that is complete; the packaged service remains masked.

[Two VM reboots and policy rollback passed](https://github.com/l4load/l4load/actions/runs/36227587895)
with explicit synthetic network ordering. This is not physical-host acceptance,
automatic HA, IPv6 filtering, a throughput ceiling or session continuity across
reboot. The separate load observations define tested scenarios, not a production SLO.
