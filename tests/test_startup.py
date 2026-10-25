import importlib.util
import os
from pathlib import Path
import signal
import socket
import tempfile
import unittest
from unittest.mock import patch

ROOT = Path(__file__).resolve().parents[1]
spec = importlib.util.spec_from_file_location("hermes_lw_startup", ROOT / "ensure_backend.py")
startup = importlib.util.module_from_spec(spec)
spec.loader.exec_module(startup)

STUB = '''import hashlib,json,os
from pathlib import Path
from http.server import BaseHTTPRequestHandler,ThreadingHTTPServer
stamp=hashlib.sha256(Path(__file__).read_bytes()).hexdigest()
class Handler(BaseHTTPRequestHandler):
 def log_message(self,*args): pass
 def do_GET(self):
  data=json.dumps({"app":"hermes-lw","pid":os.getpid(),"backend_fingerprint":stamp,"active_actions":BUSY}).encode()
  self.send_response(200);self.send_header("Content-Length",str(len(data)));self.end_headers();self.wfile.write(data)
ThreadingHTTPServer(("127.0.0.1",int(os.environ["HERMES_LW_PORT"])),Handler).serve_forever()
'''


class StartupTests(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory(prefix="hermes-startup-test-")
        self.addCleanup(self.temp.cleanup)
        self.folder = Path(self.temp.name)
        self.backend = self.folder / "backend.py"
        self.backend.write_text(STUB.replace("BUSY", "0"))
        with socket.socket() as probe:
            probe.bind(("127.0.0.1", 0))
            self.port = probe.getsockname()[1]
        for name, value in {"APP_DIR": self.folder, "BACKEND": self.backend, "PORT": self.port}.items():
            p = patch.object(startup, name, value)
            p.start()
            self.addCleanup(p.stop)
        p = patch.dict(os.environ, {"XDG_CACHE_HOME": str(self.folder / "cache")})
        p.start()
        self.addCleanup(p.stop)
        self.pids = set()

    def tearDown(self):
        current = startup.health()
        if current:
            self.pids.add(current["pid"])
        for pid in self.pids:
            if startup.owned_backend(pid):
                os.kill(pid, signal.SIGTERM)
            try:
                os.waitpid(pid, 0)
            except ChildProcessError:
                pass

    def test_backend_reused_then_restarted_when_source_changes(self):
        startup.ensure_backend()
        first = startup.health()
        self.pids.add(first["pid"])
        startup.ensure_backend()
        self.assertEqual(startup.health()["pid"], first["pid"])
        self.backend.write_text(self.backend.read_text() + "\n# changed version\n")
        startup.ensure_backend()
        second = startup.health()
        self.assertNotEqual(first["pid"], second["pid"])
        self.pids.add(second["pid"])

    def test_busy_backend_is_not_stopped(self):
        self.backend.write_text(STUB.replace("BUSY", "1"))
        startup.ensure_backend()
        first = startup.health()
        self.pids.add(first["pid"])
        self.backend.write_text(self.backend.read_text() + "\n# changed\n")
        with self.assertRaisesRegex(RuntimeError, "work running"):
            startup.ensure_backend()
        self.assertEqual(startup.health()["pid"], first["pid"])


if __name__ == "__main__":
    unittest.main()
