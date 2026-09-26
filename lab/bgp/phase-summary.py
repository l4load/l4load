import json
import os
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
    if 'runner_cpu_ticks' in before and 'runner_cpu_ticks' in after:
        delta = [end - start for start, end in zip(before['runner_cpu_ticks'], after['runner_cpu_ticks'])]
        assert len(delta) == 8 and min(delta) >= 0 and sum(delta) > 0
        busy = sum(delta[i] for i in (0, 1, 2, 5, 6))
        summary[before['phase']]['runner_busy_cpu_seconds'] = busy / os.sysconf('SC_CLK_TCK')
        summary[before['phase']]['runner_busy_percent'] = 100 * busy / sum(delta)
        summary[before['phase']]['runner_softirq_percent'] = 100 * delta[6] / sum(delta)
    for n in (1, 2):
        for unit in ('l4load-ipvs', 'l4load-routed'):
            start = before['directors'][str(n)].get(unit)
            end = after['directors'][str(n)].get(unit)
            if start and end:
                summary[before['phase']][f'{unit}-d{n}'] = {'cpu_seconds': (end['cpu_usec'] - start['cpu_usec']) / 1e6, 'memory_end_bytes': end['memory_bytes'], 'memory_peak_since_start_bytes': end['memory_peak_bytes']}
(out / 'phase-summary.json').write_text(json.dumps(summary, indent=2) + '\n')
print(json.dumps(summary))
