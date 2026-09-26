import json
import signal
import subprocess
import sys
import time
from pathlib import Path

instance = sys.argv[1]
config = json.loads(Path(f'/etc/l4load/routed-{instance}.json').read_text())
runtime = Path(f'/run/l4load-routed-{instance}')
control = runtime / 'bird.ctl'
signal.signal(signal.SIGTERM, lambda *_: sys.exit(0))
link = json.loads(subprocess.check_output(['ip', '-j', 'link', 'show', 'dev', config['sync_interface']]))[0]
assert 'LOWER_UP' in link['flags'], 'sync link has no carrier'
daemons = subprocess.run(['/usr/sbin/ipvsadm', '-Ln', '--daemon'], capture_output=True, text=True, check=True)
assert 'master sync daemon' not in daemons.stdout and 'backup sync daemon' not in daemons.stdout, 'IPVS sync is already owned'
bird = None
gate = None
started = []
try:
    bird = subprocess.Popen(['/usr/sbin/bird', '-f', '-c', f'/etc/l4load/bird-{instance}.conf', '-s', str(control)])
    for _ in range(100):
        if control.exists():
            break
        assert bird.poll() is None, 'BIRD exited during startup'
        time.sleep(0.1)
    assert control.exists(), 'BIRD control socket did not appear'
    subprocess.run(['sysctl', '-qw', 'net.ipv4.vs.sync_threshold=0 1'], check=True)
    for role in ('backup', 'master'):
        subprocess.run(['/usr/sbin/ipvsadm', '--start-daemon', role, '--mcast-interface', config['sync_interface'], '--syncid', str(config['sync_id'])], check=True)
        started.append(role)
    gate = subprocess.Popen(['/usr/bin/python3', '/usr/local/libexec/l4load-route-gate.py', str(control), 'vip', config['peer_ip'], '--ipvs', '--', f'/etc/l4load/check-{instance}'])
    while bird.poll() is None and gate.poll() is None:
        time.sleep(0.2)
    raise RuntimeError(f'BIRD={bird.poll()} route gate={gate.poll()}')
finally:
    for child in (gate, bird):
        if child and child.poll() is None:
            child.terminate()
            try:
                child.wait(timeout=3)
            except subprocess.TimeoutExpired:
                child.kill()
                child.wait()
    for role in reversed(started):
        subprocess.run(['/usr/sbin/ipvsadm', '--stop-daemon', role], check=False)
