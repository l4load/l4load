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
for n in 1 2; do
    for attempt in $(seq 1 3); do
        if ip netns exec "l4-p$n" python3 lab/filter/probe.py "10.2.$n.2" pass > "$out/probe$n.jsonl" 2>&1; then break; fi
        sleep 0.1
    done
    grep -q '"status": "pass"' "$out/probe$n.jsonl"
done
ip netns exec l4-client python3 lab/katran/scenario.py check b1 > "$out/traffic-baseline.json"
for n in 1 2; do
    if [ "${L4LOAD_BGP_TRAFFIC:-1}" = 3 ]; then
        python3 -u lab/bgp/health.py bfd "10.1.$n.1" "$out/d$n.ctl" "vip$n" > "$out/health$n.jsonl" 2>&1 &
    else
        python3 -u lab/bgp/health.py "l4-p$n" "10.2.$n.2" "$out/d$n.ctl" "vip$n" > "$out/health$n.jsonl" 2>&1 &
    fi
    pids+=("$!")
done
phase() {
    printf '%s\n' "$1" > "$out/useful-phase.next"
    mv "$out/useful-phase.next" "$out/useful-phase"
}
phase baseline
if [ "${L4LOAD_BGP_TRAFFIC:-1}" = 4 ]; then
    source lab/bgp/sync.sh
    ip netns exec l4-client python3 -u lab/bgp/session.py "$out" > "$out/session.log" 2>&1 &
    session_pid=$!
    pids+=("$session_pid")
    for attempt in $(seq 1 100); do test -e "$out/session-baseline" && break; sleep 0.1; done
    test -e "$out/session-baseline"
    sync_ready l4-d1 l4-d2 failover
fi
traffic_script=lab/cutover/useful.py
if [ "${L4LOAD_BGP_TRAFFIC:-1}" -ge 2 ]; then traffic_script=lab/bgp/offered.py; fi
for protocol in tcp udp; do
    ip netns exec l4-client python3 -u "$traffic_script" "$out" "$protocol" > "$out/useful-$protocol.log" 2>&1 &
    pids+=("$!")
    if [ "$protocol" = tcp ]; then useful_tcp=$!; else useful_udp=$!; fi
done
sleep 2
ps -C bird -o pid,rss,vsz,time > "$out/bird-baseline.txt"
fault_ns=l4-d1
if [ "${L4LOAD_BGP_TRAFFIC:-1}" = 3 ]; then fault_ns=l4-r; fi
ip netns exec "$fault_ns" nft add table inet fault
ip netns exec "$fault_ns" nft add chain inet fault ingress '{ type filter hook prerouting priority -300; policy accept; }'
if [ "$fault_ns" = l4-r ]; then
    ip netns exec l4-d1 nft add table inet fault
    ip netns exec l4-d1 nft add chain inet fault ingress '{ type filter hook prerouting priority -300; policy accept; }'
fi
python3 -c 'import time; print(time.monotonic())' > "$out/traffic-fault-start.txt"
phase fault
if [ "$fault_ns" = l4-r ]; then
    ip netns exec l4-r nft add rule inet fault ingress iifname r1 udp dport 3784 counter drop
    ip netns exec l4-d1 nft add rule inet fault ingress iifname eth0 udp dport 3784 counter drop
else
    ip netns exec l4-d1 nft add rule inet fault ingress ip daddr 198.18.0.1 counter drop
fi
wait_route 10.1.2.2 health-withdrawn
if [ "$fault_ns" = l4-r ]; then birdc -s "$out/router.ctl" 'show bfd sessions' > "$out/bfd-withdrawn.txt"; fi
phase failover
if [ "${L4LOAD_BGP_TRAFFIC:-1}" = 4 ]; then
    sync_swap l4-d1 l4-d2
    for attempt in $(seq 1 100); do test -e "$out/session-failover" && break; sleep 0.1; done
    test -e "$out/session-failover"
    sync_ready l4-d2 l4-d1 return
fi
python3 -c 'import time; print(time.monotonic())' > "$out/traffic-route-standby.txt"
ip netns exec l4-client python3 lab/katran/scenario.py check b1 > "$out/traffic-failover.json"
sleep 2
if [ "$fault_ns" = l4-r ]; then
    ip -n l4-r route get 198.18.0.1 > "$out/route-bfd-still-down.txt"
    grep -q 'via 10.1.2.2 ' "$out/route-bfd-still-down.txt"
fi
ip netns exec "$fault_ns" nft -a list table inet fault > "$out/fault-counters.txt"
if [ "$fault_ns" = l4-r ]; then ip netns exec l4-d1 nft -a list table inet fault > "$out/fault-director-counters.txt"; fi
phase return
ip netns exec "$fault_ns" nft delete table inet fault
if [ "$fault_ns" = l4-r ]; then ip netns exec l4-d1 nft delete table inet fault; fi
wait_route 10.1.1.2 health-restored
if [ "$fault_ns" = l4-r ]; then birdc -s "$out/router.ctl" 'show bfd sessions' > "$out/bfd-restored.txt"; fi
phase restored
ip netns exec l4-client python3 lab/katran/scenario.py check b1 > "$out/traffic-restored.json"
sleep 2
phase done
wait "$useful_tcp"
wait "$useful_udp"
if [ "${L4LOAD_BGP_TRAFFIC:-1}" = 4 ]; then
    wait "$session_pid"
    test -s "$out/session.json"
fi
ps -C bird -o pid,rss,vsz,time > "$out/bird-restored.txt"
for protocol in tcp udp; do
    python3 - "$out/useful-$protocol.json" "$fault_ns" <<'PY'
import json,sys
phases=json.load(open(sys.argv[1]))
assert phases['baseline']['passed'] > 0
assert phases['fault']['attempts'] > 0
if sys.argv[2] != 'l4-r': assert phases['fault']['errors'] > 0
assert phases['failover']['passed'] > 0
assert phases['restored']['passed'] > 0
PY
done
if [ "$fault_ns" = l4-r ]; then
    grep -Eq 'counter packets [1-9]' "$out/fault-counters.txt"
    grep -Eq 'counter packets [1-9]' "$out/fault-director-counters.txt"
    grep -q 'Down' "$out/bfd-withdrawn.txt"
    test "$(grep -c 'Up' "$out/bfd-restored.txt")" -ge 2
fi
grep -q '"action": "disable"' "$out/health1.jsonl"
grep -q '"action": "enable"' "$out/health1.jsonl"
for n in 1 2; do ip netns exec "l4-d$n" ipvsadm -Sn > "$out/ipvs$n-final.txt"; done
echo BGP_HEALTH_TRAFFIC_PASS
