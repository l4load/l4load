import socket
import struct
import threading
import unittest

from tap import read_frame


class Framing(unittest.TestCase):
    def exchange(self, chunks, expected):
        reader, writer = socket.socketpair()
        with reader, writer:
            reader.settimeout(2)

            def send():
                for chunk in chunks:
                    writer.sendall(chunk)
                writer.shutdown(socket.SHUT_WR)

            thread = threading.Thread(target=send)
            thread.start()
            try:
                for frame in expected:
                    self.assertEqual(read_frame(reader), frame)
                with self.assertRaises(EOFError):
                    read_frame(reader)
            finally:
                thread.join(2)
                self.assertFalse(thread.is_alive())

    def test_fragmented_and_coalesced(self):
        frames = [bytes(range(64)), b'x' * 1514, b'y' * 9000]
        wire = b''.join(struct.pack('!I', len(x)) + x for x in frames)
        self.exchange([wire], frames)
        self.exchange([wire[n:n+1] for n in range(len(wire))], frames)

    def test_truncated(self):
        for wire in (b'\0\0', struct.pack('!I', 64) + b'x' * 20):
            self.exchange([wire], [])

    def test_invalid_length(self):
        for size in (0, 13, 65536, 0xffffffff):
            reader, writer = socket.socketpair()
            with reader, writer:
                writer.sendall(struct.pack('!I', size))
                with self.assertRaises(ValueError):
                    read_frame(reader)


if __name__ == '__main__':
    unittest.main()
