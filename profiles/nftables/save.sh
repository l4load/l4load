#!/usr/bin/env bash
set -euo pipefail
test "$EUID" = 0
test "$#" = 0
umask 077
nft -j list table netdev l4load | python3 -c '
import json, sys
def check(value):
    if isinstance(value, dict):
        assert not ({"timeout", "expires"} & value.keys()), "cannot persist expiring bans"
        for child in value.values(): check(child)
    elif isinstance(value, list):
        for child in value: check(child)
check(json.load(sys.stdin))
'
mkdir -p /etc/l4load
config=$(mktemp /etc/l4load/filter.nft.XXXXXX)
trap 'rm -f "$config"' EXIT
printf 'add table netdev l4load\ndelete table netdev l4load\n' > "$config"
nft list table netdev l4load >> "$config"
nft -c -f "$config"
mv "$config" /etc/l4load/filter.nft
profile=$(cd "$(dirname "$0")" && pwd)
install -m 644 "$profile/l4load-filter.service" /etc/systemd/system/l4load-filter.service
systemctl daemon-reload
