#!/usr/bin/env bash
set -euo pipefail
cd /opt/l4load
apt-get update
apt-get install -y --no-install-recommends keepalived ipvsadm nftables
bash profiles/ipvs/install.sh profiles/ipvs/keepalived.conf
echo healthy > lab/boot/health
cat > /etc/systemd/system/l4load-lab-network.service <<'UNIT'
[Unit]
Before=l4load-ipvs.service
[Service]
Type=oneshot
RemainAfterExit=yes
ExecStart=/bin/bash /opt/l4load/lab/boot/network.sh
[Install]
WantedBy=multi-user.target
UNIT
mkdir -p /etc/systemd/system/l4load-ipvs.service.d
cat > /etc/systemd/system/l4load-ipvs.service.d/lab.conf <<'UNIT'
[Unit]
Requires=l4load-lab-network.service l4load-filter.service
After=l4load-lab-network.service l4load-filter.service
[Service]
NetworkNamespacePath=/run/netns/l4-lb
UNIT
systemctl daemon-reload
systemctl start l4load-lab-network.service
ip netns exec l4-lb bash profiles/nftables/install.sh eth0
echo '[["10.0.0.3", "198.18.0.1"]]' | ip netns exec l4-lb python3 profiles/nftables/snapshot.py
ip netns exec l4-lb bash profiles/nftables/save.sh
mkdir -p /etc/systemd/system/l4load-filter.service.d
cat > /etc/systemd/system/l4load-filter.service.d/lab.conf <<'UNIT'
[Unit]
Requires=l4load-lab-network.service
After=l4load-lab-network.service
[Service]
NetworkNamespacePath=/run/netns/l4-lb
UNIT
systemctl daemon-reload
systemctl enable l4load-filter.service
systemctl enable l4load-ipvs.service
