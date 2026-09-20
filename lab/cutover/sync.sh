ip link add sync0 netns l4-lb type veth peer name sync0 netns l4-alt
ip -n l4-lb addr add 10.254.0.1/30 dev sync0
ip -n l4-alt addr add 10.254.0.2/30 dev sync0
for ns in l4-lb l4-alt; do
    ip -n "$ns" link set sync0 up
    ip netns exec "$ns" sysctl -qw 'net.ipv4.vs.sync_threshold=0 1'
    ip netns exec "$ns" sysctl net.ipv4.vs.sync_threshold > "$out/$ns-sync.txt"
done
sender=l4-lb
receiver=l4-alt
ip netns exec "$receiver" ipvsadm --start-daemon backup --mcast-interface sync0 --syncid 42
ip netns exec "$sender" ipvsadm --start-daemon master --mcast-interface sync0 --syncid 42
sync_handoff() {
    local ready=false
    for attempt in $(seq 1 100); do
        ip netns exec "$sender" ipvsadm -Lnc > "$out/sync-source-$stage.txt"
        ip netns exec "$receiver" ipvsadm -Lnc > "$out/sync-target-$stage.txt"
        if python3 - "$out/sync-source-$stage.txt" "$out/sync-target-$stage.txt" <<'PY'
import sys
def connections(path):
    return {tuple(r[3:6]) for line in open(path) if len(r := line.split()) >= 6
            and r[0] == 'TCP' and r[2] == 'ESTABLISHED'}
source, target = map(connections, sys.argv[1:])
sys.exit(not (len(source) >= 4 and source <= target))
PY
        then ready=true; break; fi
        sleep 0.1
    done
    test "$ready" = true || return 1
    ip netns exec "$sender" ipvsadm --stop-daemon master
    ip netns exec "$receiver" ipvsadm --stop-daemon backup
    ip netns exec "$sender" ipvsadm --start-daemon backup --mcast-interface sync0 --syncid 42
    ip netns exec "$receiver" ipvsadm --start-daemon master --mcast-interface sync0 --syncid 42
    local previous=$sender
    sender=$receiver
    receiver=$previous
}
