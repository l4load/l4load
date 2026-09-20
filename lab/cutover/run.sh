! ip netns list | cut -d ' ' -f 1 | grep -qx l4-alt
ip netns add l4-alt
cutover_ns=1
ip -n l4-alt link set lo up
ip netns exec l4-alt sysctl -qw net.ipv4.conf.all.rp_filter=0 net.ipv4.conf.default.rp_filter=0 net.ipv4.ip_forward=1
connect l4-alt 4
ip -n l4-alt addr add 198.18.0.1/32 dev lo
ip netns exec l4-lb ipvsadm -Sn | ip netns exec l4-alt ipvsadm -R
for ns in l4-lb l4-alt; do
    ip netns exec "$ns" sysctl net.ipv4.vs.sloppy_tcp net.ipv4.vs.conn_reuse_mode > "$out/$ns-sysctl.txt"
    ip netns exec "$ns" ipvsadm -Sn > "$out/$ns-config.txt"
done
if [ "${L4LOAD_SYNC:-0}" = 1 ]; then source lab/cutover/sync.sh; fi
stages=(baseline cutover rollback done)
if [ "${L4LOAD_SYNC_LOSS:-0}" = 1 ]; then
    test "${L4LOAD_SYNC:-0}" = 1
    ip -n l4-lb link set sync0 down
    stages=(baseline rejected restored cutover rollback done)
fi
: > "$out/cutover-phase"
ip netns exec l4-client python3 -u lab/cutover/probe.py "$out" > "$out/cutover.jsonl" 2>&1 &
probe=$!
pids+=("$probe")
port=40000
for stage in "${stages[@]}"; do
    if [ "$stage" = restored ]; then ip -n l4-lb link set sync0 up; fi
    if [ "$stage" = rejected ]; then
        if sync_handoff; then echo 'incomplete sync accepted'; exit 1; fi
        ip -n l4-router route get 198.18.0.1 > "$out/route-after-rejection.txt"
        cmp "$out/route-baseline.txt" "$out/route-after-rejection.txt"
        test "$sender" = l4-lb && test "$receiver" = l4-alt
    fi
    if [ "${L4LOAD_SYNC:-0}" = 1 ] && { [ "$stage" = cutover ] || [ "$stage" = rollback ]; }; then
        sync_handoff
    fi
    case "$stage" in
        cutover) ip -n l4-router route replace 198.18.0.1/32 via 10.0.4.2 ;;
        rollback) ip -n l4-router route replace 198.18.0.1/32 via 10.0.1.2 ;;
    esac
    ip -n l4-router route get 198.18.0.1 > "$out/route-$stage.txt"
    echo "$stage" > "$out/cutover-phase"
    for attempt in $(seq 1 300); do
        if [ -f "$out/cutover-$stage" ]; then break; fi
        kill -0 "$probe" || { cat "$out/cutover.jsonl"; exit 1; }
        sleep 0.1
    done
    test -f "$out/cutover-$stage"
    ip netns exec l4-client python3 lab/katran/scenario.py check b1,b2 "$port" | tee "$out/fresh-$stage.json"
    for ns in l4-lb l4-alt; do
        ip netns exec "$ns" ipvsadm -Lnc > "$out/connections-$ns-$stage.txt"
    done
    port=$((port + 1000))
done
wait "$probe"
cat "$out/cutover.jsonl"
python3 - "$out/cutover.jsonl" "${L4LOAD_SYNC:-0}" "${L4LOAD_SYNC_LOSS:-0}" <<'PY'
import json, sys
rows = [json.loads(line) for line in open(sys.argv[1])]
loss = sys.argv[3] == '1'
assert [r['phase'] for r in rows] == (['baseline', 'rejected', 'restored', 'cutover', 'rollback', 'done'] if loss else ['baseline', 'cutover', 'rollback', 'done'])
assert all(set(r['fresh']) == {'b1', 'b2'} for r in rows[:-1])
assert [len(r['retained']) for r in rows] == ([0, 4, 8, 12, 16, 20] if loss else [0, 4, 8, 12])
if sys.argv[2] == '1':
    assert all(s['status'] == 'pass' for r in rows for s in r['retained']), rows
    print('SYNC_LOSS_RECOVERED' if loss else 'SYNC_CUTOVER_PASS')
print('CUTOVER_OBSERVATION_COMPLETE')
PY
