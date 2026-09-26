#!/usr/bin/env bash
set -euo pipefail
test "$EUID" = 0
test "$#" = 1
[[ "$1" =~ ^[a-zA-Z0-9_.:-]+$ ]]
ip link show dev "$1" >/dev/null
nft -j list tables | python3 -c '
import json, sys
assert not any(row.get("table", {}).get("family") == "netdev" and
               row["table"]["name"] == "l4load" for row in json.load(sys.stdin)["nftables"]), "l4load table already exists"
'
profile=$(cd "$(dirname "$0")" && pwd)
config=$(mktemp)
trap 'rm -f "$config"' EXIT
sed "s/device \"eth0\"/device \"$1\"/" "$profile/filter.nft" > "$config"
nft -c -f "$config"
nft -f "$config"
