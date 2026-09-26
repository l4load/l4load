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
ip -n l4-router route replace 198.18.0.1/32 via 10.0.5.100
has_vip() { ip -n "$1" addr show dev ha0 | grep -q '10.0.5.100/24'; }
wait_vip() {
    for attempt in $(seq 1 30); do
        if has_vip "$1" && ! has_vip "$2"; then return; fi
        sleep 0.5
    done
    cat "$out"/vrrp-*.log
    return 1
}
wait_vip l4-lb l4-alt
ip netns exec l4-client python3 lab/filter/probe.py 10.0.0.2 pass > "$out/vrrp-baseline.jsonl"
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
ip netns exec l4-client python3 lab/filter/probe.py 10.0.0.2 pass > "$out/vrrp-failover.jsonl"
python3 - "$out" <<'PY'
import json, sys, time
from pathlib import Path
p=Path(sys.argv[1]); p.joinpath('vrrp-failover-time.json').write_text(json.dumps({'failure_to_verified_recovery_seconds':time.monotonic()-float(p.joinpath('vrrp-fault-start.txt').read_text())})+'\n')
PY
ip netns exec l4-lb nft delete table netdev fault
wait_vip l4-lb l4-alt
ip netns exec l4-client python3 lab/filter/probe.py 10.0.0.2 pass > "$out/vrrp-restored.jsonl"
kill -0 "$controller"
echo VRRP_FORWARDING_RECOVERY_PASS
