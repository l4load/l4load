from pathlib import Path
import subprocess

root = Path(__file__).resolve().parents[1]
sha = subprocess.check_output(['git', 'rev-parse', 'HEAD'], cwd=root, text=True).strip()
page = '''<!doctype html>
<html lang="en">
<meta charset="utf-8">
<meta name="viewport" content="width=device-width,initial-scale=1">
<meta name="description" content="L4Load: independent tools for L4 networking. Reproducible experiments with existing dataplanes.">
<title>L4Load — L4 networking, made operable</title>
<style>
:root{color-scheme:dark;font:17px/1.7 system-ui;background:#0c1423;color:#e5ecf6}
body{max-width:920px;margin:auto;padding:48px 24px}a{color:#8bbcff}
header{border-bottom:1px solid #31415b;padding-bottom:40px}h1{font-size:clamp(44px,8vw,76px);line-height:1.1;margin:24px 0}
h2{font-size:24px;margin-top:40px}.eyebrow{color:#95afd0;letter-spacing:.12em;font-size:13px}
.grid{display:grid;grid-template-columns:repeat(auto-fit,minmax(190px,1fr));gap:16px}
article{border:1px solid #31415b;border-radius:8px;padding:20px}article h3{margin:0}
small,footer{color:#a9bad0}code{font-size:.9em}pre{padding:20px;background:#152238;overflow:auto;border-radius:8px}
footer{border-top:1px solid #31415b;margin-top:40px;padding-top:20px;font-size:14px}
</style>
<header><span class="eyebrow">L4LOAD / EXPERIMENTAL</span>
<h1>L4 networking,<br>made operable.</h1>
<p>Tools for teams that need to handle traffic without building a networking platform.</p>
<a href="https://github.com/l4load/l4load">Source &amp; quickstart ↗</a></header>
<main><h2>Start with a working dataplane.</h2>
<p><a href="https://github.com/l4load/l4load/tree/main/profiles/ipvs">Balance</a>
packages Linux IPVS and Keepalived into an installable IPv4 DSR profile with
backend health, drain, rollback and a tested two-node virtual HA recipe.
<a href="https://github.com/l4load/l4load/tree/main/profiles/nftables">Shield</a>
uses nftables for source/VIP filtering and atomic policy snapshots. Both reuse
packaged engines; neither is qualified for unrestricted production traffic.</p>
<p>Our separate Katran lab sends TCP and UDP through one IPv4 VIP to two IPIP
backends, checks replies and preserves the original client address without DPDK.</p>
<p><a href="https://github.com/l4load/l4load/tree/main/lab/katran">Run the Katran scenario ↗</a> ·
<a href="https://github.com/l4load/l4load/actions/workflows/katran.yml">Execution logs &amp; artifacts ↗</a></p>
<p>This is a functional Linux namespace test using generic XDP and static maps.
It is not a production deployment or a throughput result.</p>
<div class="grid">
<article><h3>Balance</h3><small>IPVS profile</small><p>Healthy forwarding, controlled changes and virtual HA.</p></article>
<article><h3>Shield</h3><small>nftables profile</small><p>Source/VIP policy with atomic snapshots.</p></article>
<article><h3>Pulse</h3><small>Planned</small><p>Traffic and failure analysis.</p></article>
<article><h3>Fabric</h3><small>Planned</small><p>Configuration and multi-site operation.</p></article>
</div>
<h2>Backend failure and recovery.</h2>
<p>The Keepalived/IPVS trial checks healthy, health-failed and recovered backends.
All 1024 IPv4 TCP/UDP exchanges passed, including HTTP health failure, rejected configuration, drain and rollback: new flows avoided the unhealthy backend and
returned to both backends after recovery, preserving client IP and payload.</p>
<p><a href="https://github.com/l4load/l4load/tree/main/lab/ipvs">Run the lifecycle trial ↗</a> ·
<a href="https://github.com/l4load/l4load/actions/runs/36161652255/job/108159407383">Verified execution ↗</a></p>
<p>The <a href="https://github.com/l4load/l4load/tree/main/profiles/ipvs">installable IPVS service</a>
passed supervisor recovery, rejected reload and configuration drain/rollback.
The lab installed the profile files with only a network-namespace override.
Two retained TCP sessions carried 706 exchanges each over 35.6 seconds.
Packages and networking were prepared for that installation trial.</p>
<p>A separate <a href="https://github.com/l4load/l4load/actions/runs/36167949921">Ubuntu VM boot trial</a>
passed two reboots with automatic service startup and 64 fresh TCP/UDP flows
after each boot. It used software emulation and an explicitly ordered synthetic
network service. Physical network startup, automatic failover and performance
remain unqualified.</p>
<p>The operator recipe and both installation labs now use one fresh-install script.
<a href="https://github.com/l4load/l4load/actions/runs/36172669218">Rejected installations</a>
preserved the existing configuration; the shared recipe also passed
<a href="https://github.com/l4load/l4load/actions/runs/36172669086">two VM reboots</a>
and 64 TCP/UDP flows after each. Independent operator acceptance remains open.</p>
<p>A separate <a href="https://github.com/l4load/l4load/actions/runs/36165653126">package upgrade and rollback trial</a>
passed Keepalived 2.2.8 → 2.3.2 → 2.2.8 with gated restarts, fresh TCP/UDP flows
and two retained TCP sessions carrying 913 exchanges each over 46.1 seconds.
The cross-release package tests these mechanics on a prepared runner; it is not
a supported distribution update recommendation.</p>
<p>Two established TCP sessions carried continuous low-rate requests through health exclusion, reload and gated controller recovery, including automatic systemd restart. Empty-table service startup also passed. Direct restart with retained state failed; the tested workaround pauses new flows until health is confirmed. Sustained load, host failure and HA remain unqualified.</p>
<p>A separate IPv6-over-IPv6 IPVS trial passed 192 TCP/UDP exchanges across
health-port failure and recovery with client addresses preserved. Two existing
IPv6 TCP sessions also survived those transitions in a short continuous-request
trial. IPv6 reload, restart and sustained traffic remain unqualified.</p>
<p>The packaged node_exporter IPVS collector correctly exposed backend weights
through health exclusion and recovery. Retention and alerts remain unqualified.</p>
<h2>Check applied state.</h2>
<p>Native <a href="https://github.com/l4load/l4load/actions/runs/36172967453">nftables</a>
and <a href="https://github.com/l4load/l4load/actions/runs/36174467560">YANET</a>
passed short IPv4 source/VIP filtering trials: deny one source, keep another
working, reject an invalid update and restore forwarding. The nftables rule
also expired without a controller; YANET removal was explicit.
Overload protection, filtering throughput and feature parity are not established.
<a href="https://github.com/l4load/l4load/tree/main/lab/filter">Reproduce the filter trial ↗</a></p>
<p>Full nftables snapshots now replace the deny set atomically, including empty
snapshots that clear old bans. In one matched virtual trial, applying 65,536 pairs
took 0.910 seconds for nftables and 44.466 seconds for YANET's native firewall
reload. The respective 174 and 8,407 probes sent during application all succeeded;
RTT p99 was 0.163 and 1.067 ms.
<a href="https://github.com/l4load/l4load/tree/main/lab/filter/results/2026-09-26-comparison">Raw samples and limits</a>
are preserved. This compares these update paths at low sequential traffic rates,
with no concurrent attack, not optimal tuning or forwarding capacity.</p>
<p>The <a href="https://github.com/l4load/l4load/tree/main/profiles/nftables">HTTPS snapshot helper</a>
keeps applied rules when the source disconnects, returns a truncated body or
malformed JSON, or fails certificate verification. A valid empty list clears bans.
It is a one-shot pull; scheduling, source freshness and version ordering remain
external responsibilities. Explicitly saved nonexpiring policy also passed
<a href="https://github.com/l4load/l4load/actions/runs/36227587895">two VM reboots with Balance</a>:
filter restoration preceded Balance startup; rollback and invalid-reload
retention passed. A <a href="https://github.com/l4load/l4load/actions/runs/36228365218">third reboot with invalid policy</a>
blocked Balance startup until the saved file was restored, after which traffic
checks passed. Physical-host ordering and runtime failure detection remain unqualified.</p>
<p>A <a href="https://github.com/l4load/l4load/tree/main/lab/filter/results/2026-09-26-load-updates">combined update/load trial</a>
applied 65,536 pairs under about 100,000 denied UDP messages/s. Application took
0.909 seconds for nftables and 37.224 seconds for YANET; useful-probe RTT p99
during the updates was 0.191 and 2.606 ms, with no observed loss. This is one
virtual run with sequential low-rate useful traffic, different native update paths
and whole-generator average rates, not a capacity or production-superiority claim.</p>
<p>At 1,000 requested useful UDP messages/s during six 65,536-pair updates,
nftables/IPVS reported no useful loss. YANET completed three intervals before
its control plane disappeared during the fourth; the virtual runner recorded
an OOM kill and a reload timeout. <a href="https://github.com/l4load/l4load/tree/main/lab/filter/results/2026-09-26-offered-failure">Measurements and limits</a>.
This incomplete paired trial does not establish forwarding capacity.</p>
<p>An <a href="https://github.com/l4load/l4load/actions/runs/36224483206">injected forwarding failure</a>
left Keepalived alive while TCP/UDP probes timed out. The lab harness redirected
new flows through a second director and verified recovery in 2.06 seconds,
including probe timeouts. This is orchestrated recovery, not autonomous HA or a
retained-session guarantee. A separate
<a href="https://github.com/l4load/l4load/actions/runs/36225087250">pre-synchronized TCP trial</a>
retained two sockets without reconnecting through the injected failure; one
exchange paused for 3.309 seconds. Its sequential client does not measure
independent per-flow stalls or establish uninterrupted service.</p>
<p>In a <a href="https://github.com/l4load/l4load/blob/main/lab/cutover/results/2026-09-26-vrrp.json">same-L2 VRRP trial</a>,
an external TCP/UDP probe detected an ingress blackhole while Keepalived's
backend checker stayed alive. The floating next-hop moved to the backup and
returned after recovery; fresh TCP/UDP checks passed. One virtual run took
3.590 seconds from injection to verified recovery. That run did not test
retained connections or physical failover.</p>
<p>In a <a href="https://github.com/l4load/l4load/blob/main/lab/cutover/results/2026-09-26-standby-health.json">standby-health trial</a>,
both directors excluded a failed backend before automatic failover. Fresh TCP/UDP
flows used only the healthy backend through failover and failback; both directors
restored the backend after recovery. One virtual run recovered in 3.175 seconds.
That run did not test retained sessions or physical L2.</p>
<p>With native IPVS synchronization, a separate <a href="https://github.com/l4load/l4load/blob/main/lab/cutover/results/2026-09-26-vrrp-retained.json">virtual trial</a>
kept two TCP sockets through automatic failover and failback without reconnect.
Each completed 235 exchanges; one exchange waited 6.578 seconds. Fresh TCP/UDP
recovered in 3.674 seconds. The sequential client does not measure independent
per-flow stalls. Replication loss, physical L2 and production targets remain open.</p>
<p>The <a href="https://github.com/l4load/l4load/blob/main/lab/cutover/results/2026-09-26-installed-ha.json">installed two-node profile</a>
passed automated failover, backend exclusion, rejected updates, drain, rollback
and planned service handoff in virtual namespaces. Two existing TCP sockets
survived the automatic failover without reconnect; fresh TCP/UDP recovered in
3.690 seconds. Its separate <a href="https://github.com/l4load/l4load/blob/main/lab/cutover/results/2026-09-26-sync-loss.json">sync-loss trial</a>
showed the limit: after the state link went down, the backup took the VIP and
fresh TCP/UDP recovered in 3.583 seconds, but an unsynced existing TCP socket
reset. Physical network, sustained load and an operational loss target are not
qualified.</p>
<p>With ongoing fresh TCP/UDP probes, a <a href="https://github.com/l4load/l4load/blob/main/lab/cutover/results/2026-09-26-ha-useful.json">short virtual HA trial</a>
observed 13 failed attempts per protocol during the handoff and none in the
baseline, post-failover or restored phases. The success gap was 3.269 seconds.
Sequential 250 ms timeouts reduced the actual attempt rate during failure;
this is not a sustained-load, capacity or production loss-rate result.</p>
<p>A <a href="https://github.com/l4load/l4load/blob/main/lab/bgp/results/2026-09-26-health-traffic.json">routed IPVS trial</a>
used independent TCP/UDP forwarding probes to withdraw the primary /32 when VIP
traffic was blocked while BGP stayed established. The upstream route moved to
standby and returned after recovery; 32 fresh TCP and 32 UDP exchanges passed
in each of the baseline, failover and restored phases. One virtual run did not
measure continuous-flow loss, retained sessions, BFD or physical capacity.</p>
<p>In a follow-up <a href="https://github.com/l4load/l4load/blob/main/lab/bgp/results/2026-09-26-useful.json">virtual traffic run</a>,
continuous fresh TCP/UDP attempts saw 10 errors per protocol during primary
failure; the last-to-first-success gap was 2.516 seconds. All measured attempts
after failover and after return passed. Sequential 250 ms timeouts reduced the
actual fault-phase attempt rate to about 4/s, so this is not a fixed-rate loss
or capacity result. Raw attempt records are archived with the summary.</p>
<p>A separate <a href="https://github.com/l4load/l4load/blob/main/lab/bgp/results/2026-09-26-fixed.json">fixed-offer virtual run</a>
held about 100 actual fresh-flow starts/s per protocol through the failure.
Each protocol had 244 consecutive errors and a 2.45-second gap between
successful starts; 208/208 attempts passed after failover. This is one short
software-network result, not a physical capacity or production SLO claim.</p>
<p>In a separate <a href="https://github.com/l4load/l4load/blob/main/lab/bgp/results/2026-09-26-bfd.json">single-hop BFD trial</a>,
the primary BFD session went Down when its control packets were dropped. The
route moved to standby in 0.351 seconds and returned after recovery. At about
100 fresh starts/s per protocol, all 716 TCP and 716 UDP exchanges passed;
the forwarding path itself was healthy. Multihop BFD, physical links and
production targets remain unqualified.</p>
<p>With a dedicated IPVS state-sync link, <a href="https://github.com/l4load/l4load/blob/main/lab/bgp/results/2026-09-26-session.json">one established TCP socket</a>
survived routed failover and failback without reconnecting in a short virtual
trial. Its slowest exchange took 3.35 seconds, and new TCP/UDP attempts failed
during the forwarding fault. Sync-link loss, scale and physical links remain
unqualified.</p>
<p>In a separate <a href="https://github.com/l4load/l4load/blob/main/lab/bgp/results/2026-09-26-sync-loss.json">negative control</a>,
the sync link was cut before a TCP session opened. That session reset after
routed failover, while 279/279 fresh TCP and UDP attempts passed on standby.
Loss after state has already replicated remains untested.</p>
<p>A <a href="https://github.com/l4load/l4load/blob/main/lab/bgp/results/2026-09-26-dual-sync.json">follow-up virtual run</a>
kept both native IPVS sync roles active on each director. One TCP socket survived
routed failover and failback without changing sync roles; its slowest reply took
3.32 seconds. State-table scale and sync traffic remain unqualified.</p>
<p>An <a href="https://github.com/l4load/l4load/blob/main/lab/bgp/results/2026-09-26-installed-pair.json">installed pair trial</a>
ran Keepalived/IPVS and BIRD/BFD services on both virtual directors. One TCP
socket survived failover and failback; its slowest reply took 3.35 seconds.
Fresh TCP and UDP each passed 311/311 attempts after failover at about 100
starts/s per protocol. Draining the only backend withdrew the standby route;
restoring it returned both IPVS weights and the route. Unit restarts and a
rejected reload also preserved verified traffic. This was one short virtual
run, not a physical-capacity or production SLO result.</p>
<p>A <a href="https://github.com/l4load/l4load/actions/runs/36177713642">bounded UDP load trial</a>
kept about 1,000 allowed messages/s without reported loss while generators sent
about 100,000 denied messages/s. Across three repeats, p99 RTT was 45–75 µs for
nftables/IPVS and 510–1040 µs for YANET AF_PACKET. Without background traffic,
the respective ranges were 42–44 µs and 92–1003 µs. YANET baseline variability,
shared CPU contention, fixed order and short intervals prevent a capacity or
production-superiority claim. All twelve raw CSVs are
<a href="https://github.com/l4load/l4load/tree/main/lab/filter/results/2026-09-25">preserved with hashes</a>.</p>
<p>In an isolated Katran test, freezing a kernel map caused a backend update to return success
while the kernel ring stayed unchanged. This artificial permanent-write failure does not establish
production incidence; it shows why an API acknowledgement alone is insufficient.</p>
<a href="https://github.com/l4load/l4load/tree/main/lab/katran-control">Reproduce the experiment ↗</a>
<h2>Evidence before performance claims.</h2>
<p>The YANET baseline passed 32 TCP and 32 UDP exchanges through two IPIP backends,
four upstream suites and five extra reload repetitions. It uses the existing
<a href="https://github.com/yanet-platform/yanet/pull/335">upstream neighbor fix by ezhk</a>.
The <a href="https://github.com/l4load/l4load/actions/runs/36148196614">native AF_PACKET trial</a>
also passed, using MTU 1500 and software-completed virtual-port checksums.
These are correctness checks, not competitive throughput measurements.
<a href="https://github.com/l4load/l4load/actions/runs/36146170902">Verified execution ↗</a></p>
<p>Our target is strong performance with fewer deployment dependencies.
Virtual results are distinguished from hardware measurements.</p>
<p>The <a href="https://github.com/l4load/l4load/actions/runs/36152260708">shared IPVS, Katran and YANET experiment</a>
completed 36 five-second TCP/UDP trials in one pinned builder container on one runner,
with 64-byte messages at requested 1k/10k messages per second and no reported drops.
The shared sockperf scenario records full RTT and actual message rates.</p>
<p>At 10k messages per second, trial p99 full RTT ranged from 57.7–62.3 µs for IPVS,
54.1–63.2 µs for Katran and 936.1–1421.3 µs for YANET AF_PACKET.
These ranges span individual TCP/UDP trial percentiles; they are not pooled percentiles.
The virtual paths differ, engine order was fixed and CPU placement was uncontrolled.
This is a latency observation to investigate, not a capacity, hardware or superiority claim.
<a href="https://github.com/l4load/l4load/tree/main/lab/load">Run the load scenario ↗</a></p>
<p><a href="https://github.com/l4load/l4load/actions/runs/36155111339">108 trials with cyclic engine order</a>
repeated the elevated YANET tail latency in every order. A subsequent
<a href="https://github.com/l4load/l4load/actions/runs/36159160252">workload-placement experiment</a>
put client and servers together on logical CPU 3: 10k-message/s p99 rose to
2.5–2.9 ms across all engines and returned to the prior range after restoring
normal placement. CPU 3 also shares a physical core with YANET worker 2.
This rejected configuration combines workload colocation and SMT contention;
it neither isolates their effects nor explains the original latency gap.</p>
<a href="https://github.com/l4load/l4load/blob/main/docs/benchmarks.md">Comparison criteria ↗</a>
<h2>Know the limits.</h2>
<p><a href="https://github.com/l4load/l4load/actions/runs/36169152717">Planned IPVS cutover and rollback</a>
compared independent director tables with and without native connection sync.
Without sync, four existing TCP sessions reset on cutover and four newer sessions
reset on rollback. With sync and a state-readback barrier, four sessions survived
cutover and eight survived rollback; fresh TCP/UDP traffic passed in both modes.
This does not qualify abrupt failure, lost sync messages or automatic failover.</p>
<p>The Katran scenario does not yet qualify backend changes, failover, IPv6 or physical NICs.
No production readiness, high availability or DDoS protection is claimed.</p>
</main><footer>L4Load glue: Apache-2.0 · Katran: GPL-2.0 · Generated from
<a href="https://github.com/l4load/l4load/tree/SOURCE_SHA">SOURCE_SHORT</a></footer>
</html>
'''
out = root / 'site'
out.mkdir(exist_ok=True)
(out / 'index.html').write_text(page.replace('SOURCE_SHA', sha).replace('SOURCE_SHORT', sha[:12]))
(out / 'source.txt').write_text(sha + '\n')
(out / '.nojekyll').touch()
print('Site built from', sha)
