"""Exercise the installed Hermes CLI against a local-only fake streaming provider.

No real profile, credential, or paid provider is used. Run manually on a machine
with Hermes installed: python tests/cli_generation_smoke.py
"""
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
import importlib.util
import json
from pathlib import Path
import tempfile
import threading
from unittest.mock import patch

import yaml

ROOT = Path(__file__).resolve().parents[1]
spec = importlib.util.spec_from_file_location("generation_backend", ROOT / "backend.py")
backend = importlib.util.module_from_spec(spec)
spec.loader.exec_module(backend)
DRAFT = "# Role and purpose\n" + "You audit repositories carefully, inspect the relevant code, and verify findings with concrete evidence. " * 12
requests = []


class Provider(BaseHTTPRequestHandler):
    def log_message(self, *args):
        pass

    def do_POST(self):
        payload = json.loads(self.rfile.read(int(self.headers["Content-Length"])))
        if self.path != "/v1/chat/completions":
            self.send_response(404)
            self.end_headers()
            return
        requests.append(payload)
        chunk = {"id": "fixture", "object": "chat.completion.chunk", "created": 1, "model": "fixture",
                 "choices": [{"index": 0, "delta": {"role": "assistant", "content": DRAFT}, "finish_reason": None}]}
        finish = {"id": "fixture", "object": "chat.completion.chunk", "created": 1, "model": "fixture",
                  "choices": [{"index": 0, "delta": {}, "finish_reason": "stop"}],
                  "usage": {"prompt_tokens": 10, "completion_tokens": 20, "total_tokens": 30}}
        body = ("data: " + json.dumps(chunk) + "\n\ndata: " + json.dumps(finish) + "\n\ndata: [DONE]\n\n").encode()
        self.send_response(200)
        self.send_header("Content-Type", "text/event-stream")
        self.send_header("Content-Length", str(len(body)))
        self.end_headers()
        self.wfile.write(body)


def main():
    server = ThreadingHTTPServer(("127.0.0.1", 0), Provider)
    threading.Thread(target=server.serve_forever, daemon=True).start()
    try:
        with tempfile.TemporaryDirectory(prefix="hermes-lw-cli-test-") as folder:
            home = Path(folder)
            config = {"model": {"provider": "custom", "default": "fixture", "base_url": f"http://127.0.0.1:{server.server_port}/v1", "api_key": "fake-local-only"}}
            (home / "config.yaml").write_text(yaml.safe_dump(config))
            (home / ".env").write_text("CUSTOM_API_KEY=fake-local-only\n")
            response = []
            handler = object.__new__(backend.Handler)
            handler.send_json = lambda data: response.append(data)
            with patch.object(backend, "HOME", home), patch.object(backend, "HERMES", home), patch.object(backend, "PROFILES", home / "profiles"), patch.object(backend, "installed_model_providers", return_value=[{"id": "custom", "env_vars": ["CUSTOM_API_KEY"]}]):
                handler.generate_profile_prompt({"name": "reviewer", "role": "Audit repositories", "generator_profile": "default", "provider": "custom", "model": "fixture"})
            assert response[0]["personality"] == DRAFT.strip(), response
            assert len(requests) == 1, len(requests)
            assert requests[0]["model"] == "fixture"
            assert not requests[0].get("tools"), requests[0].get("tools")
            assert yaml.safe_load((home / "config.yaml").read_text()) == config
            print("PASS: real Hermes CLI → local fake provider → clean personality; one local request, zero tools, source unchanged")
    finally:
        server.shutdown()
        server.server_close()


if __name__ == "__main__":
    main()
