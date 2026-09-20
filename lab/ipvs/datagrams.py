import errno
import json
import os
import socket
import subprocess

vip = os.environ.get('L4LOAD_VIP', '198.18.0.1')
client = os.environ.get('L4LOAD_CLIENT', '10.0.0.2')
family = socket.AF_INET6 if ':' in vip else socket.AF_INET
results = []
for size in (64, 1200, 1400, 1412, 1413, 1452, 1453, 1472, 2000, 4000):
    payload = bytes(n % 251 for n in range(size))
    for attempt in range(2):
        with socket.socket(family, socket.SOCK_DGRAM) as sock:
            sock.settimeout(3)
            sock.connect((vip, 8080))
            operation = 'send'
            before = json.loads(subprocess.check_output(['ip', '-j', 'route', 'get', vip]))
            try:
                sock.sendall(payload)
                operation = 'receive'
                backend, source, echoed = sock.recv(8192).split(b' ', 2)
                assert backend in (b'b1', b'b2') and source.decode() == client
                assert echoed == payload
                result = {'bytes': size, 'status': 'delivered', 'backend': backend.decode()}
            except OSError as error:
                result = {'bytes': size, 'status': 'failed', 'error': str(error), 'errno': error.errno, 'operation': operation}
            result['route_before'] = before
            result['route_after'] = json.loads(subprocess.check_output(['ip', '-j', 'route', 'get', vip]))
            result['attempt'] = attempt + 1
            results.append(result)
            print(json.dumps(result), flush=True)
        if result['status'] == 'delivered':
            break
        assert result.get('errno') == errno.EMSGSIZE and attempt == 0, result
        mtus = [metric.get('mtu') for route in result['route_after'] for metric in route.get('metrics', [])]
        assert (1460 if family == socket.AF_INET6 else 1480) in mtus, result
    assert result['status'] == 'delivered', result
