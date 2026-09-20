import collections
import ctypes
import json
import os
from pathlib import Path
import socket
import struct
import sys
import threading

VIP = os.environ.get('L4LOAD_VIP', '198.18.0.1')
CLIENT = os.environ.get('L4LOAD_CLIENT', '10.0.0.2')
FAMILY = socket.AF_INET6 if ':' in VIP else socket.AF_INET
PORT = 8080


def configure(directory, mac):
    lib = ctypes.CDLL('libbpf.so.1', use_errno=True)
    lib.bpf_obj_get.argtypes = [ctypes.c_char_p]
    lib.bpf_map_update_elem.argtypes = [ctypes.c_int, ctypes.c_void_p, ctypes.c_void_p, ctypes.c_ulonglong]

    def update(name, entries):
        fd = lib.bpf_obj_get(os.fsencode(Path(directory) / name))
        if fd < 0:
            raise OSError(ctypes.get_errno(), name)
        try:
            for key, value in entries:
                if lib.bpf_map_update_elem(fd, key, value, 0):
                    raise OSError(ctypes.get_errno(), name)
        finally:
            os.close(fd)

    u32 = lambda n: struct.pack('=I', n)
    update('ctl_array', [(u32(0), bytes.fromhex(mac.replace(':', '')) + bytes(2))])
    update('reals', [(u32(n), socket.inet_aton(f'10.0.{n+1}.2') + bytes(16)) for n in (1, 2)])
    update('vip_map', [(socket.inet_aton(VIP) + bytes(12) + struct.pack('!HBx', PORT, proto), bytes(8)) for proto in (6, 17)])
    update('ch_rings', ((u32(n), u32(1 + n % 2)) for n in range(65537)))


def serve(backend):
    def udp():
        with socket.socket(FAMILY, socket.SOCK_DGRAM) as sock:
            sock.bind((VIP, PORT))
            while True:
                data, peer = sock.recvfrom(4096)
                sock.sendto(f'{backend} {peer[0]} '.encode() + data, peer)

    def tcp(conn, peer):
        with conn:
            conn.settimeout(60)
            while data := conn.recv(4096):
                conn.sendall(f'{backend} {peer[0]} '.encode() + data)

    threading.Thread(target=udp, daemon=True).start()
    with socket.socket(FAMILY, socket.SOCK_STREAM) as sock:
        sock.setsockopt(socket.SOL_SOCKET, socket.SO_REUSEADDR, 1)
        sock.bind((VIP, PORT))
        sock.listen()
        print('READY', backend, flush=True)
        while True:
            conn, peer = sock.accept()
            threading.Thread(target=tcp, args=(conn, peer), daemon=True).start()


def check(expected="b1,b2", base_port="0"):
    results = {}
    for protocol, kind in [('tcp', socket.SOCK_STREAM), ('udp', socket.SOCK_DGRAM)]:
        counts = collections.Counter()
        for n in range(32):
            payload = f'{protocol}-{n}'.encode()
            with socket.socket(FAMILY, kind) as sock:
                sock.settimeout(3)
                if int(base_port):
                    sock.bind((CLIENT, int(base_port) + n))
                sock.connect((VIP, PORT))
                sock.sendall(payload)
                if kind == socket.SOCK_STREAM:
                    sock.shutdown(socket.SHUT_WR)
                    chunks = []
                    while data := sock.recv(4096):
                        chunks.append(data)
                    reply = b''.join(chunks)
                else:
                    reply = sock.recv(4096)
                backend, source, echoed = reply.decode().split(' ', 2)
                assert source == CLIENT, reply
                assert echoed.encode() == payload, reply
                counts[backend] += 1
        assert set(counts) == set(expected.split(',')), counts
        results[protocol] = dict(counts)
    print(json.dumps({'status': 'pass', 'flows': results, 'client_ip_preserved': True}))


if __name__ == '__main__':
    {'configure': configure, 'serve': serve, 'check': check}[sys.argv[1]](*sys.argv[2:])
