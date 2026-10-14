"""Fake GitHub releases endpoint for tests/agent (stdlib only, 127.0.0.1 only).

usage: python -I fake_github.py <www_dir> <port_file>

Serves files from <www_dir>. Per-path behaviour is read on every request from
<www_dir>/_routes.json:  {"/latest.json": {"status": 200, "etag": "\"abc\"", "file": "latest.json"}}
  status  - response code (default 200); non-200 codes are sent with an empty body
  etag    - ETag header; a request with a matching If-None-Match gets 304
  file    - file to serve (relative to www_dir; default: the request path)
Every request is appended to <www_dir>/_requests.log as one JSON line
{"path", "if_none_match", "user_agent", "accept"}.
The chosen port is written to <port_file> once the server listens.
"""
import json
import os
import sys
import threading
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer

WWW = os.path.abspath(sys.argv[1])
PORT_FILE = sys.argv[2]
LOCK = threading.Lock()


def load_routes():
    p = os.path.join(WWW, '_routes.json')
    try:
        with open(p, 'r', encoding='utf-8-sig') as f:
            return json.load(f)
    except (OSError, ValueError):
        return {}


class Handler(BaseHTTPRequestHandler):
    protocol_version = 'HTTP/1.1'

    def log_message(self, fmt, *args):
        pass

    def _send(self, code, body=b'', headers=None):
        self.send_response(code)
        for k, v in (headers or {}).items():
            self.send_header(k, v)
        if code != 304:
            self.send_header('Content-Length', str(len(body)))
        self.end_headers()
        if body and code != 304:
            self.wfile.write(body)

    def do_GET(self):
        path = self.path.split('?', 1)[0]
        rec = {
            'path': path,
            'if_none_match': self.headers.get('If-None-Match'),
            'user_agent': self.headers.get('User-Agent'),
            'accept': self.headers.get('Accept'),
        }
        with LOCK:
            with open(os.path.join(WWW, '_requests.log'), 'a', encoding='utf-8') as f:
                f.write(json.dumps(rec, ensure_ascii=False) + '\n')
        route = load_routes().get(path, {})
        status = int(route.get('status', 200))
        etag = route.get('etag')
        if status != 200:
            self._send(status, b'{"message":"fake"}', {'Content-Type': 'application/json'})
            return
        if etag and self.headers.get('If-None-Match') == etag:
            self._send(304, headers={'ETag': etag})
            return
        rel = route.get('file', path.lstrip('/'))
        full = os.path.abspath(os.path.join(WWW, rel))
        if not full.startswith(WWW + os.sep) or not os.path.isfile(full):
            self._send(404, b'{"message":"Not Found"}', {'Content-Type': 'application/json'})
            return
        with open(full, 'rb') as f:
            body = f.read()
        headers = {'Content-Type': 'application/octet-stream'}
        if etag:
            headers['ETag'] = etag
        self._send(200, body, headers)


def main():
    srv = ThreadingHTTPServer(('127.0.0.1', 0), Handler)
    srv.daemon_threads = True
    tmp = PORT_FILE + '.tmp'
    with open(tmp, 'w', encoding='ascii') as f:
        f.write(str(srv.server_address[1]))
    os.replace(tmp, PORT_FILE)
    srv.serve_forever()


if __name__ == '__main__':
    main()
