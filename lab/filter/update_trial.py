import ipaddress
import json
import os
from pathlib import Path
import resource
import subprocess
import sys
import time

out, count = Path(sys.argv[1]), int(sys.argv[2])
pairs = [[str(ipaddress.IPv4Address(int(ipaddress.IPv4Address('198.19.0.0')) + i)), '198.18.0.1'] for i in range(count - 1)]
pairs.append(['10.0.0.3', '198.18.0.1'])
command = ([sys.executable, 'lab/yanet/snapshot.py', os.environ['L4LOAD_SNAPSHOT_OUT']]
           if os.environ.get('L4LOAD_SNAPSHOT_ENGINE') == 'yanet' else
           ['ip', 'netns', 'exec', 'l4-lb', sys.executable, 'profiles/nftables/snapshot.py'])
started = time.monotonic()
before = resource.getrusage(resource.RUSAGE_CHILDREN)
try:
    result = subprocess.run(command, input=json.dumps(pairs), text=True, timeout=60)
    result.check_returncode()
finally:
    after = resource.getrusage(resource.RUSAGE_CHILDREN)
    out.write_text(json.dumps(dict(elements=count, started_monotonic=started,
        finished_monotonic=time.monotonic(), child_cpu_seconds=after.ru_utime+after.ru_stime-before.ru_utime-before.ru_stime,
        children_peak_rss_kib=after.ru_maxrss), indent=2) + '\n')
