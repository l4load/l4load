#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/../.."
out=$(pwd)/lab/results/ipvs6
mkdir -p "$out"
exec > >(tee "$out/run.log") 2>&1
export L4LOAD_VIP=2001:db8:100::1 L4LOAD_CLIENT=2001:db8:10::2
names=(l6-client l6-router l6-lb l6-b1 l6-b2)
for ns in "${names[@]}"; do
    ! ip netns list | cut -d ' ' -f 1 | grep -qx "$ns"
done
cleanup() {
    for ns in "${names[@]}"; do
        ip netns pids "$ns" 2>/dev/null | xargs -r kill 2>/dev/null || true
        ip netns del "$ns" 2>/dev/null || true
    done
}
trap cleanup EXIT
modprobe ip_vs_rr
modprobe ip6_tunnel
uname -a > "$out/kernel.txt"
dpkg-query -W keepalived ipvsadm > "$out/packages.txt"
git rev-parse HEAD > "$out/source.txt"
date -u +%FT%TZ > "$out/started.txt"
for ns in "${names[@]}"; do
    ip netns add "$ns"
    ip -n "$ns" link set lo up
done
connect() {
    local ns=$1 subnet=$2
    ip link add "r$subnet" type veth peer name eth0 netns "$ns"
    ip link set "r$subnet" netns l6-router
    ip -n l6-router link set "r$subnet" up
    ip -n l6-router -6 addr add "2001:db8:$subnet::1/64" dev "r$subnet" nodad
    ip -n "$ns" link set eth0 up
    ip -n "$ns" -6 addr add "2001:db8:$subnet::2/64" dev eth0 nodad
    ip -n "$ns" -6 route add default via "2001:db8:$subnet::1"
}
connect l6-client 10
connect l6-lb 11
connect l6-b1 20
connect l6-b2 30
for ns in l6-router l6-lb; do
    ip netns exec "$ns" sysctl -qw net.ipv6.conf.all.forwarding=1
done
ip -n l6-router -6 route add "$L4LOAD_VIP/128" via 2001:db8:11::2
ip -n l6-lb -6 addr add "$L4LOAD_VIP/128" dev lo nodad
start_health() {
    ip netns exec "l6-b$1" python3 -m http.server 9090 --bind "2001:db8:$(($1*10+10))::2" > "$out/health$1.log" 2>&1 &
    health_pid=$!
}
for n in 1 2; do
    ip -n "l6-b$n" -6 tunnel add decap mode ip6ip6 local "2001:db8:$((n*10+10))::2"
    ip -n "l6-b$n" link set decap up
    ip -n "l6-b$n" -6 addr add "$L4LOAD_VIP/128" dev lo nodad
    ip netns exec "l6-b$n" python3 -u lab/katran/scenario.py serve "b$n" > "$out/backend$n.log" 2>&1 &
    start_health "$n"
    if [ "$n" = 1 ]; then first_health=$health_pid; fi
done
for proto in TCP UDP; do
    cat <<CONF
virtual_server $L4LOAD_VIP 8080 {
    delay_loop 1
    lvs_sched rr
    lvs_method TUN
    protocol $proto
    alpha
CONF
    for n in 1 2; do
        cat <<CONF
    real_server 2001:db8:$((n*10+10))::2 8080 {
        weight 1
        inhibit_on_failure
        TCP_CHECK {
            connect_port 9090
            connect_timeout 1
            retry 1
            delay_before_retry 1
        }
    }
CONF
    done
    echo '}'
done > "$out/keepalived.conf"
ip netns exec l6-lb keepalived -n -l -C -f "$out/keepalived.conf" > "$out/keepalived.log" 2>&1 &
wait_state() {
    for attempt in $(seq 1 15); do
        ip netns exec l6-lb ipvsadm -Sn > "$out/state.txt"
        if python3 - "$out/state.txt" "$1" <<'PY'
import sys
rows = [x.split() for x in open(sys.argv[1]) if x.startswith('-a ')]
expected = {'[2001:db8:20::2]:8080': sys.argv[2], '[2001:db8:30::2]:8080': '1'}
ok = len(rows) == 4 and all(expected.get(x[x.index('-r')+1]) == x[x.index('-w')+1] for x in rows)
sys.exit(0 if ok else 1)
PY
        then return; fi
        sleep 1
    done
    cat "$out/state.txt" "$out/keepalived.log"
    return 1
}
wait_state 1
ip netns exec l6-client python3 lab/katran/scenario.py check b1,b2 20000 | tee "$out/healthy.json"
kill "$first_health"
wait "$first_health" 2>/dev/null || true
wait_state 0
cp "$out/state.txt" "$out/down-state.txt"
ip netns exec l6-client python3 lab/katran/scenario.py check b2 21000 | tee "$out/down.json"
start_health 1
wait_state 1
ip netns exec l6-client python3 lab/katran/scenario.py check b1,b2 22000 | tee "$out/recovered.json"
ip netns exec l6-client ip -j link show > "$out/links.json"
ip netns exec l6-client python3 -u lab/ipvs/datagrams.py | tee "$out/datagrams.jsonl"
echo IPVS_IPV6_PASS
