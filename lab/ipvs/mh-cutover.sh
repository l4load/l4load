! ip netns list | cut -d ' ' -f 1 | grep -qx l4-alt
ip netns add l4-alt
cutover_ns=1
ip -n l4-alt link set lo up
ip netns exec l4-alt sysctl -qw net.ipv4.conf.all.rp_filter=0 net.ipv4.conf.default.rp_filter=0 net.ipv4.ip_forward=1
connect l4-alt 4
ip -n l4-alt addr add 198.18.0.1/32 dev lo
ip netns exec l4-lb ipvsadm -Sn | ip netns exec l4-alt ipvsadm -R
for ns in l4-lb l4-alt; do
    ip netns exec "$ns" ipvsadm -Sn > "$out/$ns-mh-state.txt"
    test "$(grep -c '^-[A] .* -s mh -p 300 -b mh-fallback,mh-port' "$out/$ns-mh-state.txt")" = 2
    ip netns exec "$ns" sysctl -qw net.ipv4.vs.expire_quiescent_template=1
done
source lab/cutover/sync.sh
for i in $(seq 2 9); do
    client="10.0.0.$i"
    if [ "$i" != 2 ]; then ip -n l4-client addr add "$client/24" dev eth0; fi
    ip netns exec l4-client env L4LOAD_CLIENT="$client" python3 lab/katran/scenario.py check one "$((30000+i*100))" > "$out/mh-before-$i.json"
done
for attempt in $(seq 1 50); do
    ip netns exec l4-alt ipvsadm -Lnc > "$out/mh-replica.txt"
    ready=true
    for i in $(seq 2 9); do
        if ! grep -q "10.0.0.$i:" "$out/mh-replica.txt"; then ready=false; break; fi
    done
    if [ "$ready" = true ]; then break; fi
    sleep 0.1
done
test "$ready" = true
ip -n l4-router route replace 198.18.0.1/32 via 10.0.4.2
ip -n l4-router route get 198.18.0.1 > "$out/mh-route-after.txt"
ip netns exec l4-lb ipvsadm --stop-daemon master
ip netns exec l4-alt ipvsadm --stop-daemon backup
ip netns exec l4-lb ipvsadm --start-daemon backup --mcast-interface sync0 --syncid 42
ip netns exec l4-alt ipvsadm --start-daemon master --mcast-interface sync0 --syncid 42
for i in $(seq 2 9); do
    ip netns exec l4-client env L4LOAD_CLIENT="10.0.0.$i" python3 lab/katran/scenario.py check one "$((40000+i*100))" > "$out/mh-after-$i.json"
done
python3 - "$out" <<'PY'
import json,sys
from pathlib import Path
out=Path(sys.argv[1])
for i in range(2,10):
    before=json.loads((out/f'mh-before-{i}.json').read_text())['flows']
    after=json.loads((out/f'mh-after-{i}.json').read_text())['flows']
    for protocol in ('tcp','udp'):
        assert set(before[protocol]) == set(after[protocol]), (i,protocol,before,after)
print(json.dumps({'status':'pass','clients':8,'protocols':['tcp','udp'],'affinity_preserved':True}))
PY
