import json
import subprocess
import sys
import time
from pathlib import Path

out, phase = Path(sys.argv[1]), sys.argv[2]
record = {'phase': phase, 'at': time.monotonic(), 'runner_cpu_ticks': [int(x) for x in Path('/proc/stat').read_text().splitlines()[0].split()[1:9]], 'directors': {}}
for n in (1, 2):
    rows = json.loads(subprocess.check_output(['ip', 'netns', 'exec', f'l4-d{n}', 'nft', '-j', 'list', 'table', 'netdev', 'l4load']))['nftables']
    packets = sum(expr['counter']['packets'] for row in rows if 'rule' in row for expr in row['rule']['expr'] if 'counter' in expr)
    record['directors'][str(n)] = {'denied_packets': packets}
    for name in ('l4load-ipvs', 'l4load-routed'):
        unit = f'{name}@d{n}.service'
        group = subprocess.check_output(['systemctl', 'show', unit, '-p', 'ControlGroup', '--value'], text=True).strip()
        path = Path('/sys/fs/cgroup' + group)
        if path.is_dir():
            cpu = dict(line.split() for line in (path / 'cpu.stat').read_text().splitlines())
            record['directors'][str(n)][name] = {'cpu_usec': int(cpu['usage_usec']), 'memory_bytes': int((path / 'memory.current').read_text()), 'memory_peak_bytes': int((path / 'memory.peak').read_text())}
record['finished_at'] = time.monotonic()
with (out / 'phase-snapshots.jsonl').open('a') as file:
    file.write(json.dumps(record) + '\n')
