import ipaddress
import json
import os
import re
import shutil
import subprocess
import sys
import tempfile
from pathlib import Path

instance, candidate, check = sys.argv[1:]
assert os.geteuid() == 0 and re.fullmatch(r'[a-z0-9-]+', instance)
config = json.loads(Path(candidate).read_text())
assert set(config) == {'vip', 'local_ip', 'local_as', 'peer_ip', 'peer_as', 'sync_interface', 'sync_id'}
for key in ('vip', 'local_ip', 'peer_ip'):
    config[key] = str(ipaddress.IPv4Address(config[key]))
for key, limit in (('local_as', 4294967295), ('peer_as', 4294967295), ('sync_id', 255)):
    assert type(config[key]) is int and 1 <= config[key] <= limit
assert re.fullmatch(r'[a-zA-Z0-9_.-]{1,15}', config['sync_interface'])
assert Path(check).is_file() and os.access(check, os.X_OK)
base = Path('/etc/l4load')
assert (Path('/etc/systemd/system') / 'l4load-ipvs.service').exists()
assert not list(base.glob('routed-*.json'))
assert subprocess.run(['systemctl', 'is-active', '--quiet', 'bird.service']).returncode != 0
bird = f'''log stderr all;
router id {config['local_ip']};
protocol device {{}}
protocol static vip {{
    disabled;
    ipv4;
    route {config['vip']}/32 blackhole;
}}
protocol bgp upstream {{
    local {config['local_ip']} as {config['local_as']};
    neighbor {config['peer_ip']} as {config['peer_as']};
    bfd yes;
    error wait time 1, 5;
    connect delay time 1;
    ipv4 {{ import none; export where net = {config['vip']}/32; }};
}}
protocol bfd {{
    interface "*" {{ interval 100 ms; multiplier 3; }};
}}
'''
with tempfile.NamedTemporaryFile(mode='w', suffix='.conf') as stage:
    stage.write(bird)
    stage.flush()
    subprocess.run(['/usr/sbin/bird', '-p', '-c', stage.name], check=True)
subprocess.run(['systemctl', 'mask', 'bird.service'], check=True)
base.mkdir(exist_ok=True)
(base / f'bird-{instance}.conf').write_text(bird)
os.chmod(base / f'bird-{instance}.conf', 0o600)
(base / f'routed-{instance}.json').write_text(json.dumps(config) + '\n')
os.chmod(base / f'routed-{instance}.json', 0o600)
shutil.copy2(check, base / f'check-{instance}')
os.chmod(base / f'check-{instance}', 0o700)
profile = Path(__file__).resolve().parent
Path('/usr/local/libexec').mkdir(parents=True, exist_ok=True)
for name in ('route-gate.py', 'routed-run.py'):
    shutil.copy2(profile / name, Path('/usr/local/libexec') / f'l4load-{name}')
shutil.copy2(profile / 'l4load-routed@.service', '/etc/systemd/system/l4load-routed@.service')
subprocess.run(['systemctl', 'daemon-reload'], check=True)
