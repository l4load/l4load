test "${L4LOAD_SYNC:-0}" = 0
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
ip -n l4-router route replace 198.18.0.1/32 via 10.0.1.2
probe_path pass | tee "$out/failure-restored.jsonl"
kill -0 "$controller"
echo FORWARDING_FAILURE_RECOVERY_PASS
