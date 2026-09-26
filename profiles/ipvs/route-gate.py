import json
import signal
import subprocess
import sys
import time

control, route, peer, *probe = sys.argv[1:]
check_ipvs = probe[:1] == ['--ipvs']
if check_ipvs:
    probe.pop(0)
if probe[0] == '--':
    probe.pop(0)
signal.signal(signal.SIGTERM, lambda *_: sys.exit(0))


def bird(command):
    result = subprocess.run(['birdc', '-s', control, *command], capture_output=True, text=True, timeout=3)
    status = 'enabled' if command[0] == 'enable' else 'disabled'
    if result.returncode or not any(f'{route}: {prefix}{status}' in result.stdout for prefix in ('', 'already ')):
        raise RuntimeError((command, result.stdout, result.stderr))


def ipvs_ready():
    result = subprocess.run(['/usr/sbin/ipvsadm', '-Sn'], capture_output=True, text=True, timeout=3)
    if result.returncode:
        return False
    services = set()
    positive = set()
    for line in result.stdout.splitlines():
        args = line.split()
        if args[:1] == ['-A']:
            services.add(tuple(args[1:3]))
        elif args[:1] == ['-a'] and '-w' in args and int(args[args.index('-w') + 1]) > 0:
            positive.add(tuple(args[1:3]))
    return bool(services) and services <= positive


healthy = False
streak = 0
misses = 0
bird(['disable', route])
try:
    while True:
        try:
            forwarding = subprocess.run(probe, capture_output=True, timeout=3).returncode == 0
        except subprocess.TimeoutExpired:
            forwarding = False
        bfd = True
        if peer != '-':
            result = subprocess.run(['birdc', '-s', control, 'show bfd sessions'], capture_output=True, text=True, timeout=3)
            bfd = result.returncode == 0 and any(
                (parts := line.split()) and len(parts) > 2 and parts[0] == peer and parts[2] == 'Up'
                for line in result.stdout.splitlines()
            )
        good = forwarding and bfd and (not check_ipvs or ipvs_ready())
        streak = streak + 1 if good and not healthy else 0
        misses = misses + 1 if not good and healthy else 0
        if misses >= 2 or streak >= 2:
            action = 'enable' if good else 'disable'
            bird([action, route])
            healthy = good
            streak = 0
            misses = 0
            print(json.dumps({'at': time.monotonic(), 'action': action, 'route': route}), flush=True)
        time.sleep(0 if healthy and misses else 0.2)
finally:
    bird(['disable', route])
