import json
import sys
import tempfile
import threading
import time
import unittest
import urllib.error
import urllib.request
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parents[1] / "bridge"))
from core import AppError, Store, validate_model_url
from server import Bridge, handler_for, make_certificate
from http.server import ThreadingHTTPServer


def model_stub(config, snapshot, instruction):
    return {"analysis": "测试结果", "replies": [{"label": "自然", "text": "测试草稿"}]}


class StateTests(unittest.TestCase):
    def setUp(self):
        self.store = Store(model_stub)
        self.store.expected_chat = "测试聊天"
        self.store.configure_model({"url": "https://example.invalid/v1", "model": "test", "key": "fake-key"})

    def test_title_gate_prevents_cross_chat_capture(self):
        self.assertFalse(self.store.ingest("另一个聊天", "敏感内容"))
        self.assertIsNone(self.store.snapshot)
        self.assertEqual(self.store.status, "paused")

    def test_duplicate_snapshot_has_no_new_revision_but_updates_heartbeat(self):
        self.assertTrue(self.store.ingest("测试聊天", "hello"))
        before = self.store.last_seen
        self.assertFalse(self.store.ingest("测 试 聊天", "hello"))
        self.assertGreaterEqual(self.store.last_seen, before)

    def test_exact_duplicate_has_no_new_revision(self):
        self.store.ingest("测试聊天", "hello")
        self.assertFalse(self.store.ingest("测试聊天", "hello"))
        self.assertEqual(self.store.revision, 1)

    def test_new_context_rejects_old_revision(self):
        self.store.ingest("测试聊天", "one")
        self.store.ingest("测试聊天", "two")
        with self.assertRaises(AppError) as caught:
            self.store.generate(1)
        self.assertEqual(caught.exception.status, 409)

    def test_context_changed_during_model_call_does_not_replace_draft(self):
        self.store.ingest("测试聊天", "one")
        self.store.draft = {"analysis": "existing"}
        def delayed(config, snapshot, instruction):
            self.store.ingest("测试聊天", "two")
            return model_stub(config, snapshot, instruction)
        self.store.model_call = delayed
        with self.assertRaises(AppError):
            self.store.generate(1)
        self.assertEqual(self.store.draft, {"analysis": "existing"})

    def test_expired_snapshot_is_rejected(self):
        self.store.ingest("测试聊天", "one")
        self.store.last_seen = time.time() - 121
        with self.assertRaises(AppError):
            self.store.generate(1)

    def test_manual_analysis_of_recent_paused_snapshot_is_allowed(self):
        self.store.ingest("测试聊天", "one")
        self.store.set_status("paused", "微信不在前台")
        self.assertEqual(self.store.generate(1)["revision"], 1)

    def test_model_key_is_not_in_state(self):
        self.assertNotIn("fake-key", json.dumps(self.store.view()))

    def test_concurrent_generation_is_rejected(self):
        self.store.ingest("测试聊天", "one")
        self.store.generation_lock.acquire()
        try:
            with self.assertRaises(AppError) as caught:
                self.store.generate(1)
            self.assertEqual(caught.exception.status, 429)
        finally:
            self.store.generation_lock.release()

    def test_external_plain_http_and_credential_urls_rejected(self):
        for url in ["http://example.com", "https://user:password@example.com", "https://example.com?key=secret"]:
            with self.assertRaises(AppError):
                validate_model_url(url)
        self.assertEqual(validate_model_url("http://127.0.0.1:11434/v1"), "http://127.0.0.1:11434/v1")


class APITests(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.bridge = Bridge(self.temp.name)
        self.admin = ThreadingHTTPServer(("127.0.0.1", 0), handler_for(self.bridge, True))
        self.phone = ThreadingHTTPServer(("127.0.0.1", 0), handler_for(self.bridge, False))
        for server in [self.admin, self.phone]:
            threading.Thread(target=server.serve_forever, daemon=True).start()

    def tearDown(self):
        for server in [self.admin, self.phone]:
            server.shutdown(); server.server_close()
        self.temp.cleanup()

    def request(self, path, token="", data=None, phone=False, extra=None):
        port = (self.phone if phone else self.admin).server_address[1]
        headers = {"Authorization": "Bearer " + token, "Content-Type": "application/json"}
        headers.update(extra or {})
        request = urllib.request.Request(f"http://127.0.0.1:{port}" + path,
            data=None if data is None else json.dumps(data).encode(), headers=headers)
        try:
            with urllib.request.urlopen(request) as response:
                return response.status, json.loads(response.read())
        except urllib.error.HTTPError as error:
            return error.code, json.loads(error.read())

    def test_unpaired_request_cannot_read_chat(self):
        self.assertEqual(self.request("/api/state")[0], 401)

    def test_phone_token_cannot_access_admin(self):
        self.assertEqual(self.request("/api/state", self.bridge.phone_token)[0], 401)

    def test_phone_cannot_read_pairing_or_configure_model(self):
        token = self.bridge.phone_token
        self.assertEqual(self.request("/api/pairing", token, phone=True)[0], 404)
        self.assertEqual(self.request("/api/model", token, {"key": "fake"}, phone=True)[0], 403)

    def test_revocation_invalidates_old_phone_token(self):
        old = self.bridge.phone_token
        self.assertEqual(self.request("/api/state", old, phone=True)[0], 200)
        self.assertEqual(self.request("/api/revoke", self.bridge.admin_token, {})[0], 200)
        self.assertEqual(self.request("/api/state", old, phone=True)[0], 401)

    def test_cross_origin_write_is_rejected(self):
        code, _ = self.request("/api/auto", self.bridge.admin_token, {"enabled": False},
                               extra={"Origin": "https://untrusted.invalid"})
        self.assertEqual(code, 403)

    def test_no_message_send_endpoint_exists(self):
        self.assertEqual(self.request("/api/send", self.bridge.admin_token, {"text": "test"})[0], 404)

    def test_phone_cannot_stop_windows_service(self):
        self.assertEqual(self.request("/api/shutdown", self.bridge.phone_token, {}, phone=True)[0], 403)
        self.assertFalse(self.bridge.stop.is_set())

    def test_admin_can_request_graceful_shutdown(self):
        self.assertEqual(self.request("/api/shutdown", self.bridge.admin_token, {})[0], 200)
        self.assertTrue(self.bridge.stop.is_set())

    def test_tls_certificate_fingerprint_matches_der(self):
        from cryptography import x509
        from cryptography.hazmat.primitives import hashes
        cert_path, _, fingerprint = make_certificate(Path(self.temp.name), ["192.168.1.10"])
        cert = x509.load_pem_x509_certificate(cert_path.read_bytes())
        self.assertEqual(cert.fingerprint(hashes.SHA256()).hex(), fingerprint)


if __name__ == "__main__":
    unittest.main()
