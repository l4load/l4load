#!/usr/bin/env bash
set -euo pipefail
out=$(realpath -m "${1:?output directory}")
mkdir -p "$out"
date -u +%FT%TZ > "$out/started.txt"
sockperf --version > "$out/version.txt" 2>&1
uname -a > "$out/kernel.txt"
lscpu > "$out/cpu.txt"
lscpu -e=CPU,CORE,SOCKET,NODE,ONLINE > "$out/topology.txt"
taskset -pc $$ > "$out/affinity.txt"
placement=()
if [ -n "${L4LOAD_CPUS:-}" ]; then
    taskset -c "$L4LOAD_CPUS" true
    placement=(taskset -c "$L4LOAD_CPUS")
fi
printf '%s\n' "${L4LOAD_CPUS:-inherited}" > "$out/workload-cpus.txt"
cat /proc/self/cgroup > "$out/cgroup.txt"
for name in cpu.max memory.max cpuset.cpus.effective; do
    if [ -r "/sys/fs/cgroup/$name" ]; then
        cat "/sys/fs/cgroup/$name" > "$out/$name.txt"
    fi
done
dpkg-query -W sockperf > "$out/packages.txt"
pids=()
cleanup() {
    for pid in "${pids[@]}"; do kill "$pid" 2>/dev/null || true; wait "$pid" 2>/dev/null || true; done
}
trap cleanup EXIT
for protocol in udp tcp; do
    flags=()
    if [ "$protocol" = tcp ]; then flags+=(--tcp); fi
    for backend in 1 2; do
        "${placement[@]}" ip netns exec "l4-b$backend" sockperf server -i 198.18.0.1 -p 8080 "${flags[@]}" > "$out/server-$protocol-$backend.txt" 2>&1 &
        pids+=("$!")
    done
    sleep 1
    for pid in "${pids[@]}"; do
        kill -0 "$pid"
        taskset -pc "$pid" >> "$out/server-affinity.txt"
    done
    for repeat in 1 2 3; do
        for rate in 1000 10000; do
            name="$protocol-$rate-$repeat"
            timeout --kill-after=2s 20s "${placement[@]}" ip netns exec l4-client sockperf under-load \
                -i 198.18.0.1 -p 8080 "${flags[@]}" -m 64 -t 5 --mps "$rate" \
                --reply-every 1 --full-rtt --full-log "$out/$name.csv" > "$out/$name.txt" 2>&1
        done
    done
    cleanup
    pids=()
done
python3 lab/load/summarize.py "$out" | tee "$out/summary.json"
echo SOCKPERF_TRIAL_DONE
