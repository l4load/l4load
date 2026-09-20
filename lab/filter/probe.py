import json
import socket
import sys

source, expected = sys.argv[1:]
for kind in (socket.SOCK_STREAM, socket.SOCK_DGRAM):
    with socket.socket(socket.AF_INET, kind) as sock:
        sock.settimeout(1)
        sock.bind((source, 0))
        try:
            sock.connect(('198.18.0.1', 8080))
            sock.sendall(b'filter-probe')
            reply = sock.recv(4096)
        except TimeoutError:
            assert expected == 'drop', (source, kind, 'unexpected timeout')
            status = 'timeout'
        else:
            assert expected == 'pass', (source, kind, reply)
            backend, peer, payload = reply.decode().split(' ', 2)
            assert backend in ('b1', 'b2') and peer == source and payload == 'filter-probe', reply
            status = 'pass'
    print(json.dumps({'source': source, 'protocol': 'tcp' if kind == socket.SOCK_STREAM else 'udp', 'status': status}), flush=True)
