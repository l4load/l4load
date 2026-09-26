import json
import subprocess
import sys
import time

namespace, source, control, route = sys.argv[1:]
healthy = True
streak = 0
while True:
    if namespace == 'bfd':
        probe = subprocess.run(['birdc', '-s', control, 'show bfd sessions'], capture_output=True, text=True)
        good = probe.returncode == 0 and any(
            (parts := line.split()) and len(parts) > 2 and parts[0] == source and parts[2] == 'Up'
            for line in probe.stdout.splitlines()
        )
    else:
        probe = subprocess.run(
            ['ip', 'netns', 'exec', namespace, 'python3', 'lab/filter/probe.py', source, 'pass'],
            capture_output=True, text=True,
        )
        good = probe.returncode == 0
    streak = streak + 1 if good != healthy else 0
    if streak >= 2:
        action = 'enable' if good else 'disable'
        result = subprocess.run(['birdc', '-s', control, action, route], capture_output=True, text=True)
        if result.returncode or f'{route}: {"enabled" if good else "disabled"}' not in result.stdout:
            raise RuntimeError((action, result.stdout, result.stderr))
        healthy = good
        streak = 0
        print(json.dumps({'at': time.monotonic(), 'action': action, 'route': route}), flush=True)
    time.sleep(0.2)
