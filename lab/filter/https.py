import functools
import http.server
import ssl
import sys

directory, certificate, key = sys.argv[1:]
server = http.server.ThreadingHTTPServer(('10.0.0.2', 9443), functools.partial(http.server.SimpleHTTPRequestHandler, directory=directory))
context = ssl.SSLContext(ssl.PROTOCOL_TLS_SERVER)
context.load_cert_chain(certificate, key)
server.socket = context.wrap_socket(server.socket, server_side=True)
server.serve_forever()
