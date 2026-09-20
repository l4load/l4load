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
backend_pids=()
cleanup() {
    if [ -n "${unitfile:-}" ]; then
        journalctl -u l4load-ipvs-lab.service --no-pager > "$out/service-journal.txt" || true
        systemctl stop l4load-ipvs-lab.service || true
        rm -f "$unitfile"
        systemctl daemon-reload
    fi
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
dpkg-query -W keepalived ipvsadm prometheus-node-exporter > "$out/packages.txt"
cat "$out/packages.txt" "$out/kernel.txt"
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
    backend_pids+=("$!")
done

ip -n l4-lb addr add 198.18.0.1/32 dev lo
ip netns exec l4-lb sysctl -qw net.ipv4.ip_forward=1
start_health() {
    mkdir -p "$out/health$1"
    echo healthy > "$out/health$1/health"
    ip netns exec "l4-b$1" python3 -m http.server 9090 --directory "$out/health$1" --bind "10.0.$(($1+1)).2" > "$out/health$1.log" 2>&1 &
    health_pid=$!
    pids+=("$health_pid")
}
start_health 1
first_health=$health_pid
start_health 2
cp profiles/ipvs/keepalived.conf "$out/keepalived.conf"
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
wait_weight 1 10.0.3.2:8080
ip netns exec l4-client python3 lab/katran/scenario.py check b1,b2 20000 | tee "$out/healthy.json"
if [ "${L4LOAD_LOAD:-0}" = 1 ]; then
    for pid in "${backend_pids[@]}"; do kill "$pid"; wait "$pid" || true; done
    bash lab/load/run.sh "$out/load"
    exit
fi
ip netns exec l4-lb prometheus-node-exporter --collector.disable-defaults --collector.ipvs --web.listen-address=127.0.0.1:19100 > "$out/exporter.log" 2>&1 &
exporter_pid=$!
pids+=("$exporter_pid")
ip netns exec l4-lb python3 lab/ipvs/metrics.py "$out/metrics-healthy.txt" 1
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
ip netns exec l4-lb python3 lab/ipvs/metrics.py "$out/metrics-down.txt" 0
start_health 1
first_health=$health_pid
wait_weight 1
cp "$out/state.txt" "$out/recovered-state.txt"
ip netns exec l4-client python3 lab/katran/scenario.py check b1,b2 22000 | tee "$out/recovered.json"
ip netns exec l4-lb python3 lab/ipvs/metrics.py "$out/metrics-recovered.txt" 1
kill "$exporter_pid"
wait "$exporter_pid" 2>/dev/null || true
phase recovered
rm "$out/health1/health"
wait_weight 0
phase http-unhealthy
ip netns exec l4-client python3 lab/katran/scenario.py check b2 27000 | tee "$out/http-unhealthy.json"
echo healthy > "$out/health1/health"
wait_weight 1
phase http-recovered
ip netns exec l4-client python3 lab/katran/scenario.py check b1,b2 28000 | tee "$out/http-recovered.json"
reload_config() {
    ip netns exec l4-lb keepalived -t -f "$1" >> "$out/validation.log" 2>&1 || return
    cp "$1" "$out/next.conf" || return
    mv "$out/next.conf" "$out/keepalived.conf" || return
    kill -HUP "$controller"
}
cp "$out/keepalived.conf" "$out/original.conf"
sed 's/virtual_server 198.18.0.1 8080/virtual_server 198.18.0.1 70000/' "$out/original.conf" > "$out/invalid.conf"
if reload_config "$out/invalid.conf"; then
    echo 'invalid configuration accepted'
    exit 1
fi
cmp "$out/original.conf" "$out/keepalived.conf"
phase invalid-rejected
ip netns exec l4-client python3 lab/katran/scenario.py check b1,b2 29000 | tee "$out/invalid-rejected.json"
cp "$out/original.conf" "$out/drain.conf"
python3 - "$out/drain.conf" <<'PYCONFIG'
import sys
from pathlib import Path
p=Path(sys.argv[1])
p.write_text(p.read_text().replace('real_server 10.0.2.2 8080 {\n        weight 1', 'real_server 10.0.2.2 8080 {\n        weight 0'))
PYCONFIG
reload_config "$out/drain.conf"
wait_weight 0
phase drained
cp "$out/state.txt" "$out/drained-state.txt"
ip netns exec l4-client python3 lab/katran/scenario.py check b2 23000 | tee "$out/drained.json"
reload_config "$out/original.conf"
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
gate_reals() {
    ip netns exec l4-lb bash lab/ipvs/gate.sh
}
gate_reals
phase restart-gated
start_controller
wait_weight 0
wait_weight 1 10.0.3.2:8080
phase controller-restarted
ip netns exec l4-client python3 lab/katran/scenario.py check b2 26000 | tee "$out/controller-restarted.json"
start_health 1
first_health=$health_pid
wait_weight 1
kill -STOP "$controller"
mapfile -t crashed_pids < <(ip netns pids l4-lb)
test "${#crashed_pids[@]}" -ge 2
printf '%s\n' "${crashed_pids[@]}" > "$out/crashed-pids.txt"
kill -KILL "${crashed_pids[@]}"
wait "$controller" 2>/dev/null || true
for attempt in $(seq 1 30); do
    if [ -z "$(ip netns pids l4-lb)" ]; then break; fi
    sleep 0.1
done
test -z "$(ip netns pids l4-lb)"
phase controller-crashed
kill "$first_health"
wait "$first_health" 2>/dev/null || true
sleep 3
wait_weight 1
ip netns exec l4-client python3 lab/katran/scenario.py check b1,b2 30000 | tee "$out/controller-crashed.json"
gate_reals
phase crash-gated
start_controller
wait_weight 0
wait_weight 1 10.0.3.2:8080
phase crash-recovered
ip netns exec l4-client python3 lab/katran/scenario.py check b2 31000 | tee "$out/crash-recovered.json"
start_health 1
first_health=$health_pid
wait_weight 1
source lab/ipvs/service.sh
phase done
wait "$session_pid"
cat "$out/sessions.jsonl"
systemctl stop l4load-ipvs-lab.service
ip netns exec l4-lb ipvsadm -C
ip netns exec l4-lb ipvsadm -Sn > "$out/cold-empty.txt"
test ! -s "$out/cold-empty.txt"
systemctl start l4load-ipvs-lab.service
wait_weight 1
wait_weight 1 10.0.3.2:8080
cp "$out/state.txt" "$out/cold-ready.txt"
ip netns exec l4-client python3 lab/katran/scenario.py check b1,b2 33000 | tee "$out/cold-start.json"
ip netns exec l4-client ip -j link show > "$out/links.json"
ip netns exec l4-client python3 -u lab/ipvs/datagrams.py | tee "$out/datagrams.jsonl"
echo IPVS_LIFECYCLE_PASS
