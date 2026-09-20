#!/usr/bin/env bash
set -euo pipefail
cd /opt/l4load
modprobe ip_vs_rr
modprobe ipip
for ns in client router lb b1 b2; do
    ip netns add "l4-$ns"
    ip -n "l4-$ns" link set lo up
    ip netns exec "l4-$ns" sysctl -qw net.ipv4.conf.all.rp_filter=0 net.ipv4.conf.default.rp_filter=0
done
subnet=0
for ns in client lb b1 b2; do
    ip link add "r$subnet" type veth peer name eth0 netns "l4-$ns"
    ip link set "r$subnet" netns l4-router
    ip -n l4-router addr add "10.0.$subnet.1/24" dev "r$subnet"
    ip -n l4-router link set "r$subnet" up
    ip -n "l4-$ns" addr add "10.0.$subnet.2/24" dev eth0
    ip -n "l4-$ns" link set eth0 up
    ip -n "l4-$ns" route add default via "10.0.$subnet.1"
    subnet=$((subnet + 1))
done
ip netns exec l4-router sysctl -qw net.ipv4.ip_forward=1
ip -n l4-router route add 198.18.0.1/32 via 10.0.1.2
ip -n l4-lb addr add 198.18.0.1/32 dev lo
ip netns exec l4-lb sysctl -qw net.ipv4.ip_forward=1
for n in 1 2; do
    ip -n "l4-b$n" tunnel add decap mode ipip local "10.0.$((n+1)).2"
    ip -n "l4-b$n" link set decap up
    ip -n "l4-b$n" addr add 198.18.0.1/32 dev lo
    ip netns exec "l4-b$n" python3 lab/katran/scenario.py serve "b$n" &
    ip netns exec "l4-b$n" python3 -m http.server 9090 --directory /opt/l4load/lab/boot --bind "10.0.$((n+1)).2" &
done
