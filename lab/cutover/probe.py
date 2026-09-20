import json
import socket
import sys
import time
from pathlib import Path

out = Path(sys.argv[1])
sessions = []
previous = ''
deadline = time.monotonic() + 120

def exchange(sock, stream, payload):
    sock.sendall((payload + '\n').encode())
    reply = stream.readline().decode().split(' ', 2)
    if len(reply) != 3 or reply[1:] != ['10.0.0.2', payload + '\n']:
        raise ValueError(repr(reply))
    return reply[0]

while time.monotonic() < deadline:
    phase = (out / 'cutover-phase').read_text().strip()
    if not phase or phase == previous:
        time.sleep(0.05)
        continue
    retained = []
    for item in sessions:
        result = {'origin': item['origin'], 'backend': item['backend']}
        if item['failed']:
            result['status'] = 'not_tested_after_disruption'
        else:
            try:
                assert exchange(item['sock'], item['stream'], phase) == item['backend']
                result['status'] = 'pass'
            except (OSError, ValueError, AssertionError) as error:
                item['failed'] = True
                result.update(status='disrupted', error=repr(error))
        retained.append(result)
    fresh = []
    if phase != 'done':
        for number in range(4):
            sock = socket.create_connection(('198.18.0.1', 8080), timeout=2)
            stream = sock.makefile('rb')
            backend = exchange(sock, stream, f'{phase}-{number}')
            fresh.append(backend)
            sessions.append(dict(origin=phase, backend=backend, sock=sock,
                                 stream=stream, failed=False))
    print(json.dumps({'phase': phase, 'retained': retained, 'fresh': fresh,
                      'utc': time.strftime('%Y-%m-%dT%H:%M:%SZ', time.gmtime())}), flush=True)
    (out / ('cutover-' + phase)).touch()
    previous = phase
    if phase == 'done':
        break
else:
    raise TimeoutError('cutover phases incomplete')
