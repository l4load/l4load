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
    if [ "${L4LOAD_BGP_TRAFFIC:-1}" != 8 ]; then
        for proto in -t -u; do
            ip netns exec "l4-d$n" ipvsadm -A "$proto" 198.18.0.1:8080 -s rr
            ip netns exec "l4-d$n" ipvsadm -a "$proto" 198.18.0.1:8080 -r 10.0.2.2:8080 -i
        done
    fi
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
probe_directors() {
    for n in 1 2; do
        for attempt in $(seq 1 3); do
            if ip netns exec "l4-p$n" python3 lab/filter/probe.py "10.2.$n.2" pass > "$out/probe$n.jsonl" 2>&1; then break; fi
            sleep 0.1
        done
        grep -q '"status": "pass"' "$out/probe$n.jsonl"
    done
}
if [ "${L4LOAD_BGP_TRAFFIC:-1}" != 8 ]; then probe_directors; fi
if [ "${L4LOAD_BGP_TRAFFIC:-1}" != 8 ]; then ip netns exec l4-client python3 lab/katran/scenario.py check b1 > "$out/traffic-baseline.json"; fi
if [ "${L4LOAD_BGP_TRAFFIC:-1}" = 7 ]; then
    source lab/bgp/sync.sh
    systemctl stop bird.service || true
    mkdir -p /run/systemd/system/l4load-ipvs@d1.service.d
    cat > /run/systemd/system/l4load-ipvs@d1.service.d/lab.conf <<'UNIT'
[Service]
ExecStartPre=
ExecStart=
ExecStart=/usr/bin/sleep infinity
ExecReload=
Restart=no
UNIT
    cat > "$out/routed-d1.json" <<'JSON'
{"vip":"198.18.0.1","local_ip":"10.1.1.2","local_as":65001,"peer_ip":"10.1.1.1","peer_as":65000,"sync_interface":"sync0","sync_id":42}
JSON
    cat > "$out/check-d1" <<EOF
#!/bin/sh
exec ip netns exec l4-p1 python3 "$PWD/lab/filter/probe.py" 10.2.1.2 pass >/dev/null
EOF
    chmod 700 "$out/check-d1"
    python3 profiles/ipvs/install-routed.py d1 "$out/routed-d1.json" "$out/check-d1" profiles/ipvs/keepalived.conf
    cp /etc/l4load/bird-d1.conf "$out/installed-bird.conf"
    chmod 644 "$out/installed-bird.conf" "$out/check-d1"
    mkdir -p /run/systemd/system/l4load-routed@d1.service.d
    cat > /run/systemd/system/l4load-routed@d1.service.d/lab.conf <<UNIT
[Service]
NetworkNamespacePath=/run/netns/l4-d1
StandardOutput=append:$out/health1.jsonl
UNIT
    systemctl daemon-reload
    systemctl show l4load-routed@d1.service -p BindsTo -p Requires -p After -p FragmentPath -p DropInPaths > "$out/installed-dependencies.txt"
    if ! systemctl start l4load-routed@d1.service; then
        systemctl status -l --no-pager l4load-routed@d1.service > "$out/installed-status.txt" 2>&1 || true
        journalctl -b --no-pager -u l4load-routed@d1.service -u l4load-ipvs@d1.service -n 100 > "$out/installed-journal.txt" 2>&1 || true
        exit 1
    fi
    systemctl show l4load-routed@d1.service -p ActiveState -p MainPID -p NRestarts -p BindsTo > "$out/installed-service.txt"
    ln -s /run/l4load-routed-d1/bird.ctl "$out/d1.ctl"
fi
if [ "${L4LOAD_BGP_TRAFFIC:-1}" = 8 ]; then source lab/bgp/pair.sh; probe_directors; fi
if [ "${L4LOAD_BGP_LOAD:-0}" = 1 ]; then
    test "${L4LOAD_BGP_TRAFFIC:-1}" = 8
    ip -n l4-client addr add 10.0.0.3/24 dev eth0
    for n in 1 2; do
        ip netns exec "l4-d$n" bash profiles/nftables/install.sh eth0
        ip netns exec "l4-d$n" nft 'add element netdev l4load blocked { 10.0.0.3 . 198.18.0.1 }'
    done
    ip netns exec l4-client python3 lab/filter/probe.py 10.0.0.3 drop > "$out/denied-probe.jsonl"
    ip netns exec l4-client python3 lab/filter/probe.py 10.0.0.2 pass > "$out/allowed-probe.jsonl"
    lscpu > "$out/cpu.txt"
    duration=30
    if [ "${L4LOAD_BGP_SOAK:-0}" = 1 ]; then duration=90; fi
    ip netns exec l4-client sockperf throughput -i 198.18.0.1 -p 8080 --client_ip 10.0.0.3 -m 64 -t "$duration" --mps 100000 > "$out/denied-load.txt" 2>&1 &
    denied_pid=$!
    pids+=("$denied_pid")
    sleep 2
    kill -0 "$denied_pid"
fi
for n in 1 2; do
    if [ "${L4LOAD_BGP_TRAFFIC:-1}" = 8 ] || { [ "${L4LOAD_BGP_TRAFFIC:-1}" = 7 ] && [ "$n" = 1 ]; }; then continue; fi
    peer=-
    if [ "${L4LOAD_BGP_TRAFFIC:-1}" = 3 ] || [ "${L4LOAD_BGP_TRAFFIC:-1}" = 7 ]; then peer="10.1.$n.1"; fi
    python3 -u profiles/ipvs/route-gate.py "$out/d$n.ctl" "vip$n" "$peer" -- ip netns exec "l4-p$n" python3 lab/filter/probe.py "10.2.$n.2" pass > "$out/health$n.jsonl" 2>&1 &
    pids+=("$!")
done
for n in 1 2; do
    for attempt in $(seq 1 100); do grep -q '"action": "enable"' "$out/health$n.jsonl" && break; sleep 0.1; done
    grep -q '"action": "enable"' "$out/health$n.jsonl"
done
wait_route 10.1.1.2 health-ready
if [ "${L4LOAD_BGP_TRAFFIC:-1}" = 8 ]; then ip netns exec l4-client python3 lab/katran/scenario.py check b1 > "$out/traffic-baseline.json"; fi
if [ "${L4LOAD_BGP_TRAFFIC:-1}" = 7 ]; then
    ip netns exec l4-d1 ipvsadm -Ln --daemon > "$out/installed-sync-daemons.txt"
    grep -q 'master sync daemon' "$out/installed-sync-daemons.txt"
    grep -q 'backup sync daemon' "$out/installed-sync-daemons.txt"
    birdc -s "$out/d1.ctl" 'show bfd sessions' > "$out/installed-bfd.txt"
    grep -q 'Up' "$out/installed-bfd.txt"
fi
phase() {
    if [ "${L4LOAD_BGP_LOAD:-0}" = 1 ]; then python3 lab/bgp/phase-snapshot.py "$out" "$1"; fi
    printf '%s\n' "$1" > "$out/useful-phase.next"
    mv "$out/useful-phase.next" "$out/useful-phase"
}
phase baseline
if [ "${L4LOAD_BGP_TRAFFIC:-1}" -ge 4 ]; then
    if [ "${L4LOAD_BGP_TRAFFIC:-1}" != 7 ] && [ "${L4LOAD_BGP_TRAFFIC:-1}" != 8 ]; then source lab/bgp/sync.sh; fi
    if [ "${L4LOAD_BGP_TRAFFIC:-1}" = 5 ]; then
        for n in 1 2; do ip -n "l4-d$n" link set sync0 down; done
    fi
    ip netns exec l4-client env L4LOAD_SESSION_EXPECT_RESET="$([ "${L4LOAD_BGP_TRAFFIC:-1}" = 5 ] && echo 1 || echo 0)" python3 -u lab/bgp/session.py "$out" > "$out/session.log" 2>&1 &
    session_pid=$!
    pids+=("$session_pid")
    for attempt in $(seq 1 100); do test -e "$out/session-baseline" && break; sleep 0.1; done
    test -e "$out/session-baseline"
    if [ "${L4LOAD_BGP_TRAFFIC:-1}" != 5 ]; then sync_ready l4-d1 l4-d2 failover; fi
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
phase fault
python3 -c 'import time; print(time.monotonic())' > "$out/traffic-fault-start.txt"
if [ "$fault_ns" = l4-r ]; then
    ip netns exec l4-r nft add rule inet fault ingress iifname r1 udp dport 3784 counter drop
    ip netns exec l4-d1 nft add rule inet fault ingress iifname eth0 udp dport 3784 counter drop
else
    ip netns exec l4-d1 nft add rule inet fault ingress ip daddr 198.18.0.1 counter drop
fi
wait_route 10.1.2.2 health-withdrawn
if [ "$fault_ns" = l4-r ]; then birdc -s "$out/router.ctl" 'show bfd sessions' > "$out/bfd-withdrawn.txt"; fi
phase failover
if [ "${L4LOAD_BGP_TRAFFIC:-1}" = 4 ] || [ "${L4LOAD_BGP_TRAFFIC:-1}" = 6 ] || [ "${L4LOAD_BGP_TRAFFIC:-1}" = 7 ] || [ "${L4LOAD_BGP_TRAFFIC:-1}" = 8 ]; then
    if [ "${L4LOAD_BGP_TRAFFIC:-1}" = 4 ]; then sync_swap l4-d1 l4-d2; fi
    for attempt in $(seq 1 100); do test -e "$out/session-failover" && break; sleep 0.1; done
    test -e "$out/session-failover"
    sync_ready l4-d2 l4-d1 return
fi
if [ "${L4LOAD_BGP_TRAFFIC:-1}" = 5 ]; then
    for attempt in $(seq 1 100); do test -s "$out/session-reset.json" && break; sleep 0.1; done
    test -s "$out/session-reset.json"
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
if [ "${L4LOAD_BGP_SOAK:-0}" = 1 ]; then
    kill -0 "$denied_pid"
    python3 lab/bgp/phase-snapshot.py "$out" soak
    for protocol in tcp udp; do
        flags=()
        if [ "$protocol" = tcp ]; then flags+=(--tcp); fi
        ip netns exec l4-client sockperf under-load -i 198.18.0.1 -p 8081 --client_ip 10.0.0.2 "${flags[@]}" -m 64 -t 60 --mps 1000 --reply-every 1 --full-rtt --full-log "$out/soak-$protocol.csv" > "$out/soak-$protocol.txt" 2>&1 &
        pids+=("$!")
        if [ "$protocol" = tcp ]; then soak_tcp=$!; else soak_udp=$!; fi
    done
    wait "$soak_tcp"
    wait "$soak_udp"
    python3 lab/bgp/phase-snapshot.py "$out" soak-end
    python3 lab/bgp/soak-summary.py "$out" > "$out/soak-summary.json"
    kill -0 "$denied_pid"
fi
if [ "${L4LOAD_BGP_LOAD:-0}" = 1 ]; then
    wait "$denied_pid"
    python3 lab/bgp/phase-summary.py "$out" > "$out/phase-summary.log"
    python3 - "$out/denied-load.txt" "$out/denied-load.json" <<'PY'
import json,re,sys
text=open(sys.argv[1]).read()
sent,elapsed=re.search(r'Total of (\d+) messages sent in ([\d.]+) sec',text).groups()
record={'requested_mps':100000,'sent':int(sent),'elapsed_seconds':float(elapsed),'actual_mps':int(sent)/float(elapsed)}
assert record['actual_mps'] > 0
open(sys.argv[2],'w').write(json.dumps(record)+'\n')
PY
    for n in 1 2; do
        ip netns exec "l4-d$n" nft -a list table netdev l4load > "$out/filter-d$n.txt"
        grep -Eq 'counter packets [1-9]' "$out/filter-d$n.txt"
        ip netns exec "l4-d$n" ipvsadm -Ln --stats > "$out/ipvs-stats-d$n.txt"
    done
fi
if [ "${L4LOAD_BGP_TRAFFIC:-1}" -ge 4 ]; then
    wait "$session_pid"
    if [ "${L4LOAD_BGP_TRAFFIC:-1}" != 5 ]; then test -s "$out/session.json"; fi
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
if [ "${L4LOAD_BGP_TRAFFIC:-1}" = 7 ] || [ "${L4LOAD_BGP_TRAFFIC:-1}" = 8 ]; then
    systemctl stop l4load-routed@d1.service
    wait_route 10.1.2.2 installed-stopped
    systemctl start l4load-routed@d1.service
    wait_route 10.1.1.2 installed-restarted
    systemctl show l4load-routed@d1.service -p ActiveState -p MainPID -p NRestarts > "$out/installed-restarted.txt"
    ip netns exec l4-client python3 lab/katran/scenario.py check b1 > "$out/traffic-installed-restarted.json"
    ! grep -q Traceback "$out/health1.jsonl"
    if [ "${L4LOAD_BGP_TRAFFIC:-1}" = 8 ]; then
        before=$(grep -c '"action": "enable"' "$out/health2.jsonl" || true)
        systemctl stop l4load-routed@d2.service
        systemctl start l4load-routed@d2.service
        systemctl is-active --quiet l4load-routed@d2.service l4load-ipvs@d2.service
        for attempt in $(seq 1 100); do
            after=$(grep -c '"action": "enable"' "$out/health2.jsonl" || true)
            if [ "$after" -gt "$before" ]; then break; fi
            sleep 0.1
        done
        test "$after" -gt "$before"
        ip netns exec l4-client python3 lab/katran/scenario.py check b1 > "$out/traffic-secondary-restarted.json"
        ! grep -q Traceback "$out/health2.jsonl"
        before=$(grep -c '"action": "enable"' "$out/health2.jsonl" || true)
        systemctl restart l4load-ipvs@d2.service
        ! systemctl is-active --quiet l4load-routed@d2.service
        systemctl start l4load-routed@d2.service
        systemctl is-active --quiet l4load-routed@d2.service l4load-ipvs@d2.service
        for attempt in $(seq 1 100); do
            after=$(grep -c '"action": "enable"' "$out/health2.jsonl" || true)
            if [ "$after" -gt "$before" ]; then break; fi
            sleep 0.1
        done
        test "$after" -gt "$before"
        ip netns exec l4-client python3 lab/katran/scenario.py check b1 > "$out/traffic-base-restarted.json"
        systemctl show l4load-routed@d2.service l4load-ipvs@d2.service -p ActiveState -p MainPID -p NRestarts > "$out/installed-final-d2.txt"
        ! grep -q Traceback "$out/health2.jsonl"
        echo invalid-keepalived-config > "$out/ipvs-invalid.conf"
        if bash profiles/ipvs/update.sh "$out/ipvs-invalid.conf" d2; then exit 1; fi
        cmp "$out/ipvs.conf" /etc/l4load/ipvs-d2.conf
        sed 's@path /health@path /missing@g' "$out/ipvs.conf" > "$out/ipvs-drain.conf"
        before=$(grep -c '"action": "disable"' "$out/health2.jsonl" || true)
        bash profiles/ipvs/update.sh "$out/ipvs-drain.conf" d2
        for attempt in $(seq 1 100); do
            ip netns exec l4-d2 ipvsadm -Sn > "$out/ipvs-drained.txt"
            after=$(grep -c '"action": "disable"' "$out/health2.jsonl" || true)
            if [ "$(grep -c -- '-w 0' "$out/ipvs-drained.txt")" -ge 2 ] && [ "$after" -gt "$before" ]; then break; fi
            sleep 0.1
        done
        test "$(grep -c -- '-w 0' "$out/ipvs-drained.txt")" -ge 2 && test "$after" -gt "$before"
        before=$(grep -c '"action": "enable"' "$out/health2.jsonl" || true)
        bash profiles/ipvs/update.sh "$out/ipvs.conf" d2
        for attempt in $(seq 1 100); do
            ip netns exec l4-d2 ipvsadm -Sn > "$out/ipvs-rollback.txt"
            after=$(grep -c '"action": "enable"' "$out/health2.jsonl" || true)
            if [ "$(grep -c -- '-w 1' "$out/ipvs-rollback.txt")" -ge 2 ] && [ "$after" -gt "$before" ]; then break; fi
            sleep 0.1
        done
        test "$(grep -c -- '-w 1' "$out/ipvs-rollback.txt")" -ge 2 && test "$after" -gt "$before"
        cmp "$out/ipvs.conf" /etc/l4load/ipvs-d2.conf
        ip netns exec l4-p2 python3 lab/filter/probe.py 10.2.2.2 pass > "$out/probe-rollback.jsonl"
        ip netns exec l4-client python3 lab/katran/scenario.py check b1 > "$out/traffic-rollback.json"
        cat > /run/systemd/system/l4load-ipvs@d2.service.d/reject.conf <<'UNIT'
[Service]
ExecReload=
ExecReload=/bin/false
UNIT
        systemctl daemon-reload
        if bash profiles/ipvs/update.sh "$out/ipvs-drain.conf" d2; then exit 1; fi
        cmp "$out/ipvs.conf" /etc/l4load/ipvs-d2.conf
        rm /run/systemd/system/l4load-ipvs@d2.service.d/reject.conf
        systemctl daemon-reload
        ip netns exec l4-p2 python3 lab/filter/probe.py 10.2.2.2 pass > "$out/probe-rejected-reload.jsonl"
        ip netns exec l4-client python3 lab/katran/scenario.py check b1 > "$out/traffic-rejected-reload.json"
    fi
fi
echo BGP_HEALTH_TRAFFIC_PASS
