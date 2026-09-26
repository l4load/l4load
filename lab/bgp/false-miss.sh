check=/etc/l4load/check-d1
cp "$check" "$out/check-original"
chmod 755 "$out/check-original"
cat > "$out/check-wrapper" <<EOF
#!/bin/sh
if [ -e "$out/probe-one" ]; then
    mv "$out/probe-one" "$out/probe-one-used"
    exit 1
fi
if [ -e "$out/probe-persist" ]; then exit 1; fi
exec "$out/check-original"
EOF
install -m 700 "$out/check-wrapper" "$check.next"
mv "$check.next" "$check"
before=$(grep -c '"action": "disable"' "$out/health1.jsonl" || true)
touch "$out/probe-one"
for attempt in $(seq 1 50); do
    test -e "$out/probe-one-used" && break
    sleep 0.1
done
test -e "$out/probe-one-used"
sleep 1
after=$(grep -c '"action": "disable"' "$out/health1.jsonl" || true)
test "$after" = "$before"
wait_route 10.1.1.2 single-miss
ip netns exec l4-client python3 lab/katran/scenario.py check b1 > "$out/traffic-single-miss.json"
touch "$out/probe-persist"
for attempt in $(seq 1 50); do
    after=$(grep -c '"action": "disable"' "$out/health1.jsonl" || true)
    test "$after" -gt "$before" && break
    sleep 0.1
done
test "$after" -gt "$before"
wait_route 10.1.2.2 persistent-miss
ip netns exec l4-client python3 lab/katran/scenario.py check b1 > "$out/traffic-persistent-miss.json"
rm "$out/probe-persist"
wait_route 10.1.1.2 recovered-miss
ip netns exec l4-client python3 lab/katran/scenario.py check b1 > "$out/traffic-recovered-miss.json"
test "$(systemctl is-active l4load-routed@d1.service)" = active
echo ROUTE_GATE_MISS_PASS
