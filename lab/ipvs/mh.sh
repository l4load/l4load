python3 - "$out/state.txt" <<'PY'
import sys
services = [line.split() for line in open(sys.argv[1]) if line.startswith('-A ')]
assert len(services) == 2, services
for service in services:
    assert service[service.index('-s') + 1] == 'mh', service
    flags = set()
    for i, token in enumerate(service):
        if token == '-b':
            flags.update(service[i + 1].split(','))
    assert flags == {'mh-port', 'mh-fallback'}, service
PY
ip netns exec l4-client python3 lab/katran/scenario.py check b1,b2 20000 | tee "$out/mh-healthy.json"
rm "$out/health1/health"
wait_weight 0
ip netns exec l4-client python3 lab/katran/scenario.py check b2 21000 | tee "$out/mh-fallback.json"
echo healthy > "$out/health1/health"
wait_weight 1
ip netns exec l4-client python3 lab/katran/scenario.py check b1,b2 22000 | tee "$out/mh-recovered.json"
sed -i '/mh-fallback/a\    persistence_timeout 300' "$out/keepalived.conf"
ip netns exec l4-lb keepalived -t -f "$out/keepalived.conf" > "$out/persistence-validation.txt" 2>&1
kill -HUP "$controller"
for attempt in $(seq 1 15); do
    ip netns exec l4-lb ipvsadm -Sn > "$out/persistent-state.txt"
    if [ "$(grep -c '^-[A] .* -p 300' "$out/persistent-state.txt")" = 2 ]; then break; fi
    sleep 1
done
test "$(grep -c '^-[A] .* -p 300' "$out/persistent-state.txt")" = 2
ip netns exec l4-client python3 lab/katran/scenario.py check one 23000 | tee "$out/persistent-healthy.json"
rm "$out/health1/health"
wait_weight 0
ip netns exec l4-client python3 lab/katran/scenario.py check b2 24000 | tee "$out/persistent-fallback.json"
