#!/usr/bin/env python3
"""meeppo-voice 的替身（仅测试用）：语音输入端到端测试时代替本机的 meeppo-voice（typefreedemo）。

用法：voice-standin.py PORT DIR [--delay=S] [--status=N] [--reply=JSON]

- 在 DIR 写 local-api.json（{"version":1,"port":PORT,"token":…,"pid":<自身>,"startedAt":…}，权限 0600），
  退出（SIGINT、SIGTERM）时删除，同 meeppo-voice 的约定。
- 只监听 127.0.0.1:PORT，只接 POST /api/process：请求头 X-Typefree-Token 不对回 403，对则读完请求体，
  等 --delay 秒后回 --status（默认 200）与 --reply（默认 {"recognizedText":"ni hao","polishedText":"你好，世界。",
  "asrEngine":"standin"}）。
- 每个请求打一行：字节数、Content-Type、有没有 Origin、令牌是否正确；不打令牌本身。
- 客户端中途断开（Sill 取消请求）时打 "client went away"。
"""
import json, os, secrets, signal, sys, time
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
from datetime import datetime, timezone

def main():
    args = [a for a in sys.argv[1:] if not a.startswith("--")]
    flags = dict(a[2:].partition("=")[::2] for a in sys.argv[1:] if a.startswith("--"))
    if len(args) != 2:
        print(__doc__); sys.exit(2)
    port = int(args[0]); directory = args[1]
    delay = float(flags.get("delay", "0"))
    status = int(flags.get("status", "200"))
    reply = flags.get("reply") or json.dumps({"recognizedText": "ni hao", "polishedText": "你好，世界。", "asrEngine": "standin"},
                                             ensure_ascii=False)
    token = secrets.token_hex(16)
    os.makedirs(directory, exist_ok=True)
    path = os.path.join(directory, "local-api.json")

    class Handler(BaseHTTPRequestHandler):
        def log_message(self, *a): pass
        def do_POST(self):
            good = self.headers.get("X-Typefree-Token") == token
            length = int(self.headers.get("Content-Length") or 0)
            print(f"standin: POST {self.path} {length} bytes, type {self.headers.get('Content-Type')}, "
                  f"origin {'yes' if self.headers.get('Origin') else 'none'}, token {'ok' if good else 'WRONG'}", flush=True)
            body = self.rfile.read(length) if length else b""
            if self.path != "/api/process":
                return self.answer(404, {"error": "not found"})
            if not good:
                return self.answer(403, {"error": "forbidden"})
            if not body:
                return self.answer(400, {"error": "empty audio"})
            end = time.time() + delay
            while time.time() < end:
                time.sleep(0.05)
            self.answer(status, json.loads(reply))
        def answer(self, code, obj):
            data = json.dumps(obj, ensure_ascii=False).encode()
            try:
                self.send_response(code)
                self.send_header("Content-Type", "application/json; charset=utf-8")
                self.send_header("Content-Length", str(len(data)))
                self.end_headers()
                self.wfile.write(data)
                print(f"standin: answered {code}", flush=True)
            except (BrokenPipeError, ConnectionResetError):
                print("standin: client went away", flush=True)

    server = ThreadingHTTPServer(("127.0.0.1", port), Handler)
    fd = os.open(path, os.O_WRONLY | os.O_CREAT | os.O_TRUNC, 0o600)
    with os.fdopen(fd, "w") as f:
        json.dump({"version": 1, "port": server.server_address[1], "token": token, "pid": os.getpid(),
                   "startedAt": datetime.now(timezone.utc).isoformat()}, f)
    def bye(*_):
        try: os.remove(path)
        except FileNotFoundError: pass
        print("standin: stopped, local-api.json removed", flush=True)
        os._exit(0)
    signal.signal(signal.SIGINT, bye); signal.signal(signal.SIGTERM, bye)
    print(f"standin: listening on 127.0.0.1:{server.server_address[1]}, wrote {path}", flush=True)
    server.serve_forever()

if __name__ == "__main__":
    main()
