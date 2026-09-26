if [ "${L4LOAD_SYNC:-0}" = 1 ]; then
    source lab/cutover/sync.sh
    echo baseline > "$out/session-phase"
    ip netns exec l4-client env L4LOAD_SESSION_TIMEOUT=10 python3 -u lab/ipvs/sessions.py "$out" > "$out/failure-sessions.jsonl" 2>&1 &
    retained=$!
    pids+=("$retained")
    wait_session() {
        for attempt in $(seq 1 150); do
            if [ -f "$out/session-$1" ]; then return 0; fi
            kill -0 "$retained" || { cat "$out/failure-sessions.jsonl"; return 1; }
            sleep 0.1
        done
        return 1
    }
    wait_session baseline
    sync_minimum=2 stage=prepared
    sync_handoff
fi
probe_path() { ip netns exec l4-client python3 lab/filter/probe.py 10.0.0.2 "$1"; }
probe_path pass
kill -0 "$controller"
ip netns exec l4-lb nft -f - <<'NFT'
table netdev fault {
    chain ingress {
        type filter hook ingress device "eth0" priority -500; policy accept;
        ip daddr 198.18.0.1 counter drop
    }
}
NFT
python3 -c 'import time; print(time.monotonic())' > "$out/failure-start.txt"
probe_path drop | tee "$out/failure-detected.jsonl"
kill -0 "$controller"
ip netns exec l4-lb ipvsadm -Sn > "$out/failure-ipvs.txt"
ip netns exec l4-lb nft -j list table netdev fault > "$out/failure-rules.json"
ip -n l4-router route replace 198.18.0.1/32 via 10.0.4.2
probe_path pass | tee "$out/failure-recovered.jsonl"
if [ "${L4LOAD_SYNC:-0}" = 1 ]; then
    echo recovered > "$out/session-phase"
    wait_session recovered
fi
python3 - "$out" <<'PY'
import json, sys, time
from pathlib import Path
out = Path(sys.argv[1])
elapsed = time.monotonic() - float((out / 'failure-start.txt').read_text())
(out / 'failure-timing.json').write_text(json.dumps({'failure_to_verified_recovery_seconds': elapsed}) + '\n')
rules = json.loads((out / 'failure-rules.json').read_text())['nftables']
assert sum(e['counter']['packets'] for r in rules if 'rule' in r for e in r['rule']['expr'] if 'counter' in e) >= 2
PY
ip netns exec l4-lb nft delete table netdev fault
if [ "${L4LOAD_SYNC:-0}" = 1 ]; then
    stage=return
    sync_handoff
fi
ip -n l4-router route replace 198.18.0.1/32 via 10.0.1.2
probe_path pass | tee "$out/failure-restored.jsonl"
kill -0 "$controller"
echo FORWARDING_FAILURE_RECOVERY_PASS
if [ "${L4LOAD_SYNC:-0}" = 1 ]; then
    echo done > "$out/session-phase"
    wait_session done
    wait "$retained"
    cat "$out/failure-sessions.jsonl"
    echo RETAINED_FAILURE_RECOVERY_PASS
fi
