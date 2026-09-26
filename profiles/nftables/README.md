# Native IPv4 filter

An experimental nftables profile for temporary source/VIP bans before IPVS.
The [lab](../../lab/filter) consumes this exact configuration. It uses a separate
`netdev l4load` table and does not flush the host ruleset.

On an independent Linux host with nftables, copy `filter.nft` and replace `eth0`
with the ingress interface. The table must not already exist: loading the file
again can append rules. Start with an empty set, validate, then apply:

```sh
sudo nft -c -f filter.nft
sudo nft -f filter.nft
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

This adds no IPv6 policy or automatic persistence. Reboot, prefixes, tenant
isolation, fragments and overload capacity remain unqualified. Other firewall
chains can still drop traffic allowed here. This is not a complete DDoS product.
