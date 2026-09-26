echo done > "$out/session-phase"
wait_session done
wait "$retained"
ip -n l4-lb link set sync0 down
ip -n l4-alt link set sync0 down
ip netns exec l4-client python3 -u lab/cutover/stale.py "$out" > "$out/stale-client.log" 2>&1 &
stale=$!
pids+=("$stale")
for attempt in $(seq 1 100); do
    if [ -f "$out/stale-ready.json" ]; then break; fi
    kill -0 "$stale" || { cat "$out/stale-client.log"; exit 1; }
    sleep 0.1
done
test -f "$out/stale-ready.json"
port=$(python3 -c 'import json,sys; print(json.load(open(sys.argv[1]))["source_port"])' "$out/stale-ready.json")
for ns in l4-lb l4-alt; do
    ip netns exec "$ns" ipvsadm -Lnc > "$out/stale-before-$ns.txt"
done
grep -q "10.0.0.2:$port " "$out/stale-before-l4-lb.txt"
! grep -q "10.0.0.2:$port " "$out/stale-before-l4-alt.txt"
ip netns exec l4-lb nft -f - <<'NFT'
table netdev fault {
    chain ingress {
        type filter hook ingress device "ha0" priority -500; policy accept;
        ip daddr 198.18.0.1 counter drop
    }
}
NFT
python3 -c 'import time; print(time.monotonic())' > "$out/stale-fault-start.txt"
wait_vip l4-alt l4-lb
record_vip sync-loss-failover
for ns in l4-lb l4-alt; do
    ip netns exec "$ns" ipvsadm -Ln --daemon > "$out/sync-daemon-failover-$ns.txt"
done
ip netns exec l4-client python3 lab/filter/probe.py 10.0.0.2 pass > "$out/stale-fresh.jsonl"
python3 - "$out" <<'PY'
import json, sys, time
from pathlib import Path
out=Path(sys.argv[1])
(out/'stale-fresh-time.json').write_text(json.dumps({'failure_to_verified_recovery_seconds':time.monotonic()-float((out/'stale-fault-start.txt').read_text())})+'\n')
PY
touch "$out/stale-trigger"
wait "$stale"
cat "$out/stale-result.json"
echo HA_SYNC_LOSS_OBSERVED
