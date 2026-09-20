unit=l4load-ipvs.service
test "$(systemctl show "$unit" -p LoadState --value)" = not-found
for file in /etc/l4load/ipvs.conf /etc/l4load/next.conf /usr/local/libexec/l4load-ipvs-gate.py /etc/systemd/system/$unit /run/systemd/system/$unit.d; do
    test ! -e "$file"
done
kill -TERM "$controller"
wait "$controller"
unitfile=/etc/systemd/system/$unit
install -D -m 600 "$out/keepalived.conf" /etc/l4load/ipvs.conf
install -D -m 644 profiles/ipvs/gate.py /usr/local/libexec/l4load-ipvs-gate.py
install -D -m 644 profiles/ipvs/l4load-ipvs.service "$unitfile"
mkdir -p /run/systemd/system/$unit.d
cat > /run/systemd/system/$unit.d/lab.conf <<UNIT
[Service]
NetworkNamespacePath=/run/netns/l4-lb
UNIT
systemd-analyze verify "$unitfile"
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
cp "$unitfile" "$out/service.txt"
start_health 1
wait_weight 1
install -m 600 "$out/invalid.conf" /etc/l4load/ipvs.conf
if systemctl reload "$unit"; then
    echo 'invalid service reload accepted'
    exit 1
fi
systemctl is-active --quiet "$unit"
wait_weight 1
wait_weight 1 10.0.3.2:8080
for candidate in drain original; do
    install -m 600 "$out/$candidate.conf" /etc/l4load/next.conf
    mv /etc/l4load/next.conf /etc/l4load/ipvs.conf
    systemctl reload "$unit"
    if [ "$candidate" = drain ]; then
        wait_weight 0
        phase service-drained
        ip netns exec l4-client python3 lab/katran/scenario.py check b2 34000 | tee "$out/service-drained.json"
    else
        wait_weight 1
        phase service-restored
        ip netns exec l4-client python3 lab/katran/scenario.py check b1,b2 35000 | tee "$out/service-restored.json"
    fi
done
cmp "$out/original.conf" /etc/l4load/ipvs.conf
systemctl cat "$unit" > "$out/installed-service.txt"
echo INSTALLED_SERVICE_PASS
if compgen -G "$out/keepalived_*.deb" > /dev/null; then
    test "$(systemctl is-enabled keepalived.service)" = masked
    before_pid=$(systemctl show "$unit" -p MainPID --value)
    dpkg-query -W keepalived > "$out/package-before.txt"
    sha256sum "$out"/keepalived_*.deb > "$out/package-sha256.txt"
    phase package-reinstalling
    timeout --kill-after=5s 45s dpkg -i "$out"/keepalived_*.deb > "$out/package-install.txt" 2>&1
    dpkg-query -W keepalived > "$out/package-after.txt"
    cmp "$out/package-before.txt" "$out/package-after.txt"
    test "$(systemctl is-enabled keepalived.service)" = masked
    if systemctl start keepalived.service; then
        echo 'packaged controller started'
        exit 1
    fi
    test "$(systemctl show keepalived.service -p MainPID --value)" = 0
    test "$(systemctl show "$unit" -p MainPID --value)" = "$before_pid"
    wait_weight 1
    wait_weight 1 10.0.3.2:8080
    phase package-reinstalled
    ip netns exec l4-client python3 lab/katran/scenario.py check b1,b2 36000 | tee "$out/package-reinstalled.json"
    systemctl restart "$unit"
    after_pid=$(systemctl show "$unit" -p MainPID --value)
    test "$after_pid" -gt 1 && test "$after_pid" != "$before_pid"
    wait_weight 1
    wait_weight 1 10.0.3.2:8080
    phase package-restarted
    ip netns exec l4-client python3 lab/katran/scenario.py check b1,b2 37000 | tee "$out/package-restarted.json"
    systemctl show "$unit" -p ActiveState -p MainPID > "$out/package-service.txt"
    echo PACKAGE_REINSTALL_PASS
fi
