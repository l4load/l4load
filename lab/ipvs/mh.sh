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
