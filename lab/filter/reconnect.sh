mkdir "$out/source"
openssl req -x509 -newkey rsa:2048 -nodes -days 1 -subj /CN=filter-lab \
    -addext 'subjectAltName=IP:10.0.0.2' -keyout "$out/source/key.pem" -out "$out/source/cert.pem" 2>/dev/null
start_source() {
    ip netns exec l4-client python3 lab/filter/https.py "$out/source" "$out/source/cert.pem" "$out/source/key.pem" >> "$out/source.log" 2>&1 &
    source_pid=$!
    pids+=("$source_pid")
    for attempt in $(seq 1 50); do
        if ip netns exec l4-lb curl --noproxy '*' --cacert "$out/source/cert.pem" -fsS --max-time 1 https://10.0.0.2:9443/pairs.json >/dev/null 2>&1; then return; fi
        kill -0 "$source_pid"
        sleep 0.1
    done
    return 1
}
pull_snapshot() {
    ip netns exec l4-lb env NO_PROXY='*' CURL_CA_BUNDLE="$out/source/cert.pem" bash profiles/nftables/pull.sh https://10.0.0.2:9443/pairs.json
}
echo '[["10.0.0.3", "198.18.0.1"]]' > "$out/source/pairs.json"
start_source
pull_snapshot
probe 10.0.0.3 drop
probe 10.0.0.2 pass
if ip netns exec l4-lb env -u CURL_CA_BUNDLE -u SSL_CERT_FILE -u SSL_CERT_DIR NO_PROXY='*' bash profiles/nftables/pull.sh https://10.0.0.2:9443/pairs.json; then
    echo 'untrusted certificate accepted'; exit 1
fi
if ip netns exec l4-lb env NO_PROXY='*' CURL_CA_BUNDLE="$out/source/cert.pem" bash profiles/nftables/pull.sh https://10.0.0.2:9443/partial; then
    echo 'truncated response accepted'; exit 1
fi
probe 10.0.0.3 drop
probe 10.0.0.2 pass
kill "$source_pid"
wait "$source_pid" || true
if pull_snapshot; then echo 'disconnected source accepted'; exit 1; fi
probe 10.0.0.3 drop
probe 10.0.0.2 pass
echo '[[' > "$out/source/pairs.json"
start_source
if pull_snapshot; then echo 'malformed source accepted'; exit 1; fi
probe 10.0.0.3 drop
probe 10.0.0.2 pass
echo '[]' > "$out/source/pairs.json"
pull_snapshot
probe 10.0.0.3 pass
probe 10.0.0.2 pass
kill "$source_pid"
wait "$source_pid" || true
rm -f "$out/source/key.pem"
echo FILTER_RECONNECT_PASS
