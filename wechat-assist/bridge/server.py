"""Local Windows workbench + authenticated TLS companion API."""
import argparse
import datetime
import hashlib
import ipaddress
import json
import os
from pathlib import Path
import secrets
import socket
import ssl
import subprocess
import threading
import time
import urllib.parse
import webbrowser
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer

from core import AppError, Store

ROOT = Path(__file__).resolve().parents[1]


class Bridge:
    def __init__(self, data_dir=None, store=None):
        self.store = store or Store()
        self.admin_token, self.phone_token = secrets.token_urlsafe(32), secrets.token_urlsafe(32)
        self.data_dir = Path(data_dir or ROOT / "runtime")
        self.data_dir.mkdir(exist_ok=True, parents=True)
        self.process = None
        self.capture_lock = threading.Lock()
        self.calibration_lock = threading.Lock()
        self.stop = threading.Event()
        self.phone_port = 8766
        self.fingerprint = ""
        self.addresses = []

    def stop_capture(self):
        with self.capture_lock:
            if self.process and self.process.poll() is None:
                self.process.terminate()
            self.process = None
            self.store.set_status("paused", "已暂停读取，已生成草稿保留")

    def calibrate(self):
        if os.name != "nt":
            raise AppError("区域选择只能在 Windows 运行")
        if not self.calibration_lock.acquire(blocking=False):
            raise AppError("区域选择已打开，请先完成或取消", 429)
        self.stop_capture()
        def run():
            try:
                self.store.set_status("calibrating", "请在微信窗口圈选标题和消息区域")
                result = subprocess.run([
                    "powershell.exe", "-NoProfile", "-STA", "-ExecutionPolicy", "Bypass",
                    "-File", str(ROOT / "windows" / "Collector.ps1"), "-Mode", "Pick",
                    "-ConfigPath", str(self.data_dir / "region.json")],
                    capture_output=True, text=True, encoding="utf-8", errors="replace", timeout=180,
                    creationflags=0x08000000)
                if result.returncode != 0 or not (self.data_dir / "region.json").exists():
                    self.store.set_status("paused", "未完成区域选择，请重试")
                    return
                config = json.loads((self.data_dir / "region.json").read_text(encoding="utf-8-sig"))
                self.store.expected_chat = config["expected_chat"]
                self.store.set_status("ready", "区域已选定，点击开始读取后返回微信")
            except Exception:
                self.store.set_status("error", "区域选择失败或超时，请检查 Windows OCR 和微信窗口")
            finally:
                self.calibration_lock.release()
        threading.Thread(target=run, daemon=True).start()

    def start_capture(self):
        if os.name != "nt":
            raise AppError("屏幕读取只能在 Windows 运行")
        config_path = self.data_dir / "region.json"
        if not config_path.exists():
            raise AppError("请先选择聊天区域")
        config = json.loads(config_path.read_text(encoding="utf-8-sig"))
        self.stop_capture()
        self.store.expected_chat = config["expected_chat"]
        with self.capture_lock:
            process = subprocess.Popen([
                "powershell.exe", "-NoProfile", "-STA", "-ExecutionPolicy", "Bypass",
                "-File", str(ROOT / "windows" / "Collector.ps1"), "-Mode", "Watch",
                "-ConfigPath", str(config_path)], stdout=subprocess.PIPE, stderr=subprocess.DEVNULL,
                text=True, encoding="utf-8", errors="replace", creationflags=0x08000000)
            self.process = process
        self.store.set_status("starting", "返回选定微信聊天后开始读取")
        def read():
            try:
                for line in process.stdout:
                    if process is not self.process:
                        break
                    try:
                        event = json.loads(line)
                        if event.get("status") == "reading":
                            self.store.ingest(event["header"], event["body"])
                        else:
                            self.store.set_status(event.get("status", "paused"), event.get("message", "读取暂停"))
                    except (ValueError, KeyError):
                        continue
            finally:
                if process is self.process:
                    self.store.set_status("error", "读取进程已停止，请重新开始")
        threading.Thread(target=read, daemon=True).start()

    def auto_loop(self):
        while not self.stop.wait(1):
            s = self.store
            with s.lock:
                if not (s.auto and s.model and s.snapshot and s.status == "reading"):
                    continue
                revision = s.snapshot["revision"]
                if (revision == s.auto_revision or time.time() - s.last_auto < 12
                        or time.time() - s.snapshot["captured_at"] < 2):
                    continue
                s.auto_revision, s.last_auto = revision, time.time()
            try:
                s.generate(revision)
            except AppError as error:
                with s.lock:
                    s.message = str(error)


def handler_for(bridge, admin=False):
    class Handler(BaseHTTPRequestHandler):
        def log_message(self, *args):
            pass

        def send_json(self, value, status=200):
            payload = json.dumps(value, ensure_ascii=False).encode("utf-8")
            self.send_response(status)
            self.send_header("Content-Type", "application/json; charset=utf-8")
            self.send_header("Cache-Control", "no-store")
            self.send_header("X-Content-Type-Options", "nosniff")
            self.send_header("Content-Length", str(len(payload)))
            self.end_headers()
            self.wfile.write(payload)

        def authorized(self):
            token = self.headers.get("Authorization", "").removeprefix("Bearer ")
            expected = bridge.admin_token if admin else bridge.phone_token
            if not secrets.compare_digest(token, expected):
                raise AppError("尚未配对或连接凭据已失效", 401)

        def do_GET(self):
            path = urllib.parse.urlsplit(self.path).path
            if path == "/" and admin:
                content = (ROOT / "web" / "index.html").read_bytes()
                self.send_response(200)
                self.send_header("Content-Type", "text/html; charset=utf-8")
                self.send_header("Content-Length", str(len(content)))
                self.send_header("Referrer-Policy", "no-referrer")
                self.send_header("Cache-Control", "no-store")
                self.send_header("Content-Security-Policy", "default-src 'self'; script-src 'self' 'unsafe-inline'; style-src 'self' 'unsafe-inline'; connect-src 'self'; img-src 'self' data:; frame-ancestors 'none'")
                self.end_headers()
                self.wfile.write(content)
                return
            try:
                self.authorized()
                if path == "/api/state":
                    self.send_json(bridge.store.view())
                elif path == "/api/pairing" and admin:
                    self.send_json({"urls": [f"https://{ip}:{bridge.phone_port}" for ip in bridge.addresses],
                                    "token": bridge.phone_token, "fingerprint": bridge.fingerprint,
                                    "expires": "Windows 服务重启或重新配对后失效"})
                else:
                    raise AppError("接口不存在", 404)
            except AppError as error:
                self.send_json({"error": str(error)}, error.status)

        def do_POST(self):
            try:
                self.authorized()
                origin = self.headers.get("Origin")
                if origin and origin != ("http://" if admin else "https://") + self.headers.get("Host", ""):
                    raise AppError("不接受跨站请求", 403)
                try:
                    length = int(self.headers.get("Content-Length", "0"))
                except ValueError:
                    raise AppError("请求长度错误") from None
                if not 0 < length <= 65536:
                    raise AppError("请求过大或为空", 413)
                try:
                    data = json.loads(self.rfile.read(length))
                    if not isinstance(data, dict):
                        raise ValueError()
                except (ValueError, UnicodeError):
                    raise AppError("请求不是有效 JSON") from None
                path = urllib.parse.urlsplit(self.path).path
                if path == "/api/generate":
                    result = bridge.store.generate(data.get("revision"), str(data.get("instruction", "")))
                    self.send_json(result)
                    return
                if not admin:
                    raise AppError("此操作只能在 Windows 工作台进行", 403)
                if path == "/api/model":
                    bridge.store.configure_model(data)
                elif path == "/api/auto":
                    if data.get("enabled") and not bridge.store.model:
                        raise AppError("请先配置模型")
                    bridge.store.auto = bool(data.get("enabled"))
                elif path == "/api/calibrate":
                    bridge.calibrate()
                elif path == "/api/start":
                    bridge.start_capture()
                elif path == "/api/pause":
                    bridge.stop_capture()
                elif path == "/api/revoke":
                    bridge.phone_token = secrets.token_urlsafe(32)
                elif path == "/api/shutdown":
                    bridge.stop.set()
                else:
                    raise AppError("接口不存在", 404)
                self.send_json({"ok": True})
            except AppError as error:
                self.send_json({"error": str(error)}, error.status)
            except Exception:
                self.send_json({"error": "操作失败，请检查配置与本机环境"}, 500)
    return Handler


def make_certificate(directory, addresses):
    from cryptography import x509
    from cryptography.hazmat.primitives import hashes, serialization
    from cryptography.hazmat.primitives.asymmetric import rsa
    from cryptography.x509.oid import NameOID
    key = rsa.generate_private_key(public_exponent=65537, key_size=2048)
    name = x509.Name([x509.NameAttribute(NameOID.COMMON_NAME, "WeChatAssist Local Bridge")])
    now = datetime.datetime.now(datetime.timezone.utc)
    cert = (x509.CertificateBuilder().subject_name(name).issuer_name(name).public_key(key.public_key())
            .serial_number(x509.random_serial_number()).not_valid_before(now - datetime.timedelta(minutes=5))
            .not_valid_after(now + datetime.timedelta(days=30))
            .add_extension(x509.SubjectAlternativeName([x509.IPAddress(ipaddress.ip_address(ip))
                            for ip in sorted(set(addresses + ["127.0.0.1"]))]), critical=False)
            .sign(key, hashes.SHA256()))
    cert_path, key_path = directory / "bridge-cert.pem", directory / "bridge-key.pem"
    cert_path.write_bytes(cert.public_bytes(serialization.Encoding.PEM))
    key_path.write_bytes(key.private_bytes(serialization.Encoding.PEM, serialization.PrivateFormat.PKCS8,
                                         serialization.NoEncryption()))
    return cert_path, key_path, cert.fingerprint(hashes.SHA256()).hex()


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--port", type=int, default=8765)
    parser.add_argument("--phone-port", type=int, default=8766)
    parser.add_argument("--lan", action="store_true", help="enable authenticated HTTPS phone API")
    parser.add_argument("--no-browser", action="store_true")
    args = parser.parse_args()
    bridge = Bridge()
    bridge.phone_port = args.phone_port
    admin = ThreadingHTTPServer(("127.0.0.1", args.port), handler_for(bridge, True))
    servers = [admin]
    if args.lan:
        bridge.addresses = sorted({ip for ip in socket.gethostbyname_ex(socket.gethostname())[2]
                                   if not ip.startswith("127.")})
        if not bridge.addresses:
            raise RuntimeError("没有可用的局域网 IPv4 地址")
        cert, key, bridge.fingerprint = make_certificate(bridge.data_dir, bridge.addresses)
        context = ssl.SSLContext(ssl.PROTOCOL_TLS_SERVER)
        context.minimum_version = ssl.TLSVersion.TLSv1_2
        context.load_cert_chain(str(cert), str(key))
        phone = ThreadingHTTPServer(("0.0.0.0", args.phone_port), handler_for(bridge, False))
        phone.socket = context.wrap_socket(phone.socket, server_side=True)
        servers.append(phone)
    for server in servers:
        threading.Thread(target=server.serve_forever, daemon=True).start()
    threading.Thread(target=bridge.auto_loop, daemon=True).start()
    url = f"http://127.0.0.1:{args.port}/#token={bridge.admin_token}"
    session_path = bridge.data_dir / "session.json"
    session_path.write_text(json.dumps({"pid": os.getpid(), "admin_url": url,
                                        "phone_enabled": args.lan}, ensure_ascii=False), encoding="utf-8")
    print("Windows 工作台已启动；默认不读取、不上传、不发送消息。", flush=True)
    print("请保留此窗口。按 Ctrl+C 停止。", flush=True)
    if not args.no_browser:
        webbrowser.open(url)
    try:
        bridge.stop.wait()
    except KeyboardInterrupt:
        pass
    finally:
        bridge.stop.set()
        bridge.stop_capture()
        for server in servers:
            server.shutdown()
            server.server_close()
        try:
            if json.loads(session_path.read_text(encoding="utf-8"))["pid"] == os.getpid():
                session_path.unlink()
        except (FileNotFoundError, ValueError, KeyError):
            pass


if __name__ == "__main__":
    main()
