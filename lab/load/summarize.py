import hashlib
import json
from pathlib import Path
import re
import sys

root = Path(sys.argv[1])
rows = []
for protocol in ('udp', 'tcp'):
    for rate in (1000, 10000):
        for repeat in (1, 2, 3):
            name = f'{protocol}-{rate}-{repeat}'
            text = (root / f'{name}.txt').read_text()
            assert 'avg-rtt=' in text, name
            duration, sent, received = re.search(
                r'\[Valid Duration\] RunTime=([\d.]+) sec; SentMessages=(\d+); ReceivedMessages=(\d+)', text).groups()
            duration, sent, received = float(duration), int(sent), int(received)
            assert duration > 0 and sent > 0 and received > 0, name
            dropped = int(re.search(r'# dropped messages = (\d+)', text)[1])
            p99 = float(re.search(r'percentile 99\.000 =\s*([\d.]+)', text)[1])
            samples = root / f'{name}.csv'
            assert samples.is_file() and samples.stat().st_size > 0, name
            rows.append(dict(protocol=protocol, requested_mps=rate, repeat=repeat,
                             duration_s=duration, sent=sent, received=received,
                             actual_mps=sent / duration, dropped=dropped, p99_rtt_us=p99,
                             samples_file=samples.name, samples_bytes=samples.stat().st_size,
                             samples_sha256=hashlib.sha256(samples.read_bytes()).hexdigest()))
print(json.dumps(rows, indent=2))
