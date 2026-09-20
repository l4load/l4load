#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/../.."
out=$(pwd)/lab/results/ipvs
mkdir -p "$out"
exec > >(tee "$out/run.log") 2>&1
for ns in l4-client l4-router l4-lb l4-b1 l4-b2; do
    ! ip netns list | cut -d ' ' -f 1 | grep -qx "$ns"
done
pids=()
cleanup() {
    for pid in "${pids[@]}"; do kill "$pid" 2>/dev/null || true; done
    for ns in l4-client l4-router l4-lb l4-b1 l4-b2; do
        ip netns pids "$ns" 2>/dev/null | xargs -r kill 2>/dev/null || true
        ip netns del "$ns" 2>/dev/null || true
    done
}
trap cleanup EXIT
modprobe ip_vs
modprobe ip_vs_rr
modprobe ipip
uname -a > "$out/kernel.txt"
dpkg-query -W keepalived ipvsadm > "$out/packages.txt"
date -u +%FT%TZ > "$out/started.txt"
git rev-parse HEAD > "$out/source.txt"
for ns in l4-client l4-router l4-lb l4-b1 l4-b2; do
    ip netns add "$ns"
    ip -n "$ns" link set lo up
    ip netns exec "$ns" sysctl -qw net.ipv4.conf.all.rp_filter=0 net.ipv4.conf.default.rp_filter=0
done
connect() {
    local ns=$1 subnet=$2
    ip link add "r$subnet" type veth peer name eth0 netns "$ns"
    ip link set "r$subnet" netns l4-router
    ip -n l4-router addr add "10.0.$subnet.1/24" dev "r$subnet"
    ip -n l4-router link set "r$subnet" up
    ip -n "$ns" addr add "10.0.$subnet.2/24" dev eth0
    ip -n "$ns" link set eth0 up
    ip -n "$ns" route add default via "10.0.$subnet.1"
}
connect l4-client 0
connect l4-lb 1
connect l4-b1 2
connect l4-b2 3
ip netns exec l4-router sysctl -qw net.ipv4.ip_forward=1
ip -n l4-router route add 198.18.0.1/32 via 10.0.1.2
for n in 1 2; do
    ip -n "l4-b$n" tunnel add decap mode ipip local "10.0.$((n+1)).2"
    ip -n "l4-b$n" link set decap up
    ip -n "l4-b$n" addr add 198.18.0.1/32 dev lo
    ip netns exec "l4-b$n" python3 -u lab/katran/scenario.py serve "b$n" > "$out/backend$n.log" 2>&1 &
    pids+=("$!")
done

ip -n l4-lb addr add 198.18.0.1/32 dev lo
ip netns exec l4-lb sysctl -qw net.ipv4.ip_forward=1
start_health() {
    ip netns exec "l4-b$1" python3 -m http.server 9090 --bind "10.0.$(($1+1)).2" > "$out/health$1.log" 2>&1 &
    health_pid=$!
    pids+=("$health_pid")
}
start_health 1
first_health=$health_pid
start_health 2
for proto in TCP UDP; do
    cat <<CONF
virtual_server 198.18.0.1 8080 {
    delay_loop 1
    lvs_sched rr
    lvs_method TUN
    protocol $proto
    alpha
CONF
    for n in 1 2; do
        cat <<CONF
    real_server 10.0.$((n+1)).2 8080 {
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
start_controller() {
    ip netns exec l4-lb keepalived -n -l -C -I -f "$out/keepalived.conf" >> "$out/keepalived.log" 2>&1 &
    controller=$!
    pids+=("$controller")
}
start_controller
wait_weight() {
    for attempt in $(seq 1 15); do
        ip netns exec l4-lb ipvsadm -Sn > "$out/state.txt"
        if python3 - "$out/state.txt" "$1" "${2:-10.0.2.2:8080}" <<'PY'
import sys
rows=[x.split() for x in open(sys.argv[1]) if x.startswith('-a ')]
matched=[x for x in rows if x[x.index('-r')+1]==sys.argv[3] and x[x.index('-w')+1]==sys.argv[2]]
sys.exit(0 if len(matched)==2 else 1)
PY
        then return; fi
        sleep 1
    done
    cat "$out/keepalived.log"
    return 1
}
wait_weight 1
ip netns exec l4-client python3 lab/katran/scenario.py check b1,b2 20000 | tee "$out/healthy.json"
rm -f "$out"/session-*
: > "$out/session-phase"
ip netns exec l4-client python3 -u lab/ipvs/sessions.py "$out" > "$out/sessions.jsonl" 2>&1 &
session_pid=$!
pids+=("$session_pid")
wait_session() {
    for attempt in $(seq 1 100); do
        if [ -f "$out/session-$1" ]; then return; fi
        kill -0 "$session_pid" || { cat "$out/sessions.jsonl"; return 1; }
        sleep 0.1
    done
    cat "$out/sessions.jsonl"
    return 1
}
phase() {
    echo "$1" > "$out/session-phase"
    wait_session "$1"
}
wait_session ready
kill "$first_health"
wait "$first_health" 2>/dev/null || true
wait_weight 0
phase health-down
cp "$out/state.txt" "$out/down-state.txt"
ip netns exec l4-client python3 lab/katran/scenario.py check b2 21000 | tee "$out/down.json"
start_health 1
first_health=$health_pid
wait_weight 1
cp "$out/state.txt" "$out/recovered-state.txt"
ip netns exec l4-client python3 lab/katran/scenario.py check b1,b2 22000 | tee "$out/recovered.json"
phase recovered
cp "$out/keepalived.conf" "$out/original.conf"
python3 - "$out/keepalived.conf" <<'PYCONFIG'
import sys
from pathlib import Path
p=Path(sys.argv[1])
p.write_text(p.read_text().replace('real_server 10.0.2.2 8080 {\n        weight 1', 'real_server 10.0.2.2 8080 {\n        weight 0'))
PYCONFIG
kill -HUP "$controller"
wait_weight 0
phase drained
cp "$out/state.txt" "$out/drained-state.txt"
ip netns exec l4-client python3 lab/katran/scenario.py check b2 23000 | tee "$out/drained.json"
cp "$out/original.conf" "$out/keepalived.conf"
kill -HUP "$controller"
wait_weight 1
phase restored
ip netns exec l4-client python3 lab/katran/scenario.py check b1,b2 24000 | tee "$out/restored.json"
kill -TERM "$controller"
wait "$controller"
phase controller-stopped
kill "$first_health"
wait "$first_health" 2>/dev/null || true
sleep 3
wait_weight 1
cp "$out/state.txt" "$out/controller-stopped-state.txt"
ip netns exec l4-client python3 lab/katran/scenario.py check b1,b2 25000 | tee "$out/controller-stopped.json"
for proto in t u; do
    for backend in 10.0.2.2 10.0.3.2; do
        ip netns exec l4-lb ipvsadm -e "-$proto" 198.18.0.1:8080 -r "$backend:8080" -i -w 0
    done
done
phase restart-gated
start_controller
wait_weight 0
wait_weight 1 10.0.3.2:8080
phase controller-restarted
ip netns exec l4-client python3 lab/katran/scenario.py check b2 26000 | tee "$out/controller-restarted.json"
start_health 1
wait_weight 1
phase done
wait "$session_pid"
cat "$out/sessions.jsonl"
echo IPVS_LIFECYCLE_PASS
