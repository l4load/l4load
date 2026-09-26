#!/usr/bin/env bash
set -euo pipefail
out=$(realpath -m "${1:?output directory}")
seconds=${L4LOAD_FILTER_LOAD_SECONDS:-5}
repeats=${L4LOAD_FILTER_LOAD_REPEATS:-3}
rates=${L4LOAD_FILTER_LOAD_RATES:-'0 100000'}
[[ "$seconds" =~ ^[0-9]+$ && "$repeats" =~ ^[0-9]+$ ]]
(( seconds >= 1 && seconds <= 300 && repeats >= 1 && repeats <= 3 ))
[[ -n "$rates" ]]
for rate in $rates; do [[ "$rate" = 0 || "$rate" = 100000 ]]; done
mkdir -p "$out"
date -u +%FT%TZ > "$out/started.txt"
sockperf --version > "$out/version.txt" 2>&1
lscpu -e=CPU,CORE,SOCKET,NODE,ONLINE > "$out/topology.txt"
taskset -pc $$ > "$out/affinity.txt"
pids=()
cleanup() {
    for pid in "${pids[@]}"; do kill "$pid" 2>/dev/null || true; wait "$pid" 2>/dev/null || true; done
}
trap cleanup EXIT
for backend in 1 2; do
    ip netns exec "l4-b$backend" sockperf server -i 198.18.0.1 -p 8080 > "$out/server-$backend.txt" 2>&1 &
    pids+=("$!")
done
sleep 1
for pid in "${pids[@]}"; do kill -0 "$pid"; done
for repeat in $(seq 1 "$repeats"); do
    for rate in $rates; do
        name="$repeat-$rate"
        date -u +%FT%TZ > "$out/$name-started.txt"
        cat /proc/stat > "$out/$name-cpu-before.txt"
        if [ "$rate" != 0 ]; then
            timeout --kill-after=2s "$((seconds + 17))s" ip netns exec l4-client sockperf throughput \
                -i 198.18.0.1 -p 8080 --client_ip 10.0.0.3 -m 64 -t "$((seconds + 7))" --mps "$rate" \
                > "$out/$name-denied.txt" 2>&1 &
            generator=$!
            pids+=("$generator")
            sleep 2
            kill -0 "$generator"
        fi
        ip -n l4-client -j -s link show eth0 > "$out/$name-before.json"
        timeout --kill-after=2s "$((seconds + 10))s" ip netns exec l4-client sockperf under-load \
            -i 198.18.0.1 -p 8080 --client_ip 10.0.0.2 -m 64 -t "$seconds" --mps 1000 \
            --reply-every 1 --full-rtt --full-log "$out/$name.csv" > "$out/$name.txt" 2>&1
        cat /proc/stat > "$out/$name-cpu-after.txt"
        ip -n l4-client -j -s link show eth0 > "$out/$name-after.json"
        if [ "$rate" != 0 ]; then
            kill -0 "$generator"
            wait "$generator"
            unset "pids[$((${#pids[@]} - 1))]"
        fi
    done
done
python3 lab/filter/summarize.py "$out" | tee "$out/summary.json"
echo FILTER_LOAD_OBSERVATION_COMPLETE
