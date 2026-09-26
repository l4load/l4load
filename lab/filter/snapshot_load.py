import json
import re
import subprocess
import time
from contextlib import contextmanager


@contextmanager
def denied_load(out, count):
    if not count:
        yield lambda: None
        return
    duration = {1024: 10, 16384: 15, 65536: 75}[count]
    record = {'requested_mps': 100000, 'duration_seconds': duration, 'alive_monotonic': []}
    with (out / f'snapshot-denied-{count}.txt').open('w') as log:
        process = subprocess.Popen([
            'ip', 'netns', 'exec', 'l4-client', 'sockperf', 'throughput',
            '-i', '198.18.0.1', '-p', '8080', '--client_ip', '10.0.0.3',
            '-m', '64', '-t', str(duration), '--mps', '100000'], stdout=log, stderr=log)
        record['started_monotonic'] = time.monotonic()
        def check():
            assert process.poll() is None, 'denied generator exited before update finished'
            record['alive_monotonic'].append(time.monotonic())
        try:
            time.sleep(2)
            check()
            yield check
            check()
            process.wait(timeout=duration + 10)
            assert process.returncode == 0, 'denied generator failed'
            sent, elapsed = re.search(r'Total of (\d+) messages sent in ([\d.]+) sec',
                                      (out / f'snapshot-denied-{count}.txt').read_text()).groups()
            assert int(sent) > 0 and float(elapsed) > 0, 'no denied traffic generated'
            record['achieved_mps'] = int(sent) / float(elapsed)
        finally:
            if process.poll() is None:
                process.terminate()
                process.wait(timeout=5)
            record.update(finished_monotonic=time.monotonic(), returncode=process.returncode)
            (out / f'snapshot-denied-{count}.json').write_text(json.dumps(record, indent=2) + '\n')
