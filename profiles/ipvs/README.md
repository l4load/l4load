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
network and packages already configured. Reboot, package upgrades, HA, capacity
and a real operator's acceptance remain open. This is not a production release.

## Installed service

[Qualification passed](https://github.com/l4load/l4load/actions/runs/36161652255):
the lab installed these exact files with only a network-namespace drop-in.
Automatic recovery, rejected reload, drain/rollback and empty-table startup
passed. Two retained TCP sessions carried 706 exchanges each over 35.6 seconds,
including service drain and rollback. This does not qualify host boot or a
package upgrade; packages and networking were prepared before installation.

The [unit](l4load-ipvs.service) and [restart gate](gate.py) are for a dedicated
IPVS director: the gate sets **every existing destination** to weight zero before
health checks resume. Do not share its network namespace with another IPVS owner.
Use Ubuntu 24.04, packaged Keepalived/IPVS, Python 3 and the network prerequisites
above. Stop any previous controller before transferring ownership.

On an independent prepared host, with a reviewed `candidate.conf`:

```sh
sudo keepalived -t -f candidate.conf
sudo install -D -m 600 candidate.conf /etc/l4load/ipvs.conf
sudo install -D -m 644 profiles/ipvs/gate.py /usr/local/libexec/l4load-ipvs-gate.py
sudo install -D -m 644 profiles/ipvs/l4load-ipvs.service /etc/systemd/system/l4load-ipvs.service
sudo systemctl daemon-reload
sudo systemctl start l4load-ipvs
```

Check kernel weights, health and traffic before enabling boot startup with
`systemctl enable l4load-ipvs`. Boot/network ordering is not yet qualified.
Keep the last-good configuration outside the active path. To update or roll back,
validate the chosen file, install it as `/etc/l4load/next.conf`, rename it to
`/etc/l4load/ipvs.conf`, then `systemctl reload l4load-ipvs`. The unit validates
again before signalling; rejection leaves the running configuration unchanged,
but the invalid file must be replaced before a later restart. Verify applied
kernel state and traffic after either operation. Package upgrades and host
reboots remain separate unqualified steps.
