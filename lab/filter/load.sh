#!/usr/bin/env bash
set -euo pipefail
out=$(realpath -m "${1:?output directory}")
mkdir -p "$out"
date -u +%FT%TZ > "$out/started.txt"
sockperf --version > "$out/version.txt" 2>&1
lscpu -e=CPU,CORE,SOCKET,NODE,ONLINE > "$out/topology.txt"
taskset -pc $$ > "$out/affinity.txt"
duration=5
denied_duration=12
if [ "${L4LOAD_FILTER_UPDATE:-0}" = 1 ]; then duration=70; denied_duration=80; fi
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
for repeat in 1 2 3; do
    for rate in 0 100000; do
        name="$repeat-$rate"
        date -u +%FT%TZ > "$out/$name-started.txt"
        if [ "${L4LOAD_FILTER_UPDATE:-0}" = 1 ]; then
            python3 lab/filter/update_trial.py "$out/$name-reset.json" 1
        fi
        if [ "$rate" != 0 ]; then
            timeout --kill-after=2s "$((denied_duration + 8))s" ip netns exec l4-client sockperf throughput \
                -i 198.18.0.1 -p 8080 --client_ip 10.0.0.3 -m 64 -t "$denied_duration" --mps "$rate" \
                > "$out/$name-denied.txt" 2>&1 &
            generator=$!
            pids+=("$generator")
            sleep 2
            kill -0 "$generator"
        fi
        ip -n l4-client -j -s link show eth0 > "$out/$name-before.json"
        timeout --kill-after=2s "$((duration + 10))s" ip netns exec l4-client sockperf under-load \
            -i 198.18.0.1 -p 8080 --client_ip 10.0.0.2 -m 64 -t "$duration" --mps 1000 \
            --reply-every 1 --full-rtt --full-log "$out/$name.csv" > "$out/$name.txt" 2>&1 &
        useful=$!
        pids+=("$useful")
        if [ "${L4LOAD_FILTER_UPDATE:-0}" = 1 ]; then
            sleep 2
            kill -0 "$useful"
            if [ "$rate" != 0 ]; then kill -0 "$generator"; fi
            python3 lab/filter/update_trial.py "$out/$name-update.json" 65536
            kill -0 "$useful"
            if [ "$rate" != 0 ]; then kill -0 "$generator"; fi
        fi
        wait "$useful"
        unset "pids[$((${#pids[@]} - 1))]"
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
