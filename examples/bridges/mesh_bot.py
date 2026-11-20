#!/usr/bin/env python3
"""Meshex bridge example. Reply to /meshping using stdio or loopback HTTP."""

import argparse
import hmac
import json
import os
import sys
import threading
import uuid
from collections import deque
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer

FRAME_LIMIT = 256 * 1024


class Bot:
    def __init__(self):
        self.commands = deque()
        self.ready = threading.Condition()

    def receive(self, frame):
        method = frame.get("method")
        params = frame.get("params", {})
        request_id = frame.get("id")

        if method == "bridge.initialize":
            response = {"jsonrpc": "2.0", "id": request_id}
            if params.get("apiVersion") == 1:
                return dict(response, result={"apiVersion": 1})
            return dict(response, error={"code": -32000, "message": "Meshex API v1 required"})

        if method == "mesh.messageReceived" and params.get("text", "").strip() == "/meshping":
            identifier = uuid.uuid4().hex
            with self.ready:
                self.commands.append({
                    "jsonrpc": "2.0",
                    "id": identifier,
                    "method": "mesh.sendMessage",
                    "params": {
                        "commandId": identifier,
                        "nodeId": params["nodeId"],
                        "replyRef": params["replyRef"],
                        "text": "Pong from the Meshex bridge",
                    },
                })
                self.ready.notify_all()
        elif method == "mesh.deliveryChanged":
            print("Radio status:", params["status"], file=sys.stderr)
        elif method is None and request_id is not None:
            with self.ready:
                if self.commands and self.commands[0]["id"] == request_id:
                    self.commands.popleft()
            if "error" in frame:
                print("Meshex:", frame["error"]["message"], file=sys.stderr)
        return None

    def next_command(self, wait=False):
        with self.ready:
            if wait:
                self.ready.wait_for(lambda: self.commands, timeout=20)
            return self.commands[0] if self.commands else None


def stdio(bot):
    last_id = None

    def write(frame):
        print(json.dumps(frame, ensure_ascii=False), flush=True)

    while data := sys.stdin.buffer.readline(FRAME_LIMIT + 2):
        if len(data) > FRAME_LIMIT + 1:
            raise ValueError("Frame too large")
        reply = bot.receive(json.loads(data))
        if reply is not None:
            write(reply)
        command = bot.next_command()
        if command is not None and command["id"] != last_id:
            last_id = command["id"]
            write(command)


def serve_http(bot, port, token):
    class Handler(BaseHTTPRequestHandler):
        def authorized(self):
            if self.path != "/rpc":
                self.send_error(404)
                return False
            authorization = self.headers.get("Authorization", "").encode()
            if not hmac.compare_digest(authorization, f"Bearer {token}".encode()):
                self.send_error(401)
                return False
            return True

        def respond(self, frame):
            if frame is None:
                self.send_response(204)
                self.end_headers()
                return
            body = json.dumps(frame, ensure_ascii=False).encode()
            self.send_response(200)
            self.send_header("Content-Type", "application/json")
            self.send_header("Content-Length", str(len(body)))
            self.end_headers()
            self.wfile.write(body)

        def do_GET(self):
            if self.authorized():
                self.respond(bot.next_command(wait=True))

        def do_POST(self):
            if not self.authorized():
                return
            try:
                length = int(self.headers.get("Content-Length", "0"))
                if length < 1 or length > FRAME_LIMIT:
                    self.send_error(413)
                    return
                frame = json.loads(self.rfile.read(length))
                if not isinstance(frame, dict):
                    raise ValueError("expected a JSON object")
                self.respond(bot.receive(frame))
            except (ValueError, KeyError):
                self.send_error(400)

        def log_message(self, *_):
            pass

    with ThreadingHTTPServer(("127.0.0.1", port), Handler) as server:
        print(f"Meshex bridge listening on http://127.0.0.1:{port}", file=sys.stderr)
        server.serve_forever()


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--http", type=int, metavar="PORT", help="listen on loopback HTTP")
    args = parser.parse_args()
    bot = Bot()
    if args.http is None:
        stdio(bot)
    else:
        token = os.environ.get("MESHEX_BRIDGE_TOKEN")
        if not token:
            parser.error("set MESHEX_BRIDGE_TOKEN to the same secret as in Meshex")
        serve_http(bot, args.http, token)


if __name__ == "__main__":
    main()
