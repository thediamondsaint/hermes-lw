#!/usr/bin/env python3
"""Start the matching local backend, without reusing stale or foreign services."""
import fcntl
import hashlib
import json
import os
from pathlib import Path
import signal
import socket
import subprocess
import sys
import time
import urllib.error
import urllib.request

APP_DIR = Path(__file__).resolve().parent
BACKEND = APP_DIR / "backend.py"
PORT = 18731
STARTED_PROCESSES = []


def health():
    headers = {}
    if os.environ.get("HERMES_LW_TOKEN"):
        headers["Authorization"] = "Bearer " + os.environ["HERMES_LW_TOKEN"]
    try:
        with urllib.request.urlopen(urllib.request.Request(f"http://127.0.0.1:{PORT}/api/health", headers=headers), timeout=0.5) as response:
            data = json.load(response)
            return data if isinstance(data, dict) and data.get("app") == "hermes-lw" else None
    except (OSError, ValueError):
        return None


def owned_backend(pid):
    try:
        process = Path(f"/proc/{int(pid)}")
        args = (process / "cmdline").read_bytes().split(b"\0")
        return process.stat().st_uid == os.getuid() and os.fsencode(str(BACKEND)) in args
    except (OSError, ValueError, TypeError):
        return False


def has_children(pid):
    try:
        return any(path.read_text().strip() for path in Path(f"/proc/{pid}/task").glob("*/children"))
    except OSError:
        return True


def port_open():
    with socket.socket() as probe:
        probe.settimeout(0.2)
        return probe.connect_ex(("127.0.0.1", PORT)) == 0


def ensure_backend():
    expected = hashlib.sha256(BACKEND.read_bytes()).hexdigest()
    cache = Path(os.environ.get("XDG_CACHE_HOME", Path.home() / ".cache")) / "hermes-control"
    cache.mkdir(parents=True, exist_ok=True, mode=0o700)
    lock_fd = os.open(cache / "backend-start.lock", os.O_CREAT | os.O_RDWR, 0o600)
    with os.fdopen(lock_fd, "w") as lock:
        fcntl.flock(lock, fcntl.LOCK_EX)
        current = health()
        if current and current.get("backend_fingerprint") == expected:
            return
        pids = [current.get("pid")] if current else [int(p.name) for p in Path("/proc").glob("[0-9]*") if owned_backend(p.name)]
        for pid in pids:
            if not owned_backend(pid):
                raise RuntimeError("Port 18731 is occupied by a different service; Hermes LW did not stop it")
            if (current and current.get("active_actions")) or has_children(pid):
                raise RuntimeError("The old backend still has work running. Finish it before reopening Hermes LW")
            os.kill(pid, signal.SIGTERM)
        deadline = time.monotonic() + 3
        while pids and (any(owned_backend(pid) for pid in pids) or port_open()) and time.monotonic() < deadline:
            time.sleep(0.05)
        if any(owned_backend(pid) for pid in pids):
            raise RuntimeError("The old Hermes LW backend did not stop; it was not forcibly killed")
        if port_open():
            raise RuntimeError(f"Port {PORT} is occupied; Hermes LW cannot start its backend")
        log_path = cache / "backend.log"
        log_fd = os.open(log_path, os.O_CREAT | os.O_WRONLY | os.O_APPEND, 0o600)
        os.fchmod(log_fd, 0o600)
        with os.fdopen(log_fd, "ab") as log:
            child = subprocess.Popen([sys.executable, str(BACKEND)], cwd=APP_DIR,
                                     env={**os.environ, "HERMES_LW_PORT": str(PORT)},
                                     stdin=subprocess.DEVNULL, stdout=log, stderr=log,
                                     start_new_session=True)
        # Retain the handle when called as a library, so a live daemon isn't
        # treated as an accidentally abandoned subprocess by Python.
        STARTED_PROCESSES[:] = [p for p in STARTED_PROCESSES if p.poll() is None]
        STARTED_PROCESSES.append(child)
        deadline = time.monotonic() + 6
        while time.monotonic() < deadline:
            current = health()
            if current and current.get("backend_fingerprint") == expected:
                return
            if child.poll() is not None:
                break
            time.sleep(0.1)
        raise RuntimeError(f"Hermes LW backend did not become ready. See {log_path}")


if __name__ == "__main__":
    try:
        ensure_backend()
    except (OSError, RuntimeError) as error:
        print(f"Hermes LW: {error}", file=sys.stderr)
        sys.exit(1)
