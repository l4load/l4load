import json
import subprocess
import sys
from pathlib import Path

out = Path(sys.argv[1])
config = json.loads((out / 'filter-original.conf').read_text())
pairs = json.load(sys.stdin)
config['modules']['acl0']['firewall'] = [':BEGIN'] + [
    f'add deny ip from {source} to {vip}' for source, vip in pairs
] + ['add allow ip from any to any']
staging = out / 'snapshot-next.conf'
staging.write_text(json.dumps(config))
staging.replace(out / 'controlplane.conf')
subprocess.run(['yanet-cli', 'reload'], check=True)
