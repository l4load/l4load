# Balance: IPVS profile

An experimental IPv4 DSR profile using packaged Keepalived and Linux IPVS.
No DPDK or custom dataplane. The lifecycle lab consumes this exact
[configuration](keepalived.conf); it is not a separately maintained example.

The synthetic topology uses VIP `198.18.0.1:8080` for TCP/UDP and backends
`10.0.2.2` and `10.0.3.2`. Replace these addresses for an independent deployment.
Each backend must bind the VIP on loopback, receive IPIP traffic and route replies
directly to clients. Allow encapsulated traffic through the network and account
for tunnel MTU. With the lab's 1500-byte links, IPv4 IPIP leaves a 1480-byte
inner MTU (1452-byte UDP payload without IP options). The independent IPv6
trial leaves 1460/1412 bytes. Initial oversized datagrams produced `EMSGSIZE`;
a fresh-socket retry after the learned MTU delivered the tested sizes through
4000 bytes. This is not lossless first-packet delivery. Preserve PMTU feedback
and validate application error handling and both traffic directions; blocked
ICMP, other socket policies and arbitrary MTUs remain unqualified.
See [the recorded boundary/recovery trial](https://github.com/l4load/l4load/actions/runs/36137087795).

The director needs IPVS round-robin/IPIP kernel support, forwarding
and a route to each backend. Probe HTTP `/health` on port 9090 must return 200.
The installed units set `net.ipv4.vs.expire_quiescent_template=1` in their
network namespace. With client persistence, the kernel default (`0`) can keep
new flows pinned to a backend after its health check sets weight zero. This
setting moves new flows to a healthy backend; established flows retain their
existing destination. Use a dedicated IPVS network namespace.

Validate a candidate with `keepalived -t -f candidate.conf` before replacing the
working file. Use an atomic rename, signal HUP, then check `ipvsadm -Sn` and real
traffic; successful validation or signal delivery alone does not prove application.
Retain the last-good file for rollback through the same validated path.

Set a backend weight to zero for planned drain. Tests preserve established TCP
sessions, while fresh connections avoid it. A graceful `-I` controller stop retains
forwarding but also stale health decisions. The tested restart gates retained
destinations at weight zero before starting the controller and confirming healthy
kernel weights. New flows pause during that gate. See the [exact trial and failed
direct-restart evidence](../../lab/ipvs/README.md).

Reproduce on disposable Ubuntu 24.04 with `sudo bash lab/ipvs/run.sh` after the
lab prerequisites. Tested packages: Keepalived `1:2.2.8-1build2`,
ipvsadm `1:1.31-1ubuntu0.1`; every run records its actual kernel and versions.
A systemd unit with `Restart=on-failure` and the zero-weight startup gate passed
automatic recovery after main-process SIGKILL, with retained sessions and
healthy-only new flows. Startup from an empty IPVS table also passed, with the
network and packages already configured. Reboot, supported distribution upgrades, HA, capacity
and a real operator's acceptance remain open. This is not a production release.

## Installed service

[Qualification passed](https://github.com/l4load/l4load/actions/runs/36161652255):
the lab installed these exact files with only a network-namespace drop-in.
Automatic recovery, rejected reload, drain/rollback and empty-table startup
passed. Two retained TCP sessions carried 706 exchanges each over 35.6 seconds,
including service drain and rollback. This does not qualify host boot or a
package upgrade; packages and networking were prepared before installation.

A separate [VM trial](https://github.com/l4load/l4load/actions/runs/36167949921)
installed the profile and passed two reboots, with 64 fresh TCP/UDP flows after
each boot and no automatic service restarts. It uses QEMU TCG and an explicitly
ordered namespace topology service. This qualifies that lab's boot recipe;
physical network ordering and retained sessions through reboot remain unqualified.

The [unit](l4load-ipvs.service) and [restart gate](gate.py) are for a dedicated
IPVS director: the gate sets **every existing destination** to weight zero before
health checks resume. Do not share its network namespace with another IPVS owner.
Use Ubuntu 24.04, packaged Keepalived/IPVS, Python 3 and the network prerequisites
above. Stop any previous controller before transferring ownership.

On an independent prepared host, with a reviewed `candidate.conf`, run the
fresh-install script below. It rejects an existing `/etc/l4load/ipvs.conf`,
validates the candidate before changes, masks the packaged service and installs
the profile without starting or enabling it:

```sh
sudo bash profiles/ipvs/install.sh candidate.conf
sudo systemctl start l4load-ipvs
```

Check kernel weights, health and traffic before enabling boot startup with
`systemctl enable l4load-ipvs`. Boot/network ordering is not yet qualified.
Keep the last-good configuration outside the active path. To update or roll back,
run `sudo bash profiles/ipvs/update.sh candidate.conf`. Use a self-contained
configuration, as in this profile; external includes and concurrent manual edits
are outside this recipe. The helper locks concurrent helper calls, validates a
private copy before atomic replacement and restores the previous file if reload
fails. A successful reload only confirms signal delivery: verify kernel weights,
health and traffic, and use the same command with the last-good file if needed.
Directly overwriting the active file bypasses this protection. Host reboots remain unqualified;
the separate package trial below covers only its exact versions and environment.

The packaged service must stay masked while this profile owns IPVS: package
maintainer scripts target `keepalived.service`. A one-time stop is insufficient.
The package-lifecycle trial reinstalls the same recorded `.deb` under traffic,
checks that the mask survives and the custom controller PID is unchanged, then
explicitly restarts the custom service through its gate.
[This passed](https://github.com/l4load/l4load/actions/runs/36164628266) with
Keepalived `1:2.2.8-1build2`: the mask survived, the packaged service could not
start, and two retained TCP sessions carried 777 exchanges each over 39.2 seconds.
New flows passed after reinstall and explicit restart. This is not a cross-version
upgrade test. Preserve the prior package and config
before a separately qualified version change.

A [cross-version trial](https://github.com/l4load/l4load/actions/runs/36165653126)
passed `1:2.2.8-1build2` → `1:2.3.2-1` → `1:2.2.8-1build2` on the prepared
Ubuntu 24.04 runner. Dependency simulation changed only Keepalived. After each
install, the packaged service stayed masked; an explicit gated restart loaded
the installed executable and fresh TCP/UDP flows passed. Two retained TCP
sessions carried 913 exchanges each over 46.1 seconds through the lifecycle.
The newer package came from another Ubuntu release: this demonstrates the tested
upgrade/rollback mechanics, not a supported Noble update or arbitrary version
compatibility. Keep the default package; do not use this trial as an upgrade recommendation.

## Integrated HA pair

On each dedicated director, prepare one reviewed, self-contained Keepalived
configuration with the `virtual_server` checks above, a VRRP instance on a shared
L2 next-hop and an external script that tests real TCP/UDP forwarding. Use
`lvs_sync_daemon <sync-interface> inst <VRRP-instance> id <same-id>` on a separate
sync link. Both nodes need the same VIP, VRID and sync ID, different
priorities, independent backend health checks and working IPIP return paths.
The [synthetic pair](../../lab/cutover/vrrp.sh) generates tested example files;
its namespace probe and addresses must be replaced for a real deployment.
[The installed-pair result](../../lab/cutover/results/2026-09-26-installed-ha.json)
records the exact virtual run and limits.

On each prepared node, without an existing `l4load-ipvs` installation or active
packaged Keepalived service:

```sh
sudo bash profiles/ipvs/install-ha.sh director candidate.conf
sudo systemctl start l4load-ha@director
sudo ipvsadm -Sn
sudo ipvsadm -Ln --daemon
```

Verify one VIP owner, both kernel tables, backend exclusion/recovery and real
traffic before enabling boot startup. Keep the last-good configuration. Apply
or roll back with `sudo bash profiles/ipvs/update-ha.sh director candidate.conf`,
then recheck ownership, IPVS weights, sync roles and traffic. A rejected candidate
leaves the active file intact; a failed reload restores it, but the operator
must still verify runtime state. Stop the primary service for planned handoff;
confirm the standby owns the next-hop and serves traffic before maintenance.
Physical L2, network startup, sync-loss policy, sustained load and operator
acceptance remain unqualified.

[A sync-loss trial](../../lab/cutover/results/2026-09-26-sync-loss.json) cut both
sync links before opening a TCP connection, then failed primary forwarding.
The backup took the VIP and fresh TCP/UDP recovered in 3.58 seconds, but that
unsynced connection reset. Treat sync-link health and retained-session loss as
an explicit pilot risk; VRRP failover alone cannot preserve state it never received.

[A fresh-flow observation](../../lab/cutover/results/2026-09-26-ha-useful.json)
recorded 13 failed attempts per protocol during an automatic handoff and none
before or after it. Sequential probe timeouts reduced the offered rate during
the fault; this short virtual run is not a capacity or loss-rate qualification.

## Routed pair trial

The separate [BGP lab](../../lab/bgp/README.md) tests two BIRD/IPVS directors.
For a dedicated IPv4 director with one VIP, prepare a reviewed non-VRRP
Keepalived config with TCP/UDP services. Prepare a link to the other director for IPVS
state sync and an executable probe that sends real TCP/UDP traffic through
this director's forwarding path. A loopback-only check is insufficient.

Create a JSON file with `vip`, `local_ip`, `local_as`, `peer_ip`, `peer_as`,
`sync_interface` and `sync_id`; the peer must be a directly connected BFD/BGP
neighbor. Install without starting or enabling the unit:

```sh
sudo python3 profiles/ipvs/install-routed.py director candidate.json check-forwarding candidate-ipvs.conf
sudo systemctl start l4load-routed@director
```

The installer rejects an existing profile for this instance, validates addresses,
Keepalived and BIRD syntax, generates a disabled VIP static route and masks the
packaged BIRD and Keepalived services. The unit starts its matching
`l4load-ipvs@director.service`; its supervisor runs
BIRD, both native IPVS sync roles and the forwarding/BFD route gate. The gate
advertises only after two healthy probes. Check route state, both sync daemons,
backend health and real traffic on both directors before enabling startup.
The gate confirms a failed check immediately and withdraws after two
consecutive failures. A single missed probe alone does not change the route;
calibrate detection against the loss budget.
Update or restore the IPVS config with
`sudo bash profiles/ipvs/update.sh candidate-ipvs.conf director`, then check
both routes, kernel weights and real traffic. A failed reload restores the
previous file; operator validation of runtime state is still required.
The [virtual pair trial](../../lab/bgp/results/2026-09-26-installed-pair.json)
covers installation, failover, unit restarts, drain and rollback. It does not
qualify physical links, capacity or a production SLO.
The [installed sync-loss trial](../../lab/bgp/results/2026-09-26-installed-sync-loss.json)
shows that the standby can remain advertised without current connection state:
one established TCP connection reset after primary loss, while fresh TCP/UDP
flows passed. The unit logs sync-link carrier transitions to its service output;
this is not proof of connection-state freshness. Monitor those events and agree
on session loss versus fresh availability before using the routed profile.
