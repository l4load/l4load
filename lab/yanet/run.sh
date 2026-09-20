#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/../.."
upstream=$(realpath "${1:?upstream source directory}")
build="$upstream/build_autotest"
export PATH="$build/dataplane:$build/controlplane:$build/cli:$PATH"
out=$(pwd)/lab/results/yanet-dsr
mkdir -p "$out"
exec > >(tee "$out/run.log") 2>&1
for ns in l4-client l4-router l4-b1 l4-b2; do
    ! ip netns list | cut -d ' ' -f 1 | grep -qx "$ns"
done
pids=()
cleanup() {
    for pid in "${pids[@]}"; do
        kill -KILL "$pid" 2>/dev/null || true
        wait "$pid" 2>/dev/null || true
    done
    for ns in l4-client l4-router l4-b1 l4-b2; do
        ip netns pids "$ns" 2>/dev/null | xargs -r kill 2>/dev/null || true
        ip netns del "$ns" 2>/dev/null || true
    done
}
trap cleanup EXIT
modprobe ipip
uname -a > "$out/kernel.txt"
dpkg-query -W > "$out/packages.txt"
cat "$out/kernel.txt"
date -u +%FT%TZ > "$out/started.txt"
git -c safe.directory="$(pwd)" rev-parse HEAD > "$out/source.txt"
for ns in l4-client l4-router l4-b1 l4-b2; do
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
connect l4-b1 2
connect l4-b2 3
ip netns exec l4-router sysctl -qw net.ipv4.ip_forward=1
for n in 1 2; do
    ip -n "l4-b$n" tunnel add decap mode ipip local "10.0.$((n+1)).2"
    ip -n "l4-b$n" link set decap up
    ip -n "l4-b$n" addr add 198.18.0.1/32 dev lo
    ip netns exec "l4-b$n" python3 -u lab/katran/scenario.py serve "b$n" > "$out/backend$n.log" 2>&1 &
    pids+=("$!")
done

mkdir -p /run/yanet
python3 lab/yanet/configure.py "$out"
yanet-dataplane -c "$out/dataplane.conf" > "$out/dataplane.log" 2>&1 &
pids+=("$!")
wait_app() {
    for attempt in $(seq 1 30); do
        if timeout --kill-after=1s 2s yanet-cli version 2>/dev/null | grep -q "$1"; then return; fi
        sleep 1
    done
    cat "$out/dataplane.log" "$out/controlplane.log" 2>/dev/null || true
    return 1
}
wait_app dataplane
ip netns exec l4-router python3 -u lab/yanet/tap.py vp0 /run/yanet/vp0 > "$out/tap.log" 2>&1 &
pids+=("$!")
for attempt in $(seq 1 30); do
    if ip -n l4-router link show vp0 >/dev/null 2>&1; then break; fi
    sleep 0.1
done
ip -n l4-router link set vp0 address 02:00:00:00:01:01 up
ip -n l4-router addr add 10.0.1.1/24 dev vp0
ip -n l4-router neigh replace 10.0.1.2 lladdr 02:00:00:00:01:02 dev vp0 nud permanent
ip -n l4-router route add 198.18.0.1/32 via 10.0.1.2
yanet-controlplane -c "$out/controlplane.conf" > "$out/controlplane.log" 2>&1 &
pids+=("$!")
wait_app controlplane
yanet-cli rib static insert default 10.0.0.0/8 10.0.1.1
for proto in tcp udp; do
    for backend in 10.0.2.2 10.0.3.2; do
        yanet-cli balancer real enable balancer0 198.18.0.1 "$proto" 8080 "$backend" 8080
    done
done
yanet-cli balancer real flush
yanet-cli balancer real balancer0 > "$out/reals.txt"
ip netns exec l4-client python3 lab/katran/scenario.py check b1,b2 20000 | tee "$out/healthy.json"
yanet-cli balancer state balancer0 > "$out/state.txt"
echo YANET_DSR_PASS
