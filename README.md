# L4Load

Independent L4 networking tools. Experimental; not production-ready.

Balance currently provides a loopback TCP reference: round-robin, connect-only
fallback, half-close, connection limits and bounded shutdown. Shield, Pulse and
Fabric are planned. No comparative performance results are available yet.

## Try Balance

Requires Go 1.26+; Python 3 is used only for the demo backends and site generation.

```sh
go test -race ./...
go run ./cmd/l4load -config examples/local.json -check
go build -o bin/l4load ./cmd/l4load
```

In separate terminals, start two demo backends and the proxy:

```sh
python3 -m http.server 18081 --bind 127.0.0.1
python3 -m http.server 18082 --bind 127.0.0.1
./bin/l4load -config examples/local.json
```

Then run `curl http://127.0.0.1:18080/`. SIGINT/SIGTERM drains admitted sessions
and prints counters. `completed` counts finished handlers, not successful requests.

## Limits

Loopback endpoints only. Full TCP proxy: client source IP is not preserved.
Session timeout is a hard lifetime, not idle time. Configuration changes require
restart. There is no active health checking, UDP, DSR, reload, HA or DDoS protection.
JSON rejects unknown fields; repeated object keys follow Go's last-value semantics.

Next: safe configuration changes and a reproducible packet-level comparison lab.
See [benchmark criteria](docs/benchmarks.md) and the [QEMU lab](lab/README.md).
Tests do not establish performance.

## Site

`python3 scripts/build_site.py` builds `site/index.html` from this revision.
The site repository receives that generated file and its source revision.

Apache-2.0. See [LICENSE](LICENSE).
