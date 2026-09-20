#!/usr/bin/env bash
set -euo pipefail
cd /opt/l4load
apt-get update
apt-get install -y --no-install-recommends keepalived ipvsadm
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
Requires=l4load-lab-network.service
After=l4load-lab-network.service
[Service]
NetworkNamespacePath=/run/netns/l4-lb
UNIT
systemctl daemon-reload
systemctl enable l4load-ipvs.service
