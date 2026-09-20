test "$mode" = af-packet
ip -n l4-client addr add 10.0.0.3/24 dev eth0
probe() { ip netns exec l4-client python3 lab/filter/probe.py "$@"; }
cp "$out/controlplane.conf" "$out/filter-original.conf"
probe 10.0.0.2 pass
probe 10.0.0.3 pass
python3 - "$out" <<'PY'
import json, sys
from pathlib import Path
out = Path(sys.argv[1])
config = json.loads((out / 'filter-original.conf').read_text())
rules = [':BEGIN', 'add deny ip from 10.0.0.3 to 198.18.0.1', 'add allow ip from any to any']
config['modules']['acl0']['firewall'] = rules
(out / 'filter-deny.conf').write_text(json.dumps(config))
config['modules']['acl0']['firewall'] = ['this is not a firewall rule']
(out / 'filter-invalid.conf').write_text(json.dumps(config))
PY
cp "$out/filter-deny.conf" "$out/controlplane.conf"
yanet-cli reload
probe 10.0.0.3 drop
probe 10.0.0.2 pass
cp "$out/filter-invalid.conf" "$out/controlplane.conf"
if yanet-cli reload; then
    echo 'invalid firewall accepted'
    exit 1
fi
probe 10.0.0.3 drop
probe 10.0.0.2 pass
cp "$out/filter-original.conf" "$out/controlplane.conf"
yanet-cli reload
probe 10.0.0.3 pass
probe 10.0.0.2 pass
echo YANET_FILTER_PASS
if [ "${L4LOAD_FILTER_LOAD:-0}" = 1 ]; then
    cp "$out/filter-deny.conf" "$out/controlplane.conf"
    yanet-cli reload
    for pid in "${backend_pids[@]}"; do kill "$pid"; wait "$pid" || true; done
    bash lab/filter/load.sh "$out/filter-load"
fi
