from pathlib import Path
import subprocess

root = Path(__file__).resolve().parents[1]
sha = subprocess.check_output(['git', 'rev-parse', 'HEAD'], cwd=root, text=True).strip()
page = '''<!doctype html>
<html lang="en">
<meta charset="utf-8">
<meta name="viewport" content="width=device-width,initial-scale=1">
<meta name="description" content="L4Load: independent tools for L4 networking. Explore the experimental Balance TCP reference.">
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
<main><h2>Start small. Verify the behaviour.</h2>
<p>Balance has a loopback TCP reference with backend selection, connect-only fallback,
half-close, connection limits and bounded shutdown. It is not production-ready.</p>
<pre><code>git clone https://github.com/l4load/l4load.git
cd l4load
go test -race ./...
go run ./cmd/l4load -config examples/local.json -check</code></pre>
<p>Go 1.26+ required. See the <a href="https://github.com/l4load/l4load#try-balance">quickstart</a>
for a local two-backend demo.</p>
<div class="grid">
<article><h3>Balance</h3><small>TCP lab available</small><p>Connection handling with explicit limits.</p></article>
<article><h3>Shield</h3><small>Planned</small><p>Traffic filtering and protection.</p></article>
<article><h3>Pulse</h3><small>Planned</small><p>Traffic and failure analysis.</p></article>
<article><h3>Fabric</h3><small>Planned</small><p>Configuration and multi-site operation.</p></article>
</div>
<h2>Evidence before performance claims.</h2>
<p>Our target is strong performance with fewer deployment dependencies. No YANET or
Katran comparison has run yet. Virtual results will be distinguished from hardware measurements.</p>
<a href="https://github.com/l4load/l4load/blob/main/docs/benchmarks.md">Comparison criteria ↗</a>
<h2>Know the limits.</h2>
<p>The current lab is a full TCP proxy restricted to loopback. It does not preserve
client source IP or provide UDP, DSR, reload, high availability or DDoS protection.</p>
</main><footer>Apache-2.0 · Generated from
<a href="https://github.com/l4load/l4load/tree/SOURCE_SHA">SOURCE_SHORT</a></footer>
</html>
'''
out = root / 'site'
out.mkdir(exist_ok=True)
(out / 'index.html').write_text(page.replace('SOURCE_SHA', sha).replace('SOURCE_SHORT', sha[:12]))
(out / 'source.txt').write_text(sha + '\n')
(out / '.nojekyll').touch()
print('Site built from', sha)
