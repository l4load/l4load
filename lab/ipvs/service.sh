unit=l4load-ipvs.service
test "$(systemctl show "$unit" -p LoadState --value)" = not-found
for file in /etc/l4load/ipvs.conf /etc/l4load/next.conf /usr/local/libexec/l4load-ipvs-gate.py /etc/systemd/system/$unit /run/systemd/system/$unit.d; do
    test ! -e "$file"
done
packaged_state=$(systemctl is-enabled keepalived.service || true)
if bash profiles/ipvs/install.sh "$out/invalid.conf"; then
    echo 'invalid installation accepted'
    exit 1
fi
test "$(systemctl is-enabled keepalived.service || true)" = "$packaged_state"
for file in /etc/l4load/ipvs.conf /usr/local/libexec/l4load-ipvs-gate.py /etc/systemd/system/$unit; do
    test ! -e "$file"
done
kill -TERM "$controller"
wait "$controller"
unitfile=/etc/systemd/system/$unit
bash profiles/ipvs/install.sh "$out/keepalived.conf"
if bash profiles/ipvs/install.sh "$out/drain.conf"; then
    echo 'existing installation overwritten'
    exit 1
fi
cmp "$out/keepalived.conf" /etc/l4load/ipvs.conf
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
ip netns exec l4-client python3 lab/katran/scenario.py check b2 15000 | tee "$out/service-recovered.json"
systemctl show "$unit" -p ActiveState -p MainPID -p NRestarts > "$out/service-state.txt"
test "$(systemctl show "$unit" -p NRestarts --value)" -ge 1
cp "$unitfile" "$out/service.txt"
start_health 1
wait_weight 1
if bash profiles/ipvs/update.sh "$out/invalid.conf"; then
    echo 'invalid update accepted'
    exit 1
fi
cmp "$out/original.conf" /etc/l4load/ipvs.conf
systemctl restart "$unit"
wait_weight 1
wait_weight 1 10.0.3.2:8080
cat > /run/systemd/system/$unit.d/reject.conf <<'UNIT'
[Service]
ExecReload=
ExecReload=/bin/false
UNIT
systemctl daemon-reload
if bash profiles/ipvs/update.sh "$out/drain.conf"; then
    echo 'failed reload reported success'
    exit 1
fi
cmp "$out/original.conf" /etc/l4load/ipvs.conf
rm /run/systemd/system/$unit.d/reject.conf
systemctl daemon-reload
wait_weight 1
wait_weight 1 10.0.3.2:8080
install -m 600 "$out/invalid.conf" /etc/l4load/ipvs.conf
if systemctl reload "$unit"; then
    echo 'invalid service reload accepted'
    exit 1
fi
systemctl is-active --quiet "$unit"
wait_weight 1
wait_weight 1 10.0.3.2:8080
for candidate in drain original; do
    bash profiles/ipvs/update.sh "$out/$candidate.conf"
    if [ "$candidate" = drain ]; then
        wait_weight 0
        phase service-drained
        ip netns exec l4-client python3 lab/katran/scenario.py check b2 16000 | tee "$out/service-drained.json"
    else
        wait_weight 1
        phase service-restored
        ip netns exec l4-client python3 lab/katran/scenario.py check b1,b2 17000 | tee "$out/service-restored.json"
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
    ip netns exec l4-client python3 lab/katran/scenario.py check b1,b2 18000 | tee "$out/package-reinstalled.json"
    systemctl restart "$unit"
    after_pid=$(systemctl show "$unit" -p MainPID --value)
    test "$after_pid" -gt 1 && test "$after_pid" != "$before_pid"
    wait_weight 1
    wait_weight 1 10.0.3.2:8080
    phase package-restarted
    ip netns exec l4-client python3 lab/katran/scenario.py check b1,b2 19000 | tee "$out/package-restarted.json"
    systemctl show "$unit" -p ActiveState -p MainPID > "$out/package-service.txt"
    echo PACKAGE_REINSTALL_PASS
fi
if [ -f "$out/upgrade.deb" ]; then
    port=27000
    client_index=3
    for stage in upgrade rollback; do
        package="$out/upgrade.deb"
        if [ "$stage" = rollback ]; then
            package=$(compgen -G "$out/keepalived_*.deb")
        fi
        expected=$(dpkg-deb -f "$package" Version)
        test "$expected" != "$(dpkg-query -W -f='${Version}' keepalived)"
        before_pid=$(systemctl show "$unit" -p MainPID --value)
        phase "package-$stage-installing"
        timeout --kill-after=5s 45s dpkg -i "$package" > "$out/$stage-install.txt" 2>&1
        test "$(dpkg-query -W -f='${Version}' keepalived)" = "$expected"
        test "$(systemctl is-enabled keepalived.service)" = masked
        test "$(systemctl show keepalived.service -p MainPID --value)" = 0
        test "$(systemctl show "$unit" -p MainPID --value)" = "$before_pid"
        systemctl restart "$unit"
        after_pid=$(systemctl show "$unit" -p MainPID --value)
        test "$after_pid" -gt 1 && test "$after_pid" != "$before_pid"
        for attempt in $(seq 1 100); do
            if cmp -s /usr/sbin/keepalived "/proc/$after_pid/exe"; then break; fi
            sleep 0.05
        done
        cmp /usr/sbin/keepalived "/proc/$after_pid/exe"
        dpkg-query -W keepalived > "$out/$stage-version.txt"
        /usr/sbin/keepalived --version > "$out/$stage-build.txt" 2>&1
        wait_weight 1
        wait_weight 1 10.0.3.2:8080
        phase "package-$stage-restarted"
        client="10.0.0.$client_index"
        ip -n l4-client addr add "$client/24" dev eth0
        ip netns exec l4-client env L4LOAD_CLIENT="$client" python3 lab/katran/scenario.py check b1,b2 "$port" | tee "$out/$stage-flows.json"
        port=$((port + 1000))
        client_index=$((client_index + 1))
    done
    dpkg-query -W keepalived > "$out/rollback-after.txt"
    cmp "$out/package-before.txt" "$out/rollback-after.txt"
    echo PACKAGE_UPGRADE_ROLLBACK_PASS
fi
