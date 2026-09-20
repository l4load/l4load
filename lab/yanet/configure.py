import json
import sys
from pathlib import Path

out = Path(sys.argv[1]).resolve()
limits = json.loads((Path(sys.argv[2]) / 'autotest/units/001_one_port/dataplane.conf').read_text())['configValues']
configs = {
    'dataplane.conf': {
        'ports': [{'interfaceName': 'vp0', 'pci': 'sock_dev:/run/yanet/vp0', 'coreIds': [2]}],
        'hugeMem': False, 'useKni': False, 'workerGC': [1],
        'ealArgs': ['--no-pci'],
        'controlPlaneCoreId': 0, 'memory': 8192,
        'configValues': limits,
    },
    'services.conf': [
        {'vip': '198.18.0.1', 'proto': proto, 'vport': '8080', 'scheduler': 'rr',
         'reals': [{'ip': ip, 'port': '8080'} for ip in ('10.0.2.2', '10.0.3.2')]}
        for proto in ('tcp', 'udp')
    ],
    'controlplane.conf': {'modules': {
        'lp0': {'type': 'logicalPort', 'physicalPort': 'vp0', 'vlanId': '0',
                'macAddress': '02:00:00:00:01:02', 'nextModule': 'acl0'},
        'acl0': {'type': 'acl', 'nextModules': ['balancer0', 'route0']},
        'balancer0': {'type': 'balancer', 'source': '2001:db8::1',
                     'source_ipv4': '10.0.1.2', 'services': str(out / 'services.conf'),
                     'nextModule': 'route0'},
        'route0': {'type': 'route', 'interfaces': {
            'i0': {'neighborIPv4Address': '10.0.1.1',
                   'neighborMacAddress': '02:00:00:00:01:01', 'nextModule': 'lp0'},
        }},
    }},
}
if len(sys.argv) > 3 and sys.argv[3] == 'af-packet':
    port = configs['dataplane.conf']['ports'][0]
    port.update(pci='net_af_packet0', rssFlags=[], symmetric_mode=True)
    configs['dataplane.conf']['ealArgs'].append('--vdev=net_af_packet0,iface=l4-yanet,qpairs=2,framesz=9216,blocksz=36864')
for name, config in configs.items():
    (out / name).write_text(json.dumps(config, indent=2) + '\n')
