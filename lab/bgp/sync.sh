ip link add sync0 netns l4-d1 type veth peer name sync0 netns l4-d2
for n in 1 2; do
    ip -n "l4-d$n" addr add "10.254.0.$n/30" dev sync0
    ip -n "l4-d$n" link set sync0 up
    ip netns exec "l4-d$n" sysctl -qw 'net.ipv4.vs.sync_threshold=0 1'
done
ip netns exec l4-d2 ipvsadm --start-daemon backup --mcast-interface sync0 --syncid 42
if [ "${L4LOAD_BGP_TRAFFIC:-1}" != 7 ]; then
    ip netns exec l4-d1 ipvsadm --start-daemon master --mcast-interface sync0 --syncid 42
fi
if [ "${L4LOAD_BGP_TRAFFIC:-1}" = 6 ] || [ "${L4LOAD_BGP_TRAFFIC:-1}" = 7 ]; then
    if [ "${L4LOAD_BGP_TRAFFIC:-1}" = 6 ]; then ip netns exec l4-d1 ipvsadm --start-daemon backup --mcast-interface sync0 --syncid 42; fi
    ip netns exec l4-d2 ipvsadm --start-daemon master --mcast-interface sync0 --syncid 42
    for n in 1 2; do ip netns exec "l4-d$n" ipvsadm -Ln --daemon > "$out/sync-daemons$n.txt"; done
fi
sync_ready() {
    local source=$1 target=$2 stage=$3
    for attempt in $(seq 1 100); do
        ip netns exec "$source" ipvsadm -Lnc > "$out/sync-source-$stage.txt"
        ip netns exec "$target" ipvsadm -Lnc > "$out/sync-target-$stage.txt"
        if grep -q 'ESTABLISHED.*10.0.0.2:12000' "$out/sync-target-$stage.txt"; then return; fi
        sleep 0.1
    done
    return 1
}
sync_swap() {
    local source=$1 target=$2
    ip netns exec "$source" ipvsadm --stop-daemon master
    ip netns exec "$target" ipvsadm --stop-daemon backup
    ip netns exec "$source" ipvsadm --start-daemon backup --mcast-interface sync0 --syncid 42
    ip netns exec "$target" ipvsadm --start-daemon master --mcast-interface sync0 --syncid 42
}
