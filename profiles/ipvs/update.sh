#!/usr/bin/env bash
set -euo pipefail
test "$EUID" = 0
test "$#" -ge 1 && test "$#" -le 2
instance=${2:-}
if [ -n "$instance" ]; then [[ "$instance" =~ ^[a-z0-9-]+$ ]]; fi
exec 9>"/run/l4load-ipvs-update${instance:+-$instance}.lock"
flock -n 9
active="/etc/l4load/ipvs${instance:+-$instance}.conf"
unit="l4load-ipvs${instance:+@$instance}.service"
test -f "$active"
systemctl is-active --quiet "$unit"
stage=$(mktemp -d /etc/l4load/update.XXXXXX)
trap 'rm -rf "$stage"' EXIT
install -m 600 "$1" "$stage/next.conf"
/usr/sbin/keepalived -t -f "$stage/next.conf"
cp -p "$active" "$stage/previous.conf"
mv "$stage/next.conf" "$active"
if ! systemctl reload "$unit"; then
    mv "$stage/previous.conf" "$active"
    systemctl reload "$unit" || true
    echo 'reload failed; previous file restored; verify service and traffic' >&2
    exit 1
fi
