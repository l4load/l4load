source lab/bgp/sync.sh
mkdir -p "$out/health"
echo healthy > "$out/health/health"
ip netns exec l4-b1 python3 -m http.server 9090 --directory "$out/health" --bind 10.0.2.2 > "$out/health.log" 2>&1 &
pids+=("$!")
cat > "$out/ipvs.conf" <<'CONF'
virtual_server 198.18.0.1 8080 {
    delay_loop 1
    lvs_sched rr
    lvs_method TUN
    protocol TCP
    alpha
    real_server 10.0.2.2 8080 {
        weight 1
        inhibit_on_failure
        HTTP_GET {
            url { path /health status_code 200 }
            connect_port 9090
            connect_timeout 1
            retry 1
            delay_before_retry 1
        }
    }
}
virtual_server 198.18.0.1 8080 {
    delay_loop 1
    lvs_sched rr
    lvs_method TUN
    protocol UDP
    alpha
    real_server 10.0.2.2 8080 {
        weight 1
        inhibit_on_failure
        HTTP_GET {
            url { path /health status_code 200 }
            connect_port 9090
            connect_timeout 1
            retry 1
            delay_before_retry 1
        }
    }
}
CONF
if [ "${L4LOAD_BGP_SOAK:-0}" = 1 ]; then
    for protocol in TCP UDP; do
        flags=()
        if [ "$protocol" = TCP ]; then flags+=(--tcp); fi
        ip netns exec l4-b1 sockperf server -i 198.18.0.1 -p 8081 "${flags[@]}" > "$out/soak-server-$protocol.log" 2>&1 &
        pids+=("$!")
        cat >> "$out/ipvs.conf" <<CONF
virtual_server 198.18.0.1 8081 {
    delay_loop 1
    lvs_sched rr
    lvs_method TUN
    protocol $protocol
    alpha
    real_server 10.0.2.2 8081 {
        weight 1
        inhibit_on_failure
        HTTP_GET {
            url { path /health status_code 200 }
            connect_port 9090
            connect_timeout 1
            retry 1
            delay_before_retry 1
        }
    }
}
CONF
    done
fi
systemctl stop bird.service keepalived.service || true
for n in 1 2; do
    cat > "$out/routed-d$n.json" <<JSON
{"vip":"198.18.0.1","local_ip":"10.1.$n.2","local_as":6500$n,"peer_ip":"10.1.$n.1","peer_as":65000,"sync_interface":"sync0","sync_id":42}
JSON
    cat > "$out/check-d$n" <<EOF
#!/bin/sh
exec env L4LOAD_PROBE_TIMEOUT=0.2 ip netns exec l4-p$n python3 "$PWD/lab/filter/probe.py" 10.2.$n.2 pass >/dev/null
EOF
    chmod 700 "$out/check-d$n"
    python3 profiles/ipvs/install-routed.py "d$n" "$out/routed-d$n.json" "$out/check-d$n" "$out/ipvs.conf"
    cp "/etc/l4load/bird-d$n.conf" "$out/installed-bird-d$n.conf"
    chmod 644 "$out/installed-bird-d$n.conf" "$out/check-d$n"
    for unit in l4load-ipvs l4load-routed; do
        mkdir -p "/run/systemd/system/$unit@d$n.service.d"
        cat > "/run/systemd/system/$unit@d$n.service.d/lab.conf" <<UNIT
[Service]
NetworkNamespacePath=/run/netns/l4-d$n
StandardOutput=append:$out/$unit-d$n.log
UNIT
    done
    ln -s "/run/l4load-routed-d$n/bird.ctl" "$out/d$n.ctl"
    ln -s "$out/l4load-routed-d$n.log" "$out/health$n.jsonl"
done
systemctl daemon-reload
for n in 2 1; do
    if ! systemctl start "l4load-routed@d$n.service"; then
        systemctl status -l --no-pager "l4load-routed@d$n.service" "l4load-ipvs@d$n.service" > "$out/installed-status-d$n.txt" 2>&1 || true
        journalctl -b --no-pager -u "l4load-routed@d$n.service" -u "l4load-ipvs@d$n.service" -n 100 > "$out/installed-journal-d$n.txt" 2>&1 || true
        exit 1
    fi
    wait_route "10.1.$n.2" "installed-d$n"
    for attempt in $(seq 1 100); do
        ip netns exec "l4-d$n" ipvsadm -Sn > "$out/installed-ipvs-d$n.txt"
        if [ "$(grep -c -- '-w 1' "$out/installed-ipvs-d$n.txt")" -ge 2 ]; then break; fi
        sleep 0.1
    done
    test "$(grep -c -- '-w 1' "$out/installed-ipvs-d$n.txt")" -ge 2
    systemctl show "l4load-routed@d$n.service" "l4load-ipvs@d$n.service" -p ActiveState -p MainPID -p BindsTo > "$out/installed-units-d$n.txt"
    systemctl show "l4load-routed@d$n.service" -p NRestarts --value > "$out/installed-restarts-d$n.txt"
    test "$(cat "$out/installed-restarts-d$n.txt")" = 0
done
