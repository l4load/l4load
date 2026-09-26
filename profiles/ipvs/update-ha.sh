#!/usr/bin/env bash
set -euo pipefail
test "$EUID" = 0
test "$#" = 2
[[ "$1" =~ ^[a-z0-9-]+$ ]]
instance=$1
active="/etc/l4load/ha-$instance.conf"
unit="l4load-ha@$instance.service"
exec 9>"/run/l4load-ha-$instance-update.lock"
flock -n 9
test -f "$active"
systemctl is-active --quiet "$unit"
stage=$(mktemp -d /etc/l4load/update.XXXXXX)
trap 'rm -rf "$stage"' EXIT
install -m 600 "$2" "$stage/next.conf"
/usr/sbin/keepalived -t -f "$stage/next.conf"
cp -p "$active" "$stage/previous.conf"
mv "$stage/next.conf" "$active"
if ! systemctl reload "$unit"; then
    mv "$stage/previous.conf" "$active"
    systemctl reload "$unit" || true
    echo 'reload failed; previous file restored; verify service and traffic' >&2
    exit 1
fi
