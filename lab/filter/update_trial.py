import ipaddress
import json
import os
from pathlib import Path
import resource
import subprocess
import sys
import time

out, count = Path(sys.argv[1]), int(sys.argv[2])


def resources():
    paths = ['/proc/meminfo', '/proc/self/cgroup'] + [
        '/sys/fs/cgroup/' + name for name in ('memory.current', 'memory.peak', 'memory.max', 'memory.events', 'cpu.stat')]
    return {'monotonic': time.monotonic(),
            'files': {name: Path(name).read_text() for name in paths if Path(name).is_file()},
            'processes': subprocess.run(['ps', '-eo', 'pid,ppid,stat,rss,vsz,comm'],
                                        text=True, capture_output=True, check=True).stdout}


pairs = [[str(ipaddress.IPv4Address(int(ipaddress.IPv4Address('198.19.0.0')) + i)), '198.18.0.1'] for i in range(count - 1)]
pairs.append(['10.0.0.3', '198.18.0.1'])
command = ([sys.executable, 'lab/yanet/snapshot.py', os.environ['L4LOAD_SNAPSHOT_OUT']]
           if os.environ.get('L4LOAD_SNAPSHOT_ENGINE') == 'yanet' else
           ['ip', 'netns', 'exec', 'l4-lb', sys.executable, 'profiles/nftables/snapshot.py'])
state = {'before': resources()}
started = time.monotonic()
before = resource.getrusage(resource.RUSAGE_CHILDREN)
result = None
try:
    result = subprocess.run(command, input=json.dumps(pairs), text=True, timeout=60)
    result.check_returncode()
finally:
    finished = time.monotonic()
    after = resource.getrusage(resource.RUSAGE_CHILDREN)
    state['after'] = resources()
    out.with_name(out.stem + '-resources.json').write_text(json.dumps(state, indent=2) + '\n')
    out.write_text(json.dumps(dict(elements=count, started_monotonic=started,
        finished_monotonic=finished, returncode=result.returncode if result else None,
        child_cpu_seconds=after.ru_utime+after.ru_stime-before.ru_utime-before.ru_stime,
        children_peak_rss_kib=after.ru_maxrss), indent=2) + '\n')
