#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/../.."
src=$(realpath "${1:?Katran checkout required}")
out=$(pwd)/lab/results/katran
mkdir -p "$out"
exec > >(tee "$out/run.log") 2>&1
test "$(git -C "$src" rev-parse HEAD)" = 4546144594d11d7bf342d008e7b94922fc9bbaa3
test -z "$(git -C "$src" status --porcelain)"
if ! bpftool version >/dev/null 2>&1; then
    export PATH="$(dirname "$(find -L /usr/lib/linux-tools -name bpftool -type f -print -quit)"):$PATH"
fi
bpftool version > "$out/bpftool.txt"
pin=/sys/fs/bpf/l4load-katran
test ! -e "$pin"
for ns in l4-client l4-router l4-lb l4-b1 l4-b2; do
    ! ip netns list | cut -d ' ' -f 1 | grep -qx "$ns"
done
pids=()
cleanup() {
    for pid in "${pids[@]}"; do kill "$pid" 2>/dev/null || true; done
    for ns in l4-client l4-router l4-lb l4-b1 l4-b2; do ip netns del "$ns" 2>/dev/null || true; done
    rm -rf "$pin"
}
trap cleanup EXIT
date -u +%FT%TZ > "$out/started.txt"
uname -a > "$out/kernel.txt"
clang --version > "$out/compiler.txt"
git -C "$src" rev-parse HEAD > "$out/upstream.txt"
git rev-parse HEAD > "$out/harness.txt"
clang -target bpf -D__KERNEL__ -O2 -g -I "$src" -I "$src/katran/lib/linux_includes" \
    -c "$src/katran/lib/bpf/balancer.bpf.c" -o "$out/balancer.o"
sha256sum "$out/balancer.o" > "$out/object.sha256"
mountpoint -q /sys/fs/bpf || mount -t bpf bpf /sys/fs/bpf
mkdir -p "$pin/maps"
bpftool prog load "$out/balancer.o" "$pin/prog" type xdp pinmaps "$pin/maps"
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
mac=$(ip -j -n l4-router link show r1 | python3 -c 'import json,sys; print(json.load(sys.stdin)[0]["address"])')
python3 lab/katran/scenario.py configure "$pin/maps" "$mac"
ip -n l4-lb link set eth0 xdpgeneric pinned "$pin/prog"
ip netns exec l4-router tcpdump -U -ni r1 -w "$out/forwarding.pcap" > "$out/capture.log" 2>&1 &
pids+=("$!")
sleep 1
ip netns exec l4-client python3 lab/katran/scenario.py check | tee "$out/result.json"
bpftool -j prog show pinned "$pin/prog" > "$out/program.json"
ip -j -n l4-lb link show eth0 > "$out/attachment.json"
echo 'KATRAN_DSR_PASS'
