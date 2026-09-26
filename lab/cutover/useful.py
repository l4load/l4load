import csv
import json
import socket
import sys
import time
from collections import defaultdict
from pathlib import Path

out, protocol = Path(sys.argv[1]), sys.argv[2]
phase_file = out / 'useful-phase'
kind = socket.SOCK_STREAM if protocol == 'tcp' else socket.SOCK_DGRAM
rows = []
with (out / f'useful-{protocol}.csv').open('w') as file:
    writer = csv.writer(file)
    writer.writerow(['sent_monotonic', 'phase', 'rtt_ms', 'status', 'backend'])
    deadline = time.monotonic() + 120
    sequence = 0
    while time.monotonic() < deadline:
        phase = phase_file.read_text().strip()
        if phase == 'done':
            break
        start = time.monotonic()
        payload = f'{protocol}-{sequence}'.encode()
        status, backend = 'error', ''
        try:
            with socket.socket(socket.AF_INET, kind) as sock:
                sock.settimeout(0.25)
                sock.bind(('10.0.0.2', 0))
                sock.connect(('198.18.0.1', 8080))
                sock.sendall(payload)
                reply = sock.recv(4096).decode().split(' ', 2)
                if len(reply) == 3 and reply[0] in ('b1', 'b2') and reply[1] == '10.0.0.2' and reply[2] == payload.decode():
                    status, backend = 'pass', reply[0]
        except OSError:
            pass
        rtt = (time.monotonic() - start) * 1000
        row = (start, phase, rtt, status, backend)
        writer.writerow(row)
        file.flush()
        rows.append(row)
        sequence += 1
        time.sleep(max(0, 0.01 - (time.monotonic() - start)))
    else:
        raise TimeoutError('useful traffic phase did not finish')
summary = defaultdict(lambda: {'attempts': 0, 'passed': 0, 'errors': 0, 'rtt_ms': []})
for _, phase, rtt, status, _ in rows:
    item = summary[phase]
    item['attempts'] += 1
    item['passed' if status == 'pass' else 'errors'] += 1
    if status == 'pass':
        item['rtt_ms'].append(rtt)
for item in summary.values():
    values = sorted(item.pop('rtt_ms'))
    item['p99_success_rtt_ms'] = values[min(len(values) - 1, int(len(values) * 0.99))] if values else None
(out / f'useful-{protocol}.json').write_text(json.dumps(dict(summary), indent=2) + '\n')
print(protocol, json.dumps(dict(summary)), flush=True)
