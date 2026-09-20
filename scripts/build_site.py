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
<p>Balance experiments reuse existing engines before adding new code.
Our Katran lab sends TCP and UDP through one IPv4 VIP to two IPIP backends,
checks replies and preserves the original client address without DPDK.</p>
<p><a href="https://github.com/l4load/l4load/tree/main/lab/katran">Run the Katran scenario ↗</a> ·
<a href="https://github.com/l4load/l4load/actions/workflows/katran.yml">Execution logs &amp; artifacts ↗</a></p>
<p>This is a functional Linux namespace test using generic XDP and static maps.
It is not a production deployment or a throughput result.</p>
<div class="grid">
<article><h3>Balance</h3><small>Katran DSR lab</small><p>Test and tune existing dataplanes.</p></article>
<article><h3>Shield</h3><small>Planned</small><p>Traffic filtering and protection.</p></article>
<article><h3>Pulse</h3><small>Planned</small><p>Traffic and failure analysis.</p></article>
<article><h3>Fabric</h3><small>Planned</small><p>Configuration and multi-site operation.</p></article>
</div>
<h2>Backend failure and recovery.</h2>
<p>The Keepalived/IPVS trial checks healthy, health-failed and recovered backends.
All 896 IPv4 TCP/UDP exchanges passed, including HTTP health failure, rejected configuration, drain and rollback: new flows avoided the unhealthy backend and
returned to both backends after recovery, preserving client IP and payload.</p>
<p><a href="https://github.com/l4load/l4load/tree/main/lab/ipvs">Run the lifecycle trial ↗</a> ·
<a href="https://github.com/l4load/l4load/actions/runs/36138065416/job/108080863480">Verified execution ↗</a></p>
<p>Two established TCP sessions carried continuous low-rate requests through health exclusion, reload and gated controller recovery, including automatic systemd restart. Empty-table service startup also passed. Direct restart with retained state failed; the tested workaround pauses new flows until health is confirmed. Sustained load, host failure and HA remain unqualified.</p>
<p>A separate IPv6-over-IPv6 IPVS trial passed 192 TCP/UDP exchanges across
health-port failure and recovery with client addresses preserved. Two existing
IPv6 TCP sessions also survived those transitions in a short continuous-request
trial. IPv6 reload, restart and sustained traffic remain unqualified.</p>
<p>The packaged node_exporter IPVS collector correctly exposed backend weights
through health exclusion and recovery. Retention and alerts remain unqualified.</p>
<h2>Check applied state.</h2>
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
<p>Our target is strong performance with fewer deployment dependencies. No competitive
comparison has run yet. Virtual results will be distinguished from hardware measurements.</p>
<p><a href="https://github.com/l4load/l4load/actions/runs/36150467534">IPVS and Katran load-tool qualification</a>
completed 24 short TCP/UDP trials on one runner without reported message loss.
The shared sockperf scenario records full RTT and actual message rates.
Fixed engine order, unpinned CPUs and single-flow traffic prevent a capacity or
performance ranking. <a href="https://github.com/l4load/l4load/tree/main/lab/load">Run the load scenario ↗</a></p>
<a href="https://github.com/l4load/l4load/blob/main/docs/benchmarks.md">Comparison criteria ↗</a>
<h2>Know the limits.</h2>
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
