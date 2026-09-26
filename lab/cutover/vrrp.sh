ha_ns=1
for ns in l4-probe1 l4-probe2; do
    ! ip netns list | cut -d ' ' -f 1 | grep -qx "$ns"
    ip netns add "$ns"
done
ip -n l4-router link add ha-br type bridge
ip -n l4-router addr add 10.0.5.1/24 dev ha-br
ip -n l4-router link set ha-br up
ip_path=$(command -v ip)
python_path=$(command -v python3)
for n in 1 2; do
    if [ "$n" = 1 ]; then director=l4-lb; else director=l4-alt; fi
    ip link add "hd$n" type veth peer name ha0 netns "$director"
    ip link set "hd$n" netns l4-router
    ip -n l4-router link set "hd$n" master ha-br
    ip -n l4-router link set "hd$n" up
    ip -n "$director" addr add "10.0.5.$((n+1))/24" dev ha0
    ip -n "$director" link set ha0 up
    ip -n "l4-probe$n" link set lo up
    ip link add "hp$n" type veth peer name eth0 netns "l4-probe$n"
    ip link set "hp$n" netns l4-router
    ip -n l4-router link set "hp$n" master ha-br
    ip -n l4-router link set "hp$n" up
    ip -n "l4-probe$n" addr add "10.0.5.$((n+10))/24" dev eth0
    ip -n "l4-probe$n" link set eth0 up
    ip -n "l4-probe$n" route add 198.18.0.1/32 via "10.0.5.$((n+1))"
    priority=100
    if [ "$n" = 1 ]; then priority=150; fi
    cat > "$out/vrrp-$n.conf" <<EOF
global_defs {
    script_user root
    enable_script_security
}
vrrp_script dataplane {
    script "$ip_path netns exec l4-probe$n $python_path $PWD/lab/filter/probe.py 10.0.5.$((n+10)) pass"
    interval 1
    timeout 3
    fall 2
    rise 2
    user root
}
vrrp_instance DIRECTOR {
    state BACKUP
    interface ha0
    virtual_router_id 51
    priority $priority
    advert_int 1
    virtual_ipaddress {
        10.0.5.100/24 dev ha0
    }
    track_script {
        dataplane
    }
}
EOF
    ip netns exec "$director" keepalived -t -f "$out/vrrp-$n.conf"
    ip netns exec "$director" keepalived -n -l -P -f "$out/vrrp-$n.conf" -p "$out/vrrp-$n-parent.pid" -r "$out/vrrp-$n-child.pid" > "$out/vrrp-$n.log" 2>&1 &
    pids+=("$!")
done
ip netns exec l4-alt keepalived -n -l -C -I -f "$out/keepalived.conf" -p "$out/alt-check-parent.pid" -c "$out/alt-check-child.pid" > "$out/alt-checker.log" 2>&1 &
alt_controller=$!
pids+=("$alt_controller")
wait_real() {
    local ns=$1 weight=$2 phase=$3
    for attempt in $(seq 1 15); do
        ip netns exec "$ns" ipvsadm -Sn > "$out/vrrp-$phase-$ns-ipvs.txt"
        if python3 - "$out/vrrp-$phase-$ns-ipvs.txt" "$weight" <<'PY'
import sys
rows=[x.split() for x in open(sys.argv[1]) if x.startswith('-a ')]
matched=[x for x in rows if x[x.index('-r')+1]=='10.0.2.2:8080' and x[x.index('-w')+1]==sys.argv[2]]
sys.exit(0 if len(matched)==2 else 1)
PY
        then return; fi
        sleep 1
    done
    cat "$out/alt-checker.log"
    return 1
}
wait_real l4-alt 1 initial
ip -n l4-router route replace 198.18.0.1/32 via 10.0.5.100
has_vip() { ip -n "$1" addr show dev ha0 | grep -q '10.0.5.100/24'; }
record_vip() {
    for ns in l4-lb l4-alt; do ip -n "$ns" -j addr show dev ha0 > "$out/vrrp-$1-$ns.json"; done
}
wait_vip() {
    for attempt in $(seq 1 30); do
        if has_vip "$1" && ! has_vip "$2"; then return; fi
        sleep 0.5
    done
    cat "$out"/vrrp-*.log
    return 1
}
wait_vip l4-lb l4-alt
rm "$out/health1/health"
wait_real l4-lb 0 backend-down
wait_real l4-alt 0 backend-down
record_vip baseline
ip netns exec l4-client python3 lab/filter/probe.py 10.0.0.2 pass > "$out/vrrp-baseline.jsonl"
ip netns exec l4-client python3 lab/katran/scenario.py check b2 10000 > "$out/vrrp-baseline-backend.json"
ip netns exec l4-lb nft -f - <<'NFT'
table netdev fault {
    chain ingress {
        type filter hook ingress device "ha0" priority -500; policy accept;
        ip daddr 198.18.0.1 counter drop
    }
}
NFT
python3 -c 'import time; print(time.monotonic())' > "$out/vrrp-fault-start.txt"
wait_vip l4-alt l4-lb
kill -0 "$controller"
kill -0 "$alt_controller"
wait_real l4-alt 0 failover
record_vip failover
ip netns exec l4-client python3 lab/filter/probe.py 10.0.0.2 pass > "$out/vrrp-failover.jsonl"
ip netns exec l4-client python3 lab/katran/scenario.py check b2 11000 > "$out/vrrp-failover-backend.json"
ip netns exec l4-lb nft -j list table netdev fault > "$out/vrrp-fault.json"
python3 - "$out" <<'PY'
import json, sys, time
from pathlib import Path
p=Path(sys.argv[1]); rules=json.loads(p.joinpath('vrrp-fault.json').read_text())['nftables']
drops=sum(e['counter']['packets'] for r in rules if 'rule' in r for e in r['rule']['expr'] if 'counter' in e)
assert drops >= 2, drops
p.joinpath('vrrp-failover-time.json').write_text(json.dumps({'failure_to_verified_recovery_seconds':time.monotonic()-float(p.joinpath('vrrp-fault-start.txt').read_text()),'dropped_fault_packets':drops})+'\n')
PY
ip netns exec l4-lb nft delete table netdev fault
wait_vip l4-lb l4-alt
wait_real l4-lb 0 restored
record_vip restored
ip netns exec l4-client python3 lab/filter/probe.py 10.0.0.2 pass > "$out/vrrp-restored.jsonl"
ip netns exec l4-client python3 lab/katran/scenario.py check b2 12000 > "$out/vrrp-restored-backend.json"
echo healthy > "$out/health1/health"
wait_real l4-lb 1 healthy
wait_real l4-alt 1 healthy
ip netns exec l4-client python3 lab/katran/scenario.py check b1,b2 13000 > "$out/vrrp-healthy-backend.json"
kill -0 "$controller"
kill -0 "$alt_controller"
echo VRRP_BACKUP_HEALTH_PASS
