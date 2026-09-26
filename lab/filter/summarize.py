import hashlib
import json
from pathlib import Path
import re
import sys

root = Path(sys.argv[1])
rows = []
def cpu(path):
    values = list(map(int, path.read_text().splitlines()[0].split()[1:9]))
    return sum(values), values[3] + values[4], values[6]

for path in sorted(root.glob('[0-9]*-*.csv')):
    name = path.stem
    repeat, rate = map(int, name.split('-'))
    text = (root / f'{name}.txt').read_text()
    duration, sent, received = re.search(
        r'\[Valid Duration\] RunTime=([\d.]+) sec; SentMessages=(\d+); ReceivedMessages=(\d+)', text).groups()
    duration, sent, received = float(duration), int(sent), int(received)
    assert duration > 0 and sent > 0, name
    p99 = re.search(r'percentile 99\.000 =\s*([\d.]+)', text)
    denied_mps = 0
    if rate:
        denied = (root / f'{name}-denied.txt').read_text()
        count, elapsed = re.search(r'Total of (\d+) messages sent in ([\d.]+) sec', denied).groups()
        assert int(count) > 0 and float(elapsed) > 0, name
        denied_mps = int(count) / float(elapsed)
    before = cpu(root / f'{name}-cpu-before.txt')
    after = cpu(root / f'{name}-cpu-after.txt')
    total, idle, softirq = (end - start for start, end in zip(before, after))
    assert total > 0, name
    rows.append(dict(repeat=repeat, denied_requested_mps=rate,
                     denied_generator_mps=denied_mps, allowed_requested_mps=1000,
                     allowed_sent=sent, allowed_received=received,
                     allowed_actual_mps=sent / duration,
                     dropped=int(re.search(r'# dropped messages = (\d+)', text)[1]),
                     p99_rtt_us=float(p99[1]) if p99 else None,
                     runner_busy_percent=100 * (total - idle) / total,
                     runner_softirq_percent=100 * softirq / total,
                     samples_bytes=path.stat().st_size,
                     samples_sha256=hashlib.sha256(path.read_bytes()).hexdigest()))
print(json.dumps(rows, indent=2))
