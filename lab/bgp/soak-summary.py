import hashlib
import json
import re
import sys
from pathlib import Path

out = Path(sys.argv[1])
summary = {}
for protocol in ('tcp', 'udp'):
    name = f'soak-{protocol}'
    text = (out / f'{name}.txt').read_text()
    duration, sent, received = re.search(r'\[Valid Duration\] RunTime=([\d.]+) sec; SentMessages=(\d+); ReceivedMessages=(\d+)', text).groups()
    dropped = int(re.search(r'# dropped messages = (\d+)', text)[1])
    p99 = float(re.search(r'percentile 99\.000 =\s*([\d.]+)', text)[1])
    samples = (out / f'{name}.csv').read_bytes()
    assert float(duration) >= 59 and int(sent) > 0 and int(received) > 0 and samples
    summary[protocol] = {'requested_mps': 1000, 'actual_mps': int(sent) / float(duration), 'sent': int(sent), 'received': int(received), 'dropped': dropped, 'p99_rtt_us': p99, 'samples_sha256': hashlib.sha256(samples).hexdigest()}
print(json.dumps(summary, indent=2))
