#!/usr/bin/env bash
set -euo pipefail
cd /opt/l4load
cat /proc/sys/kernel/random/boot_id
date -u +%FT%TZ
uname -a
dpkg-query -W keepalived ipvsadm
test "$(systemctl is-enabled keepalived.service)" = masked
systemctl is-active --quiet l4load-ipvs
for attempt in $(seq 1 30); do
    if ip netns exec l4-lb ipvsadm -Sn | python3 -c 'import sys; r=[x.split() for x in sys.stdin if x.startswith("-a ")]; sys.exit(not(len(r)==4 and all(x[x.index("-w")+1]=="1" for x in r)))'; then break; fi
    sleep 1
done
ip netns exec l4-client python3 lab/katran/scenario.py check b1,b2 20000
systemctl show l4load-ipvs -p ActiveState -p MainPID -p NRestarts
ip netns exec l4-lb ipvsadm -Sn
echo BOOT_TRAFFIC_PASS
