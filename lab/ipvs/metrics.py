import re
import sys
import time
import urllib.request
from pathlib import Path

for attempt in range(30):
    try:
        with urllib.request.urlopen('http://127.0.0.1:19100/metrics', timeout=1) as response:
            text = response.read().decode()
        break
    except OSError:
        if attempt == 29:
            raise
        time.sleep(0.1)
Path(sys.argv[1]).write_text(text)
assert 'node_scrape_collector_success{collector="ipvs"} 1' in text
weights = {}
for line in text.splitlines():
    if not line.startswith('node_ipvs_backend_weight{'):
        continue
    labels = dict(re.findall(r'(\w+)="([^"]*)"', line))
    assert labels['local_address'] == '198.18.0.1' and labels['local_port'] == '8080'
    assert labels['remote_port'] == '8080'
    weights[labels['proto'].lower(), labels['remote_address']] = float(line.rsplit(' ', 1)[1])
assert weights == {(proto, address): weight for proto in ('tcp', 'udp')
                   for address, weight in [('10.0.2.2', int(sys.argv[2])), ('10.0.3.2', 1)]}, weights
