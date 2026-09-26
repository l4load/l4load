echo baseline > "$out/useful-phase"
ip -n l4-d1 link set sync0 down
ip netns exec l4-client env L4LOAD_SESSION_EXPECT_RESET=1 python3 -u lab/bgp/session.py "$out" > "$out/session.log" 2>&1 &
session_pid=$!
pids+=("$session_pid")
for attempt in $(seq 1 100); do
    if [ -f "$out/session-baseline" ]; then break; fi
    kill -0 "$session_pid" || { cat "$out/session.log"; exit 1; }
    sleep 0.1
done
test -f "$out/session-baseline"
sleep 1
ip netns exec l4-d2 ipvsadm -Lnc > "$out/stale-replica.txt"
! grep -q '10.0.0.2:12000' "$out/stale-replica.txt"
systemctl is-active --quiet l4load-routed@d2.service
ip -n l4-r route get 198.18.0.1 > "$out/route-before.txt"
grep -q 'via 10.1.1.2 ' "$out/route-before.txt"
touch "$out/route-health-withdrawn.txt"
systemctl stop l4load-routed@d1.service
wait_route 10.1.2.2 stale-failover
echo failover > "$out/useful-phase"
wait "$session_pid"
test -s "$out/session-reset.json"
ip netns exec l4-client python3 lab/katran/scenario.py check b1 > "$out/fresh-standby.json"
cat "$out/session-reset.json"
