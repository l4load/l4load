import functools
import http.server
import ssl
import sys

class Handler(http.server.SimpleHTTPRequestHandler):
    def do_GET(self):
        if self.path != '/partial':
            return super().do_GET()
        self.send_response(200)
        self.send_header('Content-Length', '100')
        self.end_headers()
        self.wfile.write(b'[]')
        self.close_connection = True


directory, certificate, key = sys.argv[1:]
server = http.server.ThreadingHTTPServer(('10.0.0.2', 9443), functools.partial(Handler, directory=directory))
context = ssl.SSLContext(ssl.PROTOCOL_TLS_SERVER)
context.load_cert_chain(certificate, key)
server.socket = context.wrap_socket(server.socket, server_side=True)
server.serve_forever()
