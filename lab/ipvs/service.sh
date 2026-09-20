unit=l4load-ipvs-lab.service
test "$(systemctl show "$unit" -p LoadState --value)" = not-found
kill -TERM "$controller"
wait "$controller"
unitfile=/run/systemd/system/$unit
cat > "$unitfile" <<UNIT
[Unit]
Description=Disposable IPVS recovery trial
[Service]
Type=simple
NetworkNamespacePath=/run/netns/l4-lb
ExecStartPre=/usr/bin/bash $(pwd)/lab/ipvs/gate.sh
ExecStart=/usr/sbin/keepalived -n -l -C -I -f $out/keepalived.conf
Restart=on-failure
RestartSec=1
KillMode=control-group
UNIT
systemctl daemon-reload
systemctl start "$unit"
wait_weight 1
wait_weight 1 10.0.3.2:8080
kill "$first_health"
wait "$first_health" 2>/dev/null || true
wait_weight 0
old_pid=$(systemctl show "$unit" -p MainPID --value)
test "$old_pid" -gt 1
kill -KILL "$old_pid"
for attempt in $(seq 1 100); do
    new_pid=$(systemctl show "$unit" -p MainPID --value)
    if [ "$new_pid" -gt 1 ] && [ "$new_pid" != "$old_pid" ]; then break; fi
    sleep 0.1
done
test "$new_pid" -gt 1 && test "$new_pid" != "$old_pid"
wait_weight 0
wait_weight 1 10.0.3.2:8080
phase service-recovered
ip netns exec l4-client python3 lab/katran/scenario.py check b2 32000 | tee "$out/service-recovered.json"
systemctl show "$unit" -p ActiveState -p MainPID -p NRestarts > "$out/service-state.txt"
test "$(systemctl show "$unit" -p NRestarts --value)" -ge 1
journalctl -u "$unit" --no-pager > "$out/service.log"
cp "$unitfile" "$out/service.txt"
start_health 1
wait_weight 1
