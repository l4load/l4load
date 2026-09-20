#!/usr/bin/env bash
set -euo pipefail
test "$EUID" = 0
test "$#" = 1
test ! -e /etc/l4load/ipvs.conf
profile=$(cd "$(dirname "$0")" && pwd)
/usr/sbin/keepalived -t -f "$1"
systemctl mask --now keepalived.service
install -D -m 600 "$1" /etc/l4load/ipvs.conf
install -D -m 644 "$profile/gate.py" /usr/local/libexec/l4load-ipvs-gate.py
install -D -m 644 "$profile/l4load-ipvs.service" /etc/systemd/system/l4load-ipvs.service
systemctl daemon-reload
