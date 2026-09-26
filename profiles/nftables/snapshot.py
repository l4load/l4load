import ipaddress
import json
import subprocess
import sys


def transaction(rows):
    if not isinstance(rows, list):
        raise ValueError('expected a list of [source, vip] pairs')
    pairs = set()
    for row in rows:
        if not isinstance(row, list) or len(row) != 2 or not all(isinstance(x, str) for x in row):
            raise ValueError('expected [source, vip] strings')
        pairs.add(tuple(str(ipaddress.IPv4Address(x)) for x in row))
    commands = ['flush set netdev l4load blocked']
    if pairs:
        elements = ', '.join(f'{source} . {vip}' for source, vip in sorted(pairs))
        commands.append('add element netdev l4load blocked { ' + elements + ' }')
    return '\n'.join(commands) + '\n'


if __name__ == '__main__':
    subprocess.run(['nft', '-f', '-'], input=transaction(json.load(sys.stdin)), text=True, check=True)
