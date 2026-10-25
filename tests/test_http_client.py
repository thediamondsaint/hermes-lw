"""Exercise the real QML request client against a disposable HTTP server."""
import json
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
from pathlib import Path
import threading
import time
import unittest

from PyQt6.QtCore import QCoreApplication, QUrl
from PyQt6.QtQml import QQmlComponent, QQmlEngine, QQmlExpression

ROOT = Path(__file__).resolve().parents[1]


class FixtureHandler(BaseHTTPRequestHandler):
    def log_message(self, *args):
        pass

    def do_GET(self):
        if self.path == "/slow":
            time.sleep(0.25)
        status = 400 if self.path == "/error" else 200
        body = b"not-json" if self.path == "/malformed" else json.dumps({"error": "Invalid profile"} if status == 400 else {"ok": True}).encode()
        self.send_response(status)
        self.send_header("Content-Length", str(len(body)))
        self.end_headers()
        try:
            self.wfile.write(body)
        except (BrokenPipeError, ConnectionResetError):
            pass


class HttpClientTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.app = QCoreApplication.instance() or QCoreApplication([])
        cls.server = ThreadingHTTPServer(("127.0.0.1", 0), FixtureHandler)
        cls.thread = threading.Thread(target=cls.server.serve_forever, daemon=True)
        cls.thread.start()

    @classmethod
    def tearDownClass(cls):
        cls.server.shutdown()
        cls.server.server_close()

    def setUp(self):
        self.engine = QQmlEngine()
        self.component = QQmlComponent(self.engine)
        self.component.setData(b'''import QtQml
import ".."
QtObject {
  property HttpClient client: HttpClient {}
  property int calls: 0
  property bool ok: false
  property string result: ""
  property int pending: client.pendingCount
  function start(url, ms) {
    client.send("GET", url, null, ms,
      function(value) { calls++; ok = true; result = JSON.stringify(value) },
      function(value) { calls++; ok = false; result = JSON.stringify(value) })
  }
}''', QUrl.fromLocalFile(str(ROOT / "tests" / "HttpHarness.qml")))
        self.obj = self.component.create()
        self.assertIsNotNone(self.obj, "\n".join(e.toString() for e in self.component.errors()))

    def tearDown(self):
        self.obj.deleteLater()
        self.engine.deleteLater()
        self.app.processEvents()

    def request(self, path, timeout=1000):
        url = f"http://127.0.0.1:{self.server.server_port}{path}"
        expr = QQmlExpression(self.engine.rootContext(), self.obj, f"start({json.dumps(url)}, {timeout})")
        expr.evaluate()
        self.assertFalse(expr.hasError(), expr.error().toString())
        deadline = time.monotonic() + 2
        while not self.obj.property("calls") and time.monotonic() < deadline:
            self.app.processEvents()
            time.sleep(0.002)
        self.assertEqual(self.obj.property("calls"), 1)
        self.assertEqual(self.obj.property("pending"), 0)
        return json.loads(self.obj.property("result"))

    def test_success(self):
        self.assertEqual(self.request("/ok"), {"ok": True})
        self.assertTrue(self.obj.property("ok"))

    def test_http_error_keeps_transport_connected(self):
        result = self.request("/error")
        self.assertFalse(self.obj.property("ok"))
        self.assertEqual(result["status"], 400)
        self.assertFalse(result["transport_error"])
        self.assertEqual(result["error"], "Invalid profile")

    def test_invalid_json_is_failure(self):
        result = self.request("/malformed")
        self.assertFalse(self.obj.property("ok"))
        self.assertIn("Invalid JSON", result["error"])

    def test_timeout_aborts_and_only_completes_once(self):
        result = self.request("/slow", 30)
        self.assertTrue(result["timed_out"])
        deadline = time.monotonic() + 0.4
        while time.monotonic() < deadline:
            self.app.processEvents()
            time.sleep(0.002)
        self.assertEqual(self.obj.property("calls"), 1)
        self.assertEqual(self.obj.property("pending"), 0)


if __name__ == "__main__":
    unittest.main()
