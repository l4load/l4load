#!/usr/bin/env bash
set -euo pipefail
test "$EUID" = 0
test "$#" = 2
[[ "$1" =~ ^[a-z0-9-]+$ ]]
test ! -e /etc/l4load/ipvs.conf
test ! -e "/etc/l4load/ha-$1.conf"
test "$(systemctl show l4load-ipvs.service -p ActiveState --value)" != active
profile=$(cd "$(dirname "$0")" && pwd)
/usr/sbin/keepalived -t -f "$2"
systemctl mask --now keepalived.service
install -D -m 600 "$2" "/etc/l4load/ha-$1.conf"
install -D -m 644 "$profile/gate.py" /usr/local/libexec/l4load-ipvs-gate.py
install -D -m 644 "$profile/l4load-ha@.service" /etc/systemd/system/l4load-ha@.service
systemctl daemon-reload
