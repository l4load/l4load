#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/../.."
out=$PWD/lab/results/bgp
test ! -e "$out"
mkdir -p "$out"
date -u +%FT%TZ > "$out/started.txt"
git rev-parse HEAD > "$out/source.txt"
uname -a > "$out/kernel.txt"
dpkg-query -W bird2 > "$out/packages.txt"
pids=()
cleanup() {
    for pid in "${pids[@]}"; do kill "$pid" 2>/dev/null || true; done
    for ns in l4-r l4-d1 l4-d2 l4-client l4-b1 l4-p1 l4-p2; do
        ip netns pids "$ns" 2>/dev/null | xargs -r kill 2>/dev/null || true
        ip netns del "$ns" 2>/dev/null || true
    done
}
trap cleanup EXIT
for ns in l4-r l4-d1 l4-d2; do
    ! ip netns list | cut -d ' ' -f 1 | grep -qx "$ns"
    ip netns add "$ns"
    ip -n "$ns" link set lo up
done
bfd_clause=
retry_clause=
if [ "${L4LOAD_BGP_TRAFFIC:-0}" = 3 ]; then
    bfd_clause='bfd yes;'
    retry_clause='error wait time 1, 5; connect delay time 1;'
fi
for n in 1 2; do
    ip link add "r$n" type veth peer name eth0 netns "l4-d$n"
    ip link set "r$n" netns l4-r
    ip -n l4-r addr add "10.1.$n.1/30" dev "r$n"
    ip -n "l4-d$n" addr add "10.1.$n.2/30" dev eth0
    ip -n l4-r link set "r$n" up
    ip -n "l4-d$n" link set eth0 up
    cat > "$out/d$n.conf" <<EOF
log stderr all;
router id 10.1.$n.2;
protocol device {}
protocol static vip$n {
    ipv4;
    route 198.18.0.1/32 blackhole;
}
protocol bgp upstream {
    local 10.1.$n.2 as 6500$n;
    neighbor 10.1.$n.1 as 65000;
    $bfd_clause
    $retry_clause
    ipv4 { import none; export where net = 198.18.0.1/32; };
}
EOF
done
cat > "$out/router.conf" <<EOF
log stderr all;
router id 10.1.1.1;
protocol device {}
protocol kernel k4 { ipv4 { import none; export all; }; }
protocol bgp primary {
    local 10.1.1.1 as 65000;
    neighbor 10.1.1.2 as 65001;
    $bfd_clause
    $retry_clause
    ipv4 { preference 200; import all; export none; };
}
protocol bgp standby {
    local 10.1.2.1 as 65000;
    neighbor 10.1.2.2 as 65002;
    $bfd_clause
    $retry_clause
    ipv4 { preference 100; import all; export none; };
}
EOF
if [ -n "$bfd_clause" ]; then
    for name in router d1 d2; do
        cat >> "$out/$name.conf" <<'EOF'
protocol bfd {
    interface "*" { interval 100 ms; multiplier 3; };
}
EOF
    done
fi
for pair in 'l4-r router' 'l4-d1 d1' 'l4-d2 d2'; do
    set -- $pair
    ip netns exec "$1" bird -f -c "$out/$2.conf" -s "$out/$2.ctl" -P "$out/$2.pid" > "$out/$2.log" 2>&1 &
    pids+=("$!")
done
wait_route() {
    local expected=$1 phase=$2
    for attempt in $(seq 1 100); do
        ip -n l4-r route get 198.18.0.1 > "$out/route-$phase.txt" 2>&1 || true
        if grep -q "via $expected " "$out/route-$phase.txt"; then return; fi
        sleep 0.1
    done
    if [ "${L4LOAD_BGP_TRAFFIC:-0}" = 3 ]; then
        birdc -s "$out/router.ctl" 'show bfd sessions' > "$out/bfd-timeout-$phase.txt" || true
        birdc -s "$out/router.ctl" 'show protocols all' > "$out/protocol-timeout-$phase.txt" || true
        ip netns exec l4-r nft -a list table inet fault > "$out/fault-timeout-$phase.txt" 2>&1 || true
    fi
    for name in router d1 d2; do cat "$out/$name.log"; done
    return 1
}
for peer in primary standby; do
    for attempt in $(seq 1 100); do
        birdc -s "$out/router.ctl" 'show protocols' > "$out/router-ready.txt" 2>&1 || true
        if grep -E "^$peer +BGP +.*Established" "$out/router-ready.txt"; then break; fi
        sleep 0.1
    done
    grep -Eq "^$peer +BGP +.*Established" "$out/router-ready.txt"
done
wait_route 10.1.1.2 baseline
for name in router d1 d2; do birdc -s "$out/$name.ctl" 'show protocols' > "$out/$name-protocols.txt"; done
if [ -n "$bfd_clause" ]; then
    for attempt in $(seq 1 100); do
        birdc -s "$out/router.ctl" 'show bfd sessions' > "$out/bfd-ready.txt"
        if [ "$(grep -c 'Up' "$out/bfd-ready.txt")" -ge 2 ]; then break; fi
        sleep 0.1
    done
    test "$(grep -c 'Up' "$out/bfd-ready.txt")" -ge 2
fi
python3 -c 'import time; print(time.monotonic())' > "$out/fault-start.txt"
birdc -s "$out/d1.ctl" 'disable vip1' > "$out/withdraw.txt"
wait_route 10.1.2.2 withdrawn
python3 - "$out" <<'PY'
from pathlib import Path
import sys,time
out=Path(sys.argv[1])
(out/'withdraw-time.txt').write_text(str(time.monotonic()-float((out/'fault-start.txt').read_text()))+'\n')
PY
birdc -s "$out/d1.ctl" 'enable vip1' > "$out/restore.txt"
wait_route 10.1.1.2 restored
for name in router d1 d2; do birdc -s "$out/$name.ctl" 'show protocols' > "$out/$name-final.txt"; done
echo BGP_ROUTE_TRIAL_PASS
if [ "${L4LOAD_BGP_TRAFFIC:-0}" != 0 ]; then source lab/bgp/traffic.sh; fi
