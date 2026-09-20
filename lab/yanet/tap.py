import os
import select
import socket
import struct
import sys


def receive(sock, size):
    data = bytearray()
    while len(data) < size:
        chunk = sock.recv(size - len(data))
        if not chunk:
            raise EOFError('incomplete frame')
        data.extend(chunk)
    return bytes(data)


def read_frame(sock):
    size, = struct.unpack('!I', receive(sock, 4))
    if not 14 <= size <= 65535:
        raise ValueError(f'invalid Ethernet frame length: {size}')
    return receive(sock, size)


def bridge(name, path):
    import fcntl

    with open('/dev/net/tun', 'r+b', buffering=0) as tap, socket.socket(socket.AF_UNIX) as sock:
        fcntl.ioctl(tap, 0x400454ca, struct.pack('16sH', name.encode(), 0x1002))
        sock.settimeout(5)
        sock.connect(path)
        print('READY', name, flush=True)
        while True:
            ready, _, _ = select.select([tap, sock], [], [])
            if tap in ready:
                frame = os.read(tap.fileno(), 65535)
                sock.sendall(struct.pack('!I', len(frame)) + frame)
            if sock in ready:
                frame = read_frame(sock)
                if os.write(tap.fileno(), frame) != len(frame):
                    raise OSError('short TAP write')


if __name__ == '__main__':
    bridge(*sys.argv[1:])
