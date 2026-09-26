import json
import sys
from pathlib import Path

out = Path(sys.argv[1])
rows = [json.loads(line) for line in (out / 'phase-snapshots.jsonl').read_text().splitlines()]
summary = {}
for before, after in zip(rows, rows[1:]):
    elapsed = after['at'] - before['at']
    assert elapsed > 0
    counts = {str(n): after['directors'][str(n)]['denied_packets'] - before['directors'][str(n)]['denied_packets'] for n in (1, 2)}
    assert min(counts.values()) >= 0
    summary[before['phase']] = {'seconds': elapsed, 'denied_packets': counts, 'denied_packets_per_second': sum(counts.values()) / elapsed}
    for n in (1, 2):
        for unit in ('l4load-ipvs', 'l4load-routed'):
            start = before['directors'][str(n)].get(unit)
            end = after['directors'][str(n)].get(unit)
            if start and end:
                summary[before['phase']][f'{unit}-d{n}'] = {'cpu_seconds': (end['cpu_usec'] - start['cpu_usec']) / 1e6, 'memory_end_bytes': end['memory_bytes']}
(out / 'phase-summary.json').write_text(json.dumps(summary, indent=2) + '\n')
print(json.dumps(summary))
