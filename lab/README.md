# Virtual lab

Run on disposable Ubuntu x86_64:

```sh
sudo apt-get update
sudo apt-get install -y --no-install-recommends qemu-system-x86 busybox-static cpio
bash lab/run.sh
```

Go 1.26+, Python 3 and curl are required. The script uses sudo only to create a
console device inside a temporary directory. QEMU runs unprivileged with no host
network or disk access. The guest runs the Balance TCP tests over its own loopback.
Native Linux CI separately runs the race detector; the static guest binary does not.

Artifacts: serial.log and manifest.json in lab/results. The manifest records real
execution time, source revision, QEMU/toolchain, resources and image checksums.
The Alpine kernel URL may rotate; a checksum mismatch stops the run. Review and
repin explicitly instead of silently accepting a replacement. Test timings under
TCG are not hardware latency or throughput measurements.

## Baseline intake

baselines.json pins public sources; pinning does not mean a baseline was executed.
YANET's pinned demo uses two sock_dev unix-socket ports, four assigned cores,
2048 MiB, hugeMem=false and useKni=false. Its demo demonstrates routing/filtering,
not a completed Balance comparison. Its mutable builder image must be pinned and
its build recipe reviewed before adding an adapter. Katran and YANET2 are separate.

Next common packet case: IPv4 TCP to one VIP, two backends, IPIP/DSR, repeated tuples
preserve backend selection, unknown VIPs never reach a backend. Use only synthetic
addresses and packets. Verify outer/inner headers, checksums and delivery before
measuring speed. Current Balance TCP proxy does not implement this case.

Sources: [YANET demo](https://github.com/yanet-platform/yanet/tree/6b30c2f376c5148a661eadb57fd316d3b453e085/demo),
[QEMU](https://www.qemu.org/docs/master/system/invocation.html).
