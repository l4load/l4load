import json
import socket
import sys
import time
from pathlib import Path

out = Path(sys.argv[1])
sock = socket.socket()
sock.settimeout(10)
sock.bind(('10.0.0.2', 12000))
sock.connect(('198.18.0.1', 8080))
stream = sock.makefile('rb')
counts = {}
max_rtt_ms = 0.0
previous = ''
deadline = time.monotonic() + 120
while time.monotonic() < deadline:
    phase = (out / 'useful-phase').read_text().strip()
    payload = f'{sum(counts.values())}:{phase}\n'
    start = time.monotonic()
    sock.sendall(payload.encode())
    reply = stream.readline().decode()
    assert reply == f'b1 10.0.0.2 {payload}', (phase, reply)
    max_rtt_ms = max(max_rtt_ms, (time.monotonic() - start) * 1000)
    counts[phase] = counts.get(phase, 0) + 1
    if phase != previous:
        print(json.dumps({'phase': phase, 'status': 'pass'}), flush=True)
        (out / f'session-{phase}').touch()
        previous = phase
        if phase == 'done':
            break
    time.sleep(0.05)
else:
    raise TimeoutError('session phases incomplete')
assert all(counts.get(p, 0) for p in ('baseline', 'fault', 'failover', 'return', 'restored'))
(out / 'session.json').write_text(json.dumps({'exchanges': counts, 'max_rtt_ms': max_rtt_ms}) + '\n')
