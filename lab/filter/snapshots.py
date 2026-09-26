import csv
import ipaddress
import json
import math
import os
import resource
import socket
import subprocess
import sys
import time
from pathlib import Path


out = Path(sys.argv[1])
phase = out / 'snapshot-phase.txt'


def set_phase(value):
    staging = phase.with_suffix('.tmp')
    staging.write_text(value)
    staging.replace(phase)


if len(sys.argv) == 3:
    with socket.socket(socket.AF_INET, socket.SOCK_DGRAM) as sock, (out / 'snapshot-traffic.csv').open('w') as file:
        sock.bind(('10.0.0.2', 0))
        sock.settimeout(0.2)
        writer = csv.writer(file)
        writer.writerow(['sent_monotonic', 'phase', 'rtt_ms', 'status'])
        (out / 'snapshot-ready').touch()
        for sequence in range(30000):
            current = phase.read_text().strip()
            if current == 'done':
                break
            payload = str(sequence).encode()
            sent = time.monotonic()
            sock.sendto(payload, ('198.18.0.1', 8080))
            status = 'timeout'
            deadline = sent + 0.2
            while time.monotonic() < deadline:
                sock.settimeout(max(0.001, deadline - time.monotonic()))
                try:
                    reply = sock.recv(4096).decode().split(' ', 2)
                except TimeoutError:
                    break
                if len(reply) == 3 and reply[0] in ('b1', 'b2') and reply[1] == '10.0.0.2' and reply[2] == str(sequence):
                    status = 'pass'
                    break
            writer.writerow([sent, current, (time.monotonic() - sent) * 1000, status])
            file.flush()
            time.sleep(0.005)
        else:
            raise TimeoutError('snapshot experiment did not finish')
else:
    command = ([sys.executable, 'lab/yanet/snapshot.py', str(out)]
               if os.environ.get('L4LOAD_SNAPSHOT_ENGINE') == 'yanet' else
               ['ip', 'netns', 'exec', 'l4-lb', sys.executable, 'profiles/nftables/snapshot.py'])
    set_phase('baseline')
    client = subprocess.Popen(['ip', 'netns', 'exec', 'l4-client', sys.executable, __file__, str(out), 'probe'])
    measurements = []
    probes = set()
    try:
        for _ in range(100):
            assert client.poll() is None, 'traffic probe exited'
            if (out / 'snapshot-ready').exists():
                break
            time.sleep(0.05)
        else:
            raise TimeoutError('traffic probe not ready')
        time.sleep(1)
        for count in (1024, 16384, 65536, 0):
            pairs = [[str(ipaddress.IPv4Address(int(ipaddress.IPv4Address('198.19.0.0')) + i)), '198.18.0.1'] for i in range(max(0, count - 1))]
            if count:
                pairs.append(['10.0.0.3', '198.18.0.1'])
                selected = {pairs[index][0] for index in (0, count // 2, count - 2)}
                subprocess.run(['ip', '-n', 'l4-router', 'route', 'replace', '198.19.0.0/16', 'via', '10.0.0.2'], check=True)
                for source in sorted(selected - probes):
                    subprocess.run(['ip', '-n', 'l4-client', 'addr', 'add', source + '/32', 'dev', 'eth0'], check=True)
                    subprocess.run(['ip', 'netns', 'exec', 'l4-client', sys.executable, 'lab/filter/probe.py', source, 'pass'], check=True)
                probes.update(selected)
            set_phase(str(count))
            before = resource.getrusage(resource.RUSAGE_CHILDREN)
            started = time.monotonic()
            try:
                subprocess.run(command, input=json.dumps(pairs), text=True, check=True, timeout=60)
            except (subprocess.CalledProcessError, subprocess.TimeoutExpired) as error:
                (out / 'snapshot-failure.json').write_text(json.dumps({
                    'elements': count, 'started_monotonic': started,
                    'failed_monotonic': time.monotonic(), 'error': str(error)}) + '\n')
                raise
            finished = time.monotonic()
            after = resource.getrusage(resource.RUSAGE_CHILDREN)
            measurements.append({'elements': count, 'started_monotonic': started, 'finished_monotonic': finished,
                                 'child_cpu_seconds': after.ru_utime + after.ru_stime - before.ru_utime - before.ru_stime,
                                 'children_peak_rss_kib': after.ru_maxrss})
            subprocess.run(['ip', 'netns', 'exec', 'l4-client', sys.executable, 'lab/filter/probe.py', '10.0.0.3', 'drop' if count else 'pass'], check=True)
            for source in sorted(probes):
                subprocess.run(['ip', 'netns', 'exec', 'l4-client', sys.executable, 'lab/filter/probe.py', source, 'drop' if count else 'pass'], check=True)
            time.sleep(1)
        set_phase('done')
        client.wait(timeout=5)
        assert client.returncode == 0
    finally:
        if client.poll() is None:
            client.terminate()
            client.wait(timeout=5)
        (out / 'snapshot-updates.json').write_text(json.dumps(measurements, indent=2) + '\n')
    with (out / 'snapshot-traffic.csv').open() as file:
        rows = list(csv.DictReader(file))
    summary = []
    for measurement in measurements:
        observed = [row for row in rows if measurement['started_monotonic'] <= float(row['sent_monotonic']) <= measurement['finished_monotonic']]
        delays = sorted(float(row['rtt_ms']) for row in observed if row['status'] == 'pass')
        summary.append({**measurement, 'sent_during_update': len(observed),
                        'lost_during_update': sum(row['status'] != 'pass' for row in observed),
                        'p99_rtt_ms': delays[math.ceil(len(delays) * 0.99) - 1] if delays else None})
    (out / 'snapshot-summary.json').write_text(json.dumps(summary, indent=2) + '\n')
    assert all(row['sent_during_update'] for row in summary), 'update interval had no traffic samples'
    assert rows and all(row['status'] == 'pass' for row in rows), 'permitted traffic lost; inspect CSV'
    print('FILTER_BULK_SNAPSHOT_PASS', json.dumps({'exchanges': len(rows), 'max_rtt_ms': max(float(row['rtt_ms']) for row in rows)}))
