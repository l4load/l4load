#!/usr/bin/env bash
set -euo pipefail
test "$EUID" = 0
test "$#" = 1
exec 9>/run/l4load-ipvs-update.lock
flock -n 9
active=/etc/l4load/ipvs.conf
test -f "$active"
systemctl is-active --quiet l4load-ipvs
stage=$(mktemp -d /etc/l4load/update.XXXXXX)
trap 'rm -rf "$stage"' EXIT
install -m 600 "$1" "$stage/next.conf"
/usr/sbin/keepalived -t -f "$stage/next.conf"
cp -p "$active" "$stage/previous.conf"
mv "$stage/next.conf" "$active"
if ! systemctl reload l4load-ipvs; then
    mv "$stage/previous.conf" "$active"
    systemctl reload l4load-ipvs || true
    echo 'reload failed; previous file restored; verify service and traffic' >&2
    exit 1
fi
