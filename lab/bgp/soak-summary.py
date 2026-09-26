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
    assert float(duration) >= 59 and int(sent) > 0 and int(received) == int(sent) and dropped == 0 and samples
    summary[protocol] = {'requested_mps': 1000, 'actual_mps': int(sent) / float(duration), 'sent': int(sent), 'received': int(received), 'dropped': dropped, 'p99_rtt_us': p99, 'samples_sha256': hashlib.sha256(samples).hexdigest()}
snapshots = [json.loads(line) for line in (out / 'phase-snapshots.jsonl').read_text().splitlines()]
start = next(row['at'] for row in snapshots if row['phase'] == 'soak')
end = next(row['finished_at'] for row in snapshots if row['phase'] == 'soak-end')
summary['route_actions_during_soak'] = {}
for n in (1, 2):
    events = [json.loads(line) for line in (out / f'health{n}.jsonl').read_text().splitlines() if line.startswith('{')]
    actions = [event['action'] for event in events if start <= event['at'] <= end]
    assert not actions, (n, actions)
    summary['route_actions_during_soak'][str(n)] = actions
print(json.dumps(summary, indent=2))
