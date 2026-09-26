import csv
import json
import socket
import sys
import time
from collections import defaultdict
from concurrent.futures import ThreadPoolExecutor
from pathlib import Path

out, protocol = Path(sys.argv[1]), sys.argv[2]
kind = socket.SOCK_STREAM if protocol == 'tcp' else socket.SOCK_DGRAM


def exchange(scheduled, phase, sequence):
    started = time.monotonic()
    payload = f'{protocol}-{sequence}'.encode()
    status = 'error'
    try:
        with socket.socket(socket.AF_INET, kind) as sock:
            sock.settimeout(0.25)
            sock.bind(('10.0.0.2', 0))
            sock.connect(('198.18.0.1', 8080))
            sock.sendall(payload)
            reply = sock.recv(4096).decode().split(' ', 2)
            if reply == ['b1', '10.0.0.2', payload.decode()]:
                status = 'pass'
    except OSError:
        pass
    finished = time.monotonic()
    return scheduled, started, finished, phase, status


futures = []
with ThreadPoolExecutor(max_workers=64) as pool:
    next_at = time.monotonic()
    deadline = next_at + 120
    while time.monotonic() < deadline:
        phase = (out / 'useful-phase').read_text().strip()
        if phase == 'done':
            break
        now = time.monotonic()
        if now < next_at:
            time.sleep(min(next_at - now, 0.002))
            continue
        futures.append(pool.submit(exchange, next_at, phase, len(futures)))
        next_at += 0.01
    else:
        raise TimeoutError('offered traffic phase did not finish')

rows = [future.result() for future in futures]
with (out / f'useful-{protocol}.csv').open('w') as file:
    writer = csv.writer(file)
    writer.writerow(['scheduled_monotonic', 'started_monotonic', 'finished_monotonic', 'phase', 'status'])
    writer.writerows(rows)

summary = defaultdict(lambda: {'attempts': 0, 'passed': 0, 'errors': 0, 'starts': [], 'rtt': [], 'lag': []})
for scheduled, started, finished, phase, status in rows:
    item = summary[phase]
    item['attempts'] += 1
    item['passed' if status == 'pass' else 'errors'] += 1
    item['starts'].append(started)
    item['lag'].append((started - scheduled) * 1000)
    if status == 'pass':
        item['rtt'].append((finished - started) * 1000)
for item in summary.values():
    starts = sorted(item.pop('starts'))
    rtt = sorted(item.pop('rtt'))
    lag = sorted(item.pop('lag'))
    item['actual_starts_per_second'] = (len(starts) - 1) / (starts[-1] - starts[0]) if len(starts) > 1 else None
    item['p99_success_rtt_ms'] = rtt[min(len(rtt) - 1, int(len(rtt) * 0.99))] if rtt else None
    item['p99_start_lag_ms'] = lag[min(len(lag) - 1, int(len(lag) * 0.99))]
(out / f'useful-{protocol}.json').write_text(json.dumps(dict(summary), indent=2) + '\n')
print(protocol, json.dumps(dict(summary)), flush=True)
