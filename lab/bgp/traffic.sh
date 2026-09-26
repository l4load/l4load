for module in ip_vs ip_vs_rr ipip; do modprobe "$module"; done
dpkg-query -W ipvsadm nftables >> "$out/packages.txt"
for ns in l4-client l4-b1 l4-p1 l4-p2; do
    ip netns add "$ns"
    ip -n "$ns" link set lo up
done
for ns in l4-r l4-d1 l4-d2 l4-client l4-b1 l4-p1 l4-p2; do
    ip netns exec "$ns" sysctl -qw net.ipv4.conf.all.rp_filter=0 net.ipv4.conf.default.rp_filter=0
done
ip netns exec l4-r sysctl -qw net.ipv4.ip_forward=1
connect_router() {
    local ns=$1 subnet=$2
    ip link add "c$subnet" type veth peer name eth0 netns "$ns"
    ip link set "c$subnet" netns l4-r
    ip -n l4-r addr add "10.0.$subnet.1/24" dev "c$subnet"
    ip -n "$ns" addr add "10.0.$subnet.2/24" dev eth0
    ip -n l4-r link set "c$subnet" up
    ip -n "$ns" link set eth0 up
    ip -n "$ns" route add default via "10.0.$subnet.1"
}
connect_router l4-client 0
connect_router l4-b1 2
ip -n l4-b1 tunnel add decap mode ipip local 10.0.2.2
ip -n l4-b1 link set decap up
ip -n l4-b1 addr add 198.18.0.1/32 dev lo
ip netns exec l4-b1 python3 -u lab/katran/scenario.py serve b1 > "$out/backend.log" 2>&1 &
pids+=("$!")
for n in 1 2; do
    ip -n "l4-d$n" route add default via "10.1.$n.1"
    ip -n "l4-d$n" addr add 198.18.0.1/32 dev lo
    ip netns exec "l4-d$n" sysctl -qw net.ipv4.ip_forward=1
    for proto in -t -u; do
        ip netns exec "l4-d$n" ipvsadm -A "$proto" 198.18.0.1:8080 -s rr
        ip netns exec "l4-d$n" ipvsadm -a "$proto" 198.18.0.1:8080 -r 10.0.2.2:8080 -i
    done
    ip link add "dp$n" type veth peer name eth0 netns "l4-p$n"
    ip link set "dp$n" netns "l4-d$n"
    ip -n "l4-d$n" addr add "10.2.$n.1/30" dev "dp$n"
    ip -n "l4-p$n" addr add "10.2.$n.2/30" dev eth0
    ip -n "l4-d$n" link set "dp$n" up
    ip -n "l4-p$n" link set eth0 up
    ip -n "l4-p$n" route add default via "10.2.$n.1"
    ip -n l4-r route add "10.2.$n.0/30" via "10.1.$n.2"
    ip netns exec "l4-d$n" ipvsadm -Sn > "$out/ipvs$n.txt"
done
for ns in l4-r l4-d1 l4-d2 l4-client l4-b1 l4-p1 l4-p2; do
    ip netns exec "$ns" sh -c 'for f in /proc/sys/net/ipv4/conf/*/rp_filter; do echo 0 > "$f"; done'
done
for n in 1 2; do
    ip netns exec "l4-d$n" sysctl -qw net.ipv4.conf.eth0.accept_local=1
done
for ns in l4-r l4-d1 l4-b1 l4-p1; do
    ip netns exec "$ns" tcpdump -i any -nn -l -U 'host 198.18.0.1 or host 10.2.1.2' > "$out/capture-$ns.log" 2>&1 &
    pids+=("$!")
done
for n in 1 2; do
    for attempt in $(seq 1 3); do
        if ip netns exec "l4-p$n" python3 lab/filter/probe.py "10.2.$n.2" pass > "$out/probe$n.jsonl" 2>&1; then break; fi
        sleep 0.1
    done
    ip netns exec "l4-d$n" ipvsadm -Ln --stats > "$out/stats$n.txt"
    grep -q '"status": "pass"' "$out/probe$n.jsonl"
done
ip netns exec l4-client python3 lab/katran/scenario.py check b1 > "$out/traffic-baseline.json"
for n in 1 2; do
    python3 -u lab/bgp/health.py "l4-p$n" "10.2.$n.2" "$out/d$n.ctl" "vip$n" > "$out/health$n.jsonl" 2>&1 &
    pids+=("$!")
done
sleep 1
ip netns exec l4-d1 nft add table inet fault
ip netns exec l4-d1 nft add chain inet fault ingress '{ type filter hook prerouting priority -300; policy accept; }'
python3 -c 'import time; print(time.monotonic())' > "$out/traffic-fault-start.txt"
ip netns exec l4-d1 nft add rule inet fault ingress ip daddr 198.18.0.1 counter drop
wait_route 10.1.2.2 health-withdrawn
ip netns exec l4-client python3 lab/katran/scenario.py check b1 > "$out/traffic-failover.json"
ip netns exec l4-d1 nft -a list table inet fault > "$out/fault-counters.txt"
ip netns exec l4-d1 nft delete table inet fault
wait_route 10.1.1.2 health-restored
ip netns exec l4-client python3 lab/katran/scenario.py check b1 > "$out/traffic-restored.json"
for n in 1 2; do ip netns exec "l4-d$n" ipvsadm -Sn > "$out/ipvs$n-final.txt"; done
echo BGP_HEALTH_TRAFFIC_PASS
