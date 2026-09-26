ip -n l4-client addr add 10.0.0.3/24 dev eth0
ip netns exec l4-lb nft --version > "$out/nft-version.txt"
nftlb() { ip netns exec l4-lb nft "$@"; }
probe() { ip netns exec l4-client python3 lab/filter/probe.py "$@"; }
nftlb -c -f profiles/nftables/filter.nft
nftlb -f profiles/nftables/filter.nft
probe 10.0.0.2 pass
probe 10.0.0.3 pass
nftlb 'add element netdev l4load blocked { 10.0.0.3 . 198.18.0.1 timeout 15s }'
probe 10.0.0.3 drop
probe 10.0.0.2 pass
nftlb -j list table netdev l4load > "$out/filter-blocked.json"
python3 - "$out/filter-blocked.json" <<'PY'
import json, sys
rows = json.load(open(sys.argv[1]))['nftables']
counters = [expr['counter']['packets'] for row in rows if 'rule' in row for expr in row['rule']['expr'] if 'counter' in expr]
assert sum(counters) >= 2, counters
PY
cat > "$out/filter-invalid.nft" <<'NFT'
add element netdev l4load blocked { 10.0.0.2 . 198.18.0.1 timeout 60s }
add element netdev l4load missing { 10.0.0.2 }
NFT
if nftlb -f "$out/filter-invalid.nft"; then
    echo 'invalid filter transaction accepted'
    exit 1
fi
probe 10.0.0.2 pass
probe 10.0.0.3 drop
sleep 16
probe 10.0.0.3 pass
probe 10.0.0.2 pass
nftlb -j list table netdev l4load > "$out/filter-expired.json"
snapshot() { ip netns exec l4-lb python3 profiles/nftables/snapshot.py; }
printf '%s\n' '[["10.0.0.3", "198.18.0.1"]]' | snapshot
probe 10.0.0.3 drop
probe 10.0.0.2 pass
if printf '%s\n' '[["10.0.0.2", "198.18.0.1"], ["bad", "198.18.0.1"]]' | snapshot; then
    echo 'invalid snapshot accepted'
    exit 1
fi
probe 10.0.0.3 drop
probe 10.0.0.2 pass
printf '%s\n' '[]' | snapshot
probe 10.0.0.3 pass
probe 10.0.0.2 pass
nftlb -j list table netdev l4load > "$out/filter-empty-snapshot.json"
echo FILTER_SNAPSHOT_PASS
nftlb delete table netdev l4load
probe 10.0.0.3 pass
echo FILTER_LIFECYCLE_PASS
if [ "${L4LOAD_FILTER_LOAD:-0}" = 1 ]; then
    nftlb -f profiles/nftables/filter.nft
    nftlb 'add element netdev l4load blocked { 10.0.0.3 . 198.18.0.1 }'
    for pid in "${backend_pids[@]}"; do kill "$pid"; wait "$pid" || true; done
    bash lab/filter/load.sh "$out/filter-load"
    nftlb -j list table netdev l4load > "$out/filter-load-counters.json"
fi
