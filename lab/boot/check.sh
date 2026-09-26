#!/usr/bin/env bash
set -euo pipefail
cd /opt/l4load
cat /proc/sys/kernel/random/boot_id
date -u +%FT%TZ
uname -a
dpkg-query -W keepalived ipvsadm
test "$(systemctl is-enabled keepalived.service)" = masked
systemctl is-active --quiet l4load-ipvs
systemctl is-active --quiet l4load-filter
ready=false
for attempt in $(seq 1 30); do
    if ip netns exec l4-lb ipvsadm -Sn | python3 -c 'import sys; r=[x.split() for x in sys.stdin if x.startswith("-a ")]; sys.exit(not(len(r)==4 and all(x[x.index("-w")+1]=="1" for x in r)))'; then ready=true; break; fi
    sleep 1
done
test "$ready" = true
ip netns exec l4-client python3 lab/katran/scenario.py check b1,b2 20000
ip netns exec l4-client python3 lab/filter/probe.py 10.0.0.3 drop
ip netns exec l4-client python3 lab/filter/probe.py 10.0.0.2 pass
echo '[]' | ip netns exec l4-lb python3 profiles/nftables/snapshot.py
ip netns exec l4-client python3 lab/filter/probe.py 10.0.0.3 pass
systemctl reload l4load-filter
ip netns exec l4-client python3 lab/filter/probe.py 10.0.0.3 drop
ip netns exec l4-client python3 lab/filter/probe.py 10.0.0.2 pass
cp /etc/l4load/filter.nft /tmp/filter-good.nft
ip netns exec l4-lb nft 'add element netdev l4load blocked { 10.0.0.4 . 198.18.0.1 timeout 2m }'
if ip netns exec l4-lb bash profiles/nftables/save.sh; then exit 1; fi
cmp /etc/l4load/filter.nft /tmp/filter-good.nft
echo 'invalid nft input' > /etc/l4load/filter.nft
if systemctl reload l4load-filter; then exit 1; fi
ip netns exec l4-client python3 lab/filter/probe.py 10.0.0.3 drop
ip netns exec l4-client python3 lab/filter/probe.py 10.0.0.2 pass
mv /tmp/filter-good.nft /etc/l4load/filter.nft
systemctl reload l4load-filter
echo FILTER_BOOT_ROLLBACK_PASS
systemctl show l4load-ipvs -p ActiveState -p MainPID -p NRestarts
ip netns exec l4-lb ipvsadm -Sn
echo BOOT_TRAFFIC_PASS
