import json
import signal
import subprocess
import sys
import time

control, route, peer, *probe = sys.argv[1:]
if probe[0] == '--':
    probe.pop(0)
signal.signal(signal.SIGTERM, lambda *_: sys.exit(0))


def bird(command):
    result = subprocess.run(['birdc', '-s', control, *command], capture_output=True, text=True, timeout=3)
    if result.returncode or f'{route}: {"enabled" if command[0] == "enable" else "disabled"}' not in result.stdout:
        raise RuntimeError((command, result.stdout, result.stderr))


healthy = False
streak = 0
bird(['disable', route])
try:
    while True:
        forwarding = subprocess.run(probe, capture_output=True, timeout=3).returncode == 0
        bfd = True
        if peer != '-':
            result = subprocess.run(['birdc', '-s', control, 'show bfd sessions'], capture_output=True, text=True, timeout=3)
            bfd = result.returncode == 0 and any(
                (parts := line.split()) and len(parts) > 2 and parts[0] == peer and parts[2] == 'Up'
                for line in result.stdout.splitlines()
            )
        good = forwarding and bfd
        streak = streak + 1 if good != healthy else 0
        if streak >= 2:
            action = 'enable' if good else 'disable'
            bird([action, route])
            healthy = good
            streak = 0
            print(json.dumps({'at': time.monotonic(), 'action': action, 'route': route}), flush=True)
        time.sleep(0.2)
finally:
    bird(['disable', route])
