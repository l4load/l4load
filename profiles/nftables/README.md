# Native IPv4 filter

An experimental nftables profile for temporary source/VIP bans before IPVS.
The [lab](../../lab/filter) consumes this exact configuration. It uses a separate
`netdev l4load` table and does not flush the host ruleset.

On an independent Linux host with nftables, iproute2 and Python, install the
profile on the reviewed ingress interface. Installation refuses an existing
table and validates the configuration before applying it. It starts empty:

```sh
sudo bash install.sh eth0
sudo nft list table netdev l4load
```

Add an IPv4 source/VIP pair with explicit expiry; substitute reviewed addresses:

```sh
sudo nft 'add element netdev l4load blocked { 10.0.0.3 . 198.18.0.1 timeout 5m }'
sudo nft list set netdev l4load blocked
sudo nft 'delete element netdev l4load blocked { 10.0.0.3 . 198.18.0.1 }'
```

Verify denied and unaffected traffic, not only command success. The pair covers
the VIP's IPv4 traffic, not a specific port. Expiry proceeds without a controller;
deleting an already expired element reports absence. For a batch, use one
`nft -f changes.nft` transaction. Never add `flush ruleset` to that file.
To withdraw this entire profile, use `sudo nft delete table netdev l4load`.

For an authoritative full snapshot, run `sudo python3 snapshot.py < pairs.json`,
where the JSON is a list such as `[["10.0.0.3", "198.18.0.1"]]`. The helper
validates the complete input before replacing the set in one transaction.
Duplicates collapse; `[]` removes all bans. These entries do not expire.
Use one writer: concurrent snapshots have last-applied-wins semantics, with no
version ordering or reconnect transport supplied by this helper.

`sudo bash pull.sh https://policy.example/pairs.json` fetches one authoritative
snapshot and applies it only after a successful complete download and validation.
It requires curl, Python and nft, an installed table, and a trusted HTTPS source.
Certificate verification stays enabled; redirects are not followed. Fetches are
bounded to 10 seconds and 16 MiB. A transport or validation failure keeps the
last applied set; a valid empty list removes all bans. Retry explicitly after
recovery. This is a one-shot pull, not a daemon: use one writer and supply source
freshness, authorization and scheduling externally. Old rules can persist during
an outage; choose this behaviour deliberately. Reboot persistence is unchanged.

For explicit boot persistence of reviewed **nonexpiring** rules, run
`sudo bash profiles/nftables/save.sh` after applying and checking the policy.
It validates and atomically saves this table to `/etc/l4load/filter.nft`, installs
`l4load-filter.service`, and rejects expiring elements rather than renewing their
lifetimes at every boot. Keep one writer during saving. Later pulls change only
runtime state: save explicitly to change the boot policy. A saved empty set
restores an empty set. Preserve the previous file for rollback.

Run `sudo systemctl start l4load-filter` and check allowed/denied traffic before
`sudo systemctl enable l4load-filter`. Reload restores the saved table in one nft
transaction; invalid input leaves live rules unchanged. Stopping the unit retains
rules. For withdrawal, disable it before deleting the table. The interface must
exist at startup; `network-online.target` alone does not prove this on every host.
When pairing with Balance, add `Requires=l4load-filter.service` and
`After=l4load-filter.service` in its unit's `[Unit]` drop-in so a failed filter
startup prevents Balance startup. This does not monitor later filter changes or
stop already-running forwarding. The combined VM boot test is pending qualification.

This adds no IPv6 policy. Physical-host boot ordering, prefixes, tenant
isolation, fragments and overload capacity remain unqualified. Other firewall
chains can still drop traffic allowed here. This is not a complete DDoS product.
