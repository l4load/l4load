import json
import socket
import sys
import time
from pathlib import Path

out = Path(sys.argv[1])
sock = socket.create_connection(('198.18.0.1', 8080), timeout=10)
stream = sock.makefile('rb')
sock.sendall(b'before\n')
initial = stream.readline().decode()
backend, source, payload = initial.split(' ', 2)
assert backend in ('b1', 'b2') and source == '10.0.0.2' and payload == 'before\n'
(out / 'stale-ready.json').write_text(json.dumps({'source_port': sock.getsockname()[1], 'backend': backend}) + '\n')
for _ in range(600):
    if (out / 'stale-trigger').exists():
        break
    time.sleep(0.05)
else:
    raise TimeoutError('no failover trigger')
start = time.monotonic()
try:
    sock.sendall(b'after\n')
    reply = stream.readline().decode()
    status = 'retained' if reply == f'{backend} 10.0.0.2 after\n' else 'changed_or_closed'
    detail = reply
except (OSError, TimeoutError) as error:
    status = 'disrupted'
    detail = repr(error)
(out / 'stale-result.json').write_text(json.dumps({'status': status, 'detail': detail,
    'exchange_seconds': time.monotonic() - start, 'reconnects': 0}) + '\n')
