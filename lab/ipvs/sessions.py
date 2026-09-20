import json
import socket
import sys
import time
from pathlib import Path

out = Path(sys.argv[1])
sessions = {}
for _ in range(8):
    sock = socket.create_connection(('198.18.0.1', 8080), timeout=3)
    stream = sock.makefile('rb')
    sock.sendall(b'initial\n')
    backend, source, payload = stream.readline().decode().split(' ', 2)
    assert source == '10.0.0.2' and payload == 'initial\n'
    if backend in sessions:
        stream.close()
        sock.close()
    else:
        sessions[backend] = (sock, stream)
    if set(sessions) == {'b1', 'b2'}:
        break
assert set(sessions) == {'b1', 'b2'}, sessions
(out / 'session-ready').touch()
previous = ''
deadline = time.monotonic() + 120
while time.monotonic() < deadline:
    phase = (out / 'session-phase').read_text().strip()
    if phase and phase != previous:
        for backend, (sock, stream) in sessions.items():
            sock.sendall((phase + '\n').encode())
            reply = stream.readline().decode()
            assert reply == f'{backend} 10.0.0.2 {phase}\n', reply
        print(json.dumps({'phase': phase, 'sessions': sorted(sessions), 'status': 'pass'}), flush=True)
        (out / ('session-' + phase)).touch()
        previous = phase
        if phase == 'done':
            break
    time.sleep(0.05)
else:
    raise TimeoutError('session phases incomplete')
