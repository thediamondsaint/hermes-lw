#!/usr/bin/env python3
"""Small local API for the Hermes LW Quickshell control desk."""
from __future__ import annotations

import copy
import ast
import atexit
import json
import hashlib
import math
import os
import re
import secrets
import shutil
import shlex
import socket
import subprocess
import threading
import tempfile
import time
import urllib.error
import urllib.parse
import urllib.request
from datetime import date
from functools import lru_cache
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
from pathlib import Path

import yaml

HOME = Path.home()
HERMES = HOME / ".hermes"
PROFILES = HERMES / "profiles"
ESTIMATES = HOME / ".local/share/hermes-control/estimates.json"
APP_SETTINGS = HOME / ".local/share/hermes-control/settings.json"
MODEL_CACHE = HOME / ".cache/hermes-control/openrouter-models.json"
PORT = int(os.environ.get("HERMES_LW_PORT", "18731"))
LOCK = threading.RLock()
CONNECTIONS_PATH = HOME / ".local/share/hermes-control/connections.json"
TUNNEL_LOCK = threading.Lock()
TUNNELS: dict[str, tuple[subprocess.Popen, int]] = {}
MODEL_CACHE_SECONDS = 6 * 60 * 60
MAX_REQUEST_BYTES = 1_048_576
BACKEND_FINGERPRINT = hashlib.sha256(Path(__file__).read_bytes()).hexdigest()
ACTIVE_POSTS = 0
ACTIVE_POSTS_LOCK = threading.Lock()


def atomic_write(path: Path, content: str, mode: int = 0o600) -> None:
    """Replace app state atomically so a crash cannot leave half a JSON/YAML file."""
    path.parent.mkdir(parents=True, exist_ok=True, mode=0o700)
    temp = path.with_name(f".{path.name}.{os.getpid()}.{threading.get_ident()}.tmp")
    try:
        fd = os.open(temp, os.O_WRONLY | os.O_CREAT | os.O_EXCL, mode)
        with os.fdopen(fd, "w", encoding="utf-8") as handle:
            handle.write(content)
            handle.flush()
            os.fsync(handle.fileno())
        temp.replace(path)
        os.chmod(path, mode)
    finally:
        try:
            temp.unlink(missing_ok=True)
        except OSError:
            pass


def read_connections() -> list[dict]:
    try:
        data = json.loads(CONNECTIONS_PATH.read_text())
        return data if isinstance(data, list) else []
    except (OSError, json.JSONDecodeError):
        return []


def save_connections(items: list[dict]) -> None:
    atomic_write(CONNECTIONS_PATH, json.dumps(items, indent=2) + "\n", 0o600)


def connection_status(item: dict) -> dict:
    result = {key: item.get(key) for key in ("id", "name", "kind", "host", "ssh_port", "remote_port", "url")}
    result["kind"] = item.get("kind", "ssh")
    if result["kind"] == "https":
        result.update(connected=False, url=item.get("url", ""))
        return result
    with TUNNEL_LOCK:
        state = TUNNELS.get(item["id"])
        if state and state[0].poll() is None:
            result.update(connected=True, url=f"http://127.0.0.1:{state[1]}")
        else:
            TUNNELS.pop(item["id"], None)
            result.update(connected=False, url="")
    return result


def save_connection(payload: dict) -> dict:
    name = str(payload.get("name", "")).strip()
    if not name or len(name) > 64:
        raise ValueError("Connection name must be 1–64 characters")
    items = read_connections()
    identifier = str(payload.get("id", ""))
    existing = next((row for row in items if row.get("id") == identifier), None)
    kind = str(payload.get("kind", "ssh"))
    if kind == "ssh":
        host = str(payload.get("host", "")).strip()
        if not re.fullmatch(r"[A-Za-z0-9_.@-]{1,255}", host) or host.startswith("-"):
            raise ValueError("Use an SSH config alias or user@host; spaces and SSH command flags are not allowed")
        try:
            ssh_port = int(payload.get("ssh_port", 22))
            remote_port = int(payload.get("remote_port", PORT))
        except (TypeError, ValueError) as exc:
            raise ValueError("SSH and remote service ports must be whole numbers") from exc
        if not 1 <= ssh_port <= 65535 or not 1024 <= remote_port <= 65535:
            raise ValueError("Choose a valid SSH port and a remote Hermes LW port from 1024 to 65535")
        item = {"kind": kind, "host": host, "ssh_port": ssh_port, "remote_port": remote_port}
    elif kind == "https":
        url = str(payload.get("url", "")).strip().rstrip("/")
        try:
            parsed = urllib.parse.urlsplit(url)
            port = parsed.port
        except ValueError as exc:
            raise ValueError("Enter a valid HTTPS gateway URL") from exc
        if parsed.scheme != "https" or not parsed.hostname or parsed.username or parsed.password or parsed.query or parsed.fragment or (port is not None and not 1 <= port <= 65535):
            raise ValueError("Cloud / VPS gateways need an HTTPS URL without embedded credentials, query, or fragment")
        if len(url) > 512:
            raise ValueError("Gateway URL is too long")
        token = str(payload.get("token", ""))
        if not token and existing:
            token = str(existing.get("token", ""))
        if not token and not existing:
            raise ValueError("Enter the Hermes LW gateway access token")
        if not re.fullmatch(r"[A-Za-z0-9._~+/=-]{16,8192}", token):
            raise ValueError("Gateway token must be 16–8,192 URL-safe characters")
        item = {"kind": kind, "url": url, "token": token}
    else:
        raise ValueError("Choose SSH / VPS or HTTPS / Cloud")
    if not existing:
        identifier = secrets.token_hex(8)
    if any(row.get("id") != identifier and row.get("name", "").casefold() == name.casefold() for row in items):
        raise ValueError("Connection names must be unique")
    for row in items:
        if row.get("id") == identifier or row.get("kind") != kind:
            continue
        duplicate = (row.get("host", "").casefold() == item.get("host", "").casefold() and
                     row.get("ssh_port") == item.get("ssh_port") and row.get("remote_port") == item.get("remote_port")) if kind == "ssh" else row.get("url", "").casefold() == item.get("url", "").casefold()
        if duplicate:
            raise ValueError("This Hermes instance is already saved as another tab")
    item.update(id=identifier, name=name)
    items = [item if row.get("id") == identifier else row for row in items]
    if not any(row.get("id") == identifier for row in items):
        items.append(item)
    save_connections(items)
    return item


def stop_tunnel(identifier: str) -> None:
    with TUNNEL_LOCK:
        state = TUNNELS.pop(identifier, None)
    if state and state[0].poll() is None:
        state[0].terminate()
        try:
            state[0].wait(timeout=3)
        except subprocess.TimeoutExpired:
            state[0].kill()
            state[0].wait(timeout=2)


def stop_all_tunnels() -> None:
    with TUNNEL_LOCK:
        identifiers = list(TUNNELS)
    for identifier in identifiers:
        stop_tunnel(identifier)


atexit.register(stop_all_tunnels)


def connect_tunnel(identifier: str) -> dict:
    item = next((row for row in read_connections() if row.get("id") == identifier), None)
    if not item:
        raise ValueError("Saved remote connection not found")
    if item.get("kind") == "https":
        return connection_status(item)
    current = connection_status(item)
    if current["connected"]:
        return current
    ssh = shutil.which("ssh")
    if not ssh:
        raise RuntimeError("OpenSSH client is required for remote connections")
    sock = socket.socket()
    sock.bind(("127.0.0.1", 0))
    local_port = sock.getsockname()[1]
    sock.close()
    args = [ssh, "-N", "-T", "-o", "ExitOnForwardFailure=yes", "-o", "ServerAliveInterval=30",
            "-o", "ServerAliveCountMax=3", "-o", "BatchMode=yes", "-o", "ConnectTimeout=8",
            "-p", str(item["ssh_port"]), "-L", f"127.0.0.1:{local_port}:127.0.0.1:{item['remote_port']}", item["host"]]
    process = subprocess.Popen(args, stdin=subprocess.DEVNULL, stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL,
                               start_new_session=True, close_fds=True)
    with TUNNEL_LOCK:
        TUNNELS[identifier] = (process, local_port)
    url = f"http://127.0.0.1:{local_port}"
    deadline = time.monotonic() + 10
    while time.monotonic() < deadline:
        if process.poll() is not None:
            stop_tunnel(identifier)
            raise RuntimeError("SSH tunnel failed. Check the host, SSH key, and remote Hermes LW service.")
        try:
            request = urllib.request.Request(url + "/api/state", headers={"Host": f"127.0.0.1:{local_port}"})
            with urllib.request.urlopen(request, timeout=1) as response:
                state = json.loads(response.read())
                if isinstance(state, dict) and "profiles" in state:
                    return {**connection_status(item), "url": url, "connected": True}
        except (OSError, ValueError, urllib.error.URLError):
            time.sleep(0.2)
    stop_tunnel(identifier)
    raise RuntimeError("SSH connected, but no Hermes LW API answered on the remote loopback port")


def request_remote_connection(payload: dict) -> tuple[dict, int]:
    identifier = str(payload.get("id", ""))
    item = next((row for row in read_connections() if row.get("id") == identifier), None)
    if not item or item.get("kind") != "https":
        raise ValueError("HTTPS gateway connection not found")
    method = str(payload.get("method", "GET")).upper()
    if method not in ("GET", "POST"):
        raise ValueError("Remote gateway supports GET and POST requests only")
    path = str(payload.get("path", ""))
    parsed_path = urllib.parse.urlsplit(path)
    if not parsed_path.path.startswith("/api/") or parsed_path.path.startswith("//") or ".." in parsed_path.path.split("/"):
        raise ValueError("Invalid remote API path")
    body = None if method == "GET" else json.dumps(payload.get("body") or {}, ensure_ascii=False).encode("utf-8")
    try:
        timeout = min(300, max(1, int(payload.get("timeout_ms", 20000)) / 1000))
    except (TypeError, ValueError) as exc:
        raise ValueError("Remote timeout must be a whole number of milliseconds") from exc
    request = urllib.request.Request(item["url"] + path, data=body, method=method, headers={
        "Authorization": "Bearer " + item["token"], "Accept": "application/json",
        **({"Content-Type": "application/json"} if body is not None else {}),
    })
    try:
        with urllib.request.urlopen(request, timeout=timeout) as response:
            status, raw = response.status, response.read(1_048_577)
    except urllib.error.HTTPError as exc:
        status, raw = exc.code, exc.read(1_048_577)
    except (urllib.error.URLError, TimeoutError, OSError) as exc:
        raise RuntimeError("Could not reach HTTPS gateway. Check its URL, TLS certificate, and auth token.") from exc
    if len(raw) > 1_048_576:
        raise ValueError("Remote API response is too large")
    try:
        data = json.loads(raw)
    except (json.JSONDecodeError, UnicodeDecodeError) as exc:
        raise RuntimeError("Remote server did not return a Hermes LW JSON response") from exc
    if not isinstance(data, dict):
        raise RuntimeError("Remote Hermes LW returned an unexpected response")
    return data, status


def cmd(*args: str, timeout: int = 12) -> str:
    p = subprocess.run(["hermes", *args], text=True, capture_output=True, timeout=timeout)
    if p.returncode:
        raise RuntimeError((p.stderr or p.stdout or "Hermes command failed").strip())
    return p.stdout.strip()


def profile_slugs() -> list[str]:
    return ["default"] + sorted(p.name for p in PROFILES.glob("*") if p.is_dir() and (p / "config.yaml").exists())


def profile_paths(slug: str) -> tuple[Path, Path]:
    if slug == "default":
        return HERMES / "config.yaml", HERMES / "SOUL.md"
    folder = PROFILES / slug
    return folder / "config.yaml", folder / "SOUL.md"


def profile_env_path(slug: str) -> Path:
    return (HERMES if slug == "default" else PROFILES / slug) / ".env"


@lru_cache(maxsize=1)
def installed_model_providers() -> list[dict]:
    """Read Hermes' installed provider registry for the profile editor."""
    fallback = [
        {"id": "auto", "label": "Automatic", "env_vars": [], "description": "Use Hermes provider routing"},
        {"id": "openrouter", "label": "OpenRouter", "env_vars": ["OPENROUTER_API_KEY"], "description": "Model aggregator"},
        {"id": "anthropic", "label": "Anthropic", "env_vars": ["ANTHROPIC_API_KEY"], "description": "Claude API"},
        {"id": "deepseek", "label": "DeepSeek", "env_vars": ["DEEPSEEK_API_KEY"], "description": "DeepSeek API"},
        {"id": "gemini", "label": "Google Gemini", "env_vars": ["GOOGLE_API_KEY", "GEMINI_API_KEY"], "description": "Gemini API"},
        {"id": "custom", "label": "Custom / Local endpoint", "env_vars": [], "description": "OpenAI-compatible endpoint, including local servers"},
    ]
    executable = shutil.which("hermes")
    if not executable:
        return fallback
    binary = Path(executable).resolve()
    roots = [binary.parent.parent]
    provider_dirs = []
    for root in roots:
        for site in root.glob("lib/python*/site-packages"):
            candidate = site / "plugins/model-providers"
            if candidate.is_dir(): provider_dirs.append(candidate)
    found = {}
    for folder in provider_dirs:
        for source in folder.glob("*/__init__.py"):
            try:
                tree = ast.parse(source.read_text())
            except (OSError, SyntaxError):
                continue
            for node in ast.walk(tree):
                if not isinstance(node, ast.Call): continue
                values = {kw.arg: kw.value for kw in node.keywords if kw.arg}
                try:
                    provider_id = ast.literal_eval(values.get("name"))
                except (ValueError, TypeError):
                    continue
                if not isinstance(provider_id, str) or not re.fullmatch(r"[a-z0-9][a-z0-9-]{0,63}", provider_id): continue
                def literal_list(key):
                    try:
                        value = ast.literal_eval(values.get(key))
                        return [str(item) for item in value] if isinstance(value, (tuple, list)) else []
                    except (ValueError, TypeError):
                        return []
                def literal_text(key, default=""):
                    try:
                        value = ast.literal_eval(values.get(key))
                        return value if isinstance(value, str) else default
                    except (ValueError, TypeError):
                        return default
                description = literal_text("description")
                label = literal_text("display_name") or description or provider_id.replace("-", " ").title()
                env_vars = [name for name in literal_list("env_vars")
                            if re.fullmatch(r"[A-Z][A-Z0-9_]{0,63}", name)]
                found[provider_id] = {"id": provider_id, "label": label, "env_vars": env_vars,
                                      "description": description,
                                      "aliases": literal_list("aliases")}
    if not found: return fallback
    found["auto"] = fallback[0]
    return sorted(found.values(), key=lambda item: (item["id"] != "auto", item["label"].lower()))


def credential_env_names(path: Path) -> list[str]:
    if not path.exists(): return []
    found = set()
    for line in path.read_text().splitlines():
        match = re.match(r"^\s*(?:export\s+)?([A-Z][A-Z0-9_]{0,63})\s*=\s*\S+", line)
        if match:
            name = match.group(1)
            if name.endswith(("_API_KEY", "_TOKEN")) or name in {"GH_TOKEN", "GITHUB_TOKEN"}:
                found.add(name)
    return sorted(found)


def credential_env_candidates(provider: str) -> list[str]:
    entry = next((p for p in installed_model_providers() if p["id"] == provider), None)
    if not entry: return []
    return [name for name in entry["env_vars"]
            if name.endswith(("_API_KEY", "_TOKEN")) or name in {"GH_TOKEN", "GITHUB_TOKEN"}]


def write_profile_config(config_path: Path, cfg: dict) -> None:
    atomic_write(config_path, yaml.safe_dump(cfg, sort_keys=False, allow_unicode=True))


def app_settings() -> dict:
    try:
        data = json.loads(APP_SETTINGS.read_text())
    except Exception:
        data = {}
    if not isinstance(data, dict):
        data = {}
    data.setdefault("manager_profile", "")
    data.setdefault("paused_profiles", [])
    data.setdefault("favorite_models", [])
    data.setdefault("prompts", [])
    data.setdefault("theme", "light")
    data.setdefault("active_board", "default")
    data.setdefault("project_meta", {})
    data.setdefault("saved_views", [])
    data.setdefault("task_templates", [])
    return data


def save_app_settings(data: dict) -> None:
    atomic_write(APP_SETTINGS, json.dumps(data, indent=2, ensure_ascii=False))


def update_env_key(path: Path, key_name: str, value: str | None) -> None:
    if "\n" in (value or "") or "\r" in (value or ""):
        raise ValueError("API keys cannot contain line breaks")
    if len(value or "") > 8192:
        raise ValueError("API keys must be 8,192 characters or fewer")
    lines = path.read_text().splitlines() if path.exists() else []
    lines = [line for line in lines if not re.match(rf"^\s*(?:export\s+)?{re.escape(key_name)}\s*=", line)]
    if value:
        lines.append(f"{key_name}={value}")
    atomic_write(path, "\n".join(lines) + ("\n" if lines else ""))


def clear_profile_credentials(slug: str) -> None:
    """Clear copied secrets, including OAuth pools, while preserving endpoints."""
    path = profile_env_path(slug)
    key_names = {name for provider in installed_model_providers()
                 for name in provider.get("env_vars", [])
                 if name.endswith(("_API_KEY", "_TOKEN")) or name in {"GH_TOKEN", "GITHUB_TOKEN"}}
    key_names.update({"CUSTOM_API_KEY", "OPENAI_API_KEY", "OPENROUTER_API_KEY", "GH_TOKEN", "GITHUB_TOKEN"})
    if path.exists():
        lines = []
        for line in path.read_text().splitlines():
            match = re.match(r"^\s*(?:export\s+)?([A-Z][A-Z0-9_]*)\s*=", line)
            if match and (match.group(1) in key_names or match.group(1).endswith(("_API_KEY", "_TOKEN"))):
                continue
            lines.append(line)
        atomic_write(path, "\n".join(lines) + ("\n" if lines else ""))
    # Full clones also copy Hermes' OAuth/API credential pools.
    for name in ("auth.json", "auth.lock"):
        (profile_hermes_home(slug) / name).unlink(missing_ok=True)
    config_path, _ = profile_paths(slug)
    config = yaml.safe_load(config_path.read_text()) or {}
    def without_secrets(value):
        if isinstance(value, dict):
            return {key: without_secrets(item) for key, item in value.items()
                    if str(key).lower() not in {"api_key", "api_keys", "token", "access_token", "refresh_token", "password", "secret", "authorization"}
                    and not str(key).lower().endswith(("_api_key", "_token"))}
        if isinstance(value, list):
            return [without_secrets(item) for item in value]
        return value
    clean = without_secrets(config)
    if clean != config:
        write_profile_config(config_path, clean)


def has_env_key(path: Path, key_name: str = "OPENROUTER_API_KEY") -> bool:
    if not path.exists():
        return False
    return any(re.match(rf"^\s*(?:export\s+)?{re.escape(key_name)}\s*=\s*\S+", line)
               for line in path.read_text().splitlines())


def read_profiles() -> list[dict]:
    settings = app_settings()
    active = "default"
    try:
        rows = cmd("profile", "list")
        match = re.search(r"^\s*◆\s*(\S+)", rows, re.M)
        if match: active = match.group(1)
    except Exception:
        pass
    result = []
    for slug in profile_slugs():
        config_path, soul = profile_paths(slug)
        try:
            cfg = yaml.safe_load(config_path.read_text()) or {}
        except Exception:
            cfg = {}
        model = cfg.get("model") if isinstance(cfg.get("model"), dict) else {}
        agent = cfg.get("agent") if isinstance(cfg.get("agent"), dict) else {}
        result.append({
            "slug": slug,
            "model": str(model.get("default", "not set")),
            "provider": str(model.get("provider", "auto")),
            "base_url": str(model.get("base_url", "")),
            "custom_api_key_configured": bool(model.get("api_key")),
            "reasoning": str(agent.get("reasoning_effort", "medium")),
            "description": str(cfg.get("description", "")),
            "personality": soul.read_text() if soul.exists() else "",
            "active": slug == active,
            "manager": slug == settings["manager_profile"],
            "paused": slug in settings["paused_profiles"],
            "openrouter_key_configured": has_env_key(profile_env_path(slug)),
            "configured_api_keys": credential_env_names(profile_env_path(slug)),
        })
    return result


def read_estimates() -> dict:
    try:
        data = json.loads(ESTIMATES.read_text())
        return data if isinstance(data, dict) else {}
    except Exception:
        return {}


def save_estimates(data: dict) -> None:
    atomic_write(ESTIMATES, json.dumps(data, indent=2, ensure_ascii=False))


def iso_date(value) -> str:
    value = str(value or "").strip()
    if not value: return ""
    try:
        return date.fromisoformat(value).isoformat()
    except ValueError as exc:
        raise ValueError("Enter dates in YYYY-MM-DD format") from exc


def nonnegative_number(value, label: str) -> float:
    try:
        number = float(value or 0)
    except (TypeError, ValueError) as exc:
        raise ValueError(f"{label} must be a number") from exc
    if not math.isfinite(number): raise ValueError(f"{label} must be a finite number")
    return max(0, number)


def model_category(model: dict) -> str:
    arch = model.get("architecture") or {}
    inputs = {str(x).lower() for x in arch.get("input_modalities", [])}
    outputs = {str(x).lower() for x in arch.get("output_modalities", [])}
    name = " ".join((str(model.get("id", "")), str(model.get("name", "")), str(model.get("description", "")))).lower()
    if "video" in inputs or "video" in outputs:
        return "Video"
    if "audio" in inputs or "audio" in outputs or "speech" in outputs or "transcription" in outputs:
        return "Audio"
    if "image" in outputs:
        return "Image generation"
    if "embedding" in outputs or "embeddings" in outputs:
        return "Embeddings"
    if "rerank" in outputs:
        return "Reranking"
    if "decision" in outputs:
        return "Decision"
    if "image" in inputs:
        return "Vision"
    if "file" in inputs:
        return "Files & documents"
    if any(term in name for term in ("code", "coder", "coding", "programming", "devstral", "qwen3-coder", "deepseek-coder")):
        return "Coding"
    if "text" in outputs or not outputs:
        return "Text & chat"
    return "Other"


def normalized_model(model: dict) -> dict:
    pricing = model.get("pricing") or {}
    if not isinstance(pricing, dict): pricing = {}
    input_rate = _float(pricing.get("prompt")) * 1_000_000
    output_rate = _float(pricing.get("completion")) * 1_000_000
    image_rate = _float(pricing.get("image"))
    arch = model.get("architecture") or {}
    top_provider = model.get("top_provider") or {}
    return {
        "id": str(model.get("id", "")),
        "name": str(model.get("name") or model.get("id", "")),
        "description": str(model.get("description", "")),
        "category": model_category(model),
        "input_rate": input_rate,
        "output_rate": output_rate,
        "image_rate": image_rate,
        "request_rate": _float(pricing.get("request")),
        "price_known": pricing.get("prompt") is not None or pricing.get("completion") is not None,
        "inputs": arch.get("input_modalities") or [],
        "outputs": arch.get("output_modalities") or [],
        "supported_parameters": model.get("supported_parameters") or [],
        "context_length": int(model.get("context_length") or 0),
        "max_completion_tokens": int(top_provider.get("max_completion_tokens") or 0),
        "created": int(model.get("created") or 0),
    }


def _float(value) -> float:
    try:
        result = float(value or 0)
        return result if math.isfinite(result) and result >= 0 else 0.0
    except (TypeError, ValueError):
        return 0.0


def load_openrouter_model_catalog(force: bool = False) -> dict:
    cache = {}
    try:
        cache = json.loads(MODEL_CACHE.read_text())
    except Exception:
        pass
    fresh = int(cache.get("fetched_at", 0)) > int(time.time()) - MODEL_CACHE_SECONDS
    if not force and fresh and cache.get("models"):
        return {"models": cache["models"], "fetched_at": cache["fetched_at"], "source": "cache", "stale": False}
    req = urllib.request.Request(
        "https://openrouter.ai/api/v1/models?output_modalities=all",
        headers={"User-Agent": "Hermes-Control/0.1", "Accept": "application/json"},
    )
    try:
        with urllib.request.urlopen(req, timeout=25) as response:
            payload = json.loads(response.read())
        if not isinstance(payload, dict) or not isinstance(payload.get("data"), list):
            raise ValueError("OpenRouter returned an unexpected model catalog")
        models = []
        for item in payload["data"]:
            if not isinstance(item, dict) or not item.get("id"):
                continue
            try:
                models.append(normalized_model(item))
            except (ValueError, TypeError, OverflowError, AttributeError):
                continue
        if not models:
            raise ValueError("OpenRouter returned an empty model catalog")
        data = {"fetched_at": int(time.time()), "models": models}
        atomic_write(MODEL_CACHE, json.dumps(data, ensure_ascii=False))
        return {"models": models, "fetched_at": data["fetched_at"], "source": "live", "stale": False}
    except (urllib.error.URLError, TimeoutError, OSError, ValueError) as exc:
        if cache.get("models"):
            return {"models": cache["models"], "fetched_at": cache.get("fetched_at", 0), "source": "cache", "stale": True, "error": str(exc)}
        raise RuntimeError(f"Could not load OpenRouter's model catalog: {exc}")


def _profile_catalog_environment(slug: str, provider: str) -> dict[str, str]:
    """Build a child Hermes environment scoped to one profile, without logging secrets."""
    home = HERMES if slug == "default" else PROFILES / slug
    env = os.environ.copy()
    env["HERMES_HOME"] = str(home)
    env_names = {name for entry in installed_model_providers() if entry["id"] == provider
                 for name in entry.get("env_vars", [])}
    if provider == "custom":
        env_names.update({"CUSTOM_API_KEY", "OPENAI_API_KEY", "OPENROUTER_API_KEY"})
    if not profile_env_path(slug).exists():
        return env
    for line in profile_env_path(slug).read_text().splitlines():
        match = re.match(r"^\s*(?:export\s+)?([A-Z][A-Z0-9_]{0,63})\s*=\s*(.*)$", line)
        if not match:
            continue
        name, value = match.groups()
        if name not in env_names and not name.endswith(("_API_KEY", "_TOKEN", "_BASE_URL")) and name not in {"GH_TOKEN", "GITHUB_TOKEN"}:
            continue
        value = value.strip()
        if len(value) >= 2 and value[0] == value[-1] and value[0] in ("'", '"'):
            value = value[1:-1]
        env[name] = value
    return env


def _provider_catalog_entry(model_id: str, provider: str) -> dict:
    """Give Hermes' provider model IDs the common catalog row shape."""
    lower = model_id.lower()
    if any(term in lower for term in ("embedding", "embed-", "embed/")):
        category, inputs, outputs = "Embeddings", ["text"], ["embeddings"]
    elif any(term in lower for term in ("rerank", "re-rank")):
        category, inputs, outputs = "Reranking", ["text"], ["text"]
    elif any(term in lower for term in ("image-gen", "image_generation", "flux", "dall-e", "imagen", "stable-diffusion")):
        category, inputs, outputs = "Image generation", ["text"], ["image"]
    elif any(term in lower for term in ("vision", "-vl", "vl-", "llava", "pixtral")):
        category, inputs, outputs = "Vision", ["text", "image"], ["text"]
    elif any(term in lower for term in ("audio", "speech", "whisper", "tts", "transcri")):
        category = "Audio"
        inputs = ["audio"] if any(term in lower for term in ("whisper", "transcri", "stt", "audio-in")) else ["text"]
        outputs = ["audio"] if any(term in lower for term in ("tts", "speech", "audio-out")) else ["text"]
    elif "video" in lower or "veo" in lower or "sora" in lower:
        category, inputs, outputs = "Video", ["text"], ["video"]
    elif any(term in lower for term in ("code", "coder", "codex", "devstral")):
        category, inputs, outputs = "Coding", ["text"], ["text"]
    elif any(term in lower for term in ("reason", "thinking", "deepseek-r1", "o1", "o3", "o4")):
        category, inputs, outputs = "Decision", ["text"], ["text"]
    else:
        category, inputs, outputs = "Text & chat", ["text"], ["text"]
    return {
        "id": model_id, "name": model_id, "description": f"Model offered by {provider}",
        "category": category, "input_rate": 0, "output_rate": 0, "image_rate": 0,
        "request_rate": 0, "price_known": False, "inputs": inputs, "outputs": outputs,
        "supported_parameters": [], "context_length": 0, "max_completion_tokens": 0,
        "created": 0,
    }


def load_provider_model_catalog(provider: str, slug: str, force: bool = False, base_url: str = "") -> dict:
    """Ask the installed Hermes provider registry for a profile's model IDs."""
    if slug not in profile_slugs():
        raise ValueError("Choose an existing Hermes profile")
    config_path, _ = profile_paths(slug)
    try:
        cfg = yaml.safe_load(config_path.read_text()) or {}
    except (OSError, yaml.YAMLError):
        cfg = {}
    model_cfg = cfg.get("model") if isinstance(cfg.get("model"), dict) else {}
    requested_provider = provider.strip().lower()
    if requested_provider == "auto":
        requested_provider = str(model_cfg.get("provider", "auto")).strip().lower()
    if requested_provider == "auto":
        raise ValueError("Automatic routing has no single model list. Choose a specific provider in the catalog.")
    available = {entry["id"] for entry in installed_model_providers()}
    if requested_provider not in available:
        raise ValueError("This provider is not installed in the selected Hermes environment")
    if requested_provider == "openrouter":
        result = load_openrouter_model_catalog(force)
        result["provider"] = requested_provider
        return result

    if requested_provider == "custom":
        base_url = base_url.strip() or str(model_cfg.get("base_url", "")).strip()
        if base_url:
            if not re.match(r"^https?://", base_url, re.I) or len(base_url) > 2048 or any(c in base_url for c in "\r\n"):
                raise ValueError("Custom model-list URL must be a valid http:// or https:// URL")
            parsed = urllib.parse.urlsplit(base_url)
            if not parsed.hostname or parsed.username or parsed.password or parsed.query or parsed.fragment:
                raise ValueError("Custom model-list URL cannot contain credentials, query parameters, or a fragment")
        else:
            raise ValueError("Set and save a custom endpoint URL before browsing its models")

    executable = shutil.which("hermes")
    if not executable:
        raise RuntimeError("Hermes CLI is required for provider model discovery")
    python = Path(executable).resolve().with_name("python")
    if not python.exists():
        raise RuntimeError("Could not find the Python environment used by the installed Hermes CLI")
    env = _profile_catalog_environment(slug, requested_provider)
    if requested_provider == "custom" and base_url:
        env["HERMES_CATALOG_BASE_URL"] = base_url
    script = """import json, os
import hermes_cli.models as models
base_url = os.environ.get('HERMES_CATALOG_BASE_URL', '')
if base_url:
    original = models._get_model_config_dict
    def custom_model_config():
        config = dict(original())
        config['base_url'] = base_url
        return config
    models._get_model_config_dict = custom_model_config
ids = models.cached_provider_model_ids(os.environ['HERMES_CATALOG_PROVIDER'], force_refresh=os.environ.get('HERMES_CATALOG_REFRESH') == '1')
print(json.dumps(ids))
"""
    env["HERMES_CATALOG_PROVIDER"] = requested_provider
    env["HERMES_CATALOG_REFRESH"] = "1" if force else "0"
    try:
        completed = subprocess.run([str(python), "-c", script], env=env, text=True,
                                   capture_output=True, timeout=40, check=False)
    except subprocess.TimeoutExpired as exc:
        raise RuntimeError(f"Timed out while loading {requested_provider} models") from exc
    if completed.returncode:
        raise RuntimeError(f"Could not load {requested_provider} models from Hermes")
    try:
        ids = json.loads(completed.stdout.strip().splitlines()[-1])
    except (json.JSONDecodeError, IndexError) as exc:
        raise RuntimeError(f"Hermes returned an invalid {requested_provider} model list") from exc
    if not isinstance(ids, list):
        raise RuntimeError(f"Hermes returned an invalid {requested_provider} model list")
    models = []
    seen = set()
    for value in ids:
        model_id = str(value).strip()
        key = model_id.casefold()
        if model_id and len(model_id) <= 256 and key not in seen:
            seen.add(key)
            models.append(_provider_catalog_entry(model_id, requested_provider))
    if not models:
        raise RuntimeError(f"Hermes did not find any models for {requested_provider}. Check the profile's provider credentials and refresh.")
    return {"models": models, "provider": requested_provider, "fetched_at": int(time.time()),
            "source": "Hermes provider catalog", "stale": False}


def load_model_catalog(force: bool = False, provider: str = "openrouter", slug: str = "default", base_url: str = "") -> dict:
    if provider.strip().lower() == "openrouter":
        return load_openrouter_model_catalog(force)
    return load_provider_model_catalog(provider, slug, force, base_url)


def read_projects(settings: dict | None = None) -> list[dict]:
    settings = settings or app_settings()
    try:
        projects = json.loads(cmd("kanban", "boards", "list", "--json", "--all"))
    except Exception as exc:
        raise RuntimeError(f"Could not read Hermes projects: {exc}") from exc
    if not isinstance(projects, list):
        projects = []
    meta = settings.get("project_meta", {})
    estimates = read_estimates()
    result = []
    for project in projects:
        if not isinstance(project, dict) or not project.get("slug"):
            continue
        extra = meta.get(project["slug"], {})
        prefix = str(project["slug"]) + ":"
        rows = [v for k, v in estimates.items() if k.startswith(prefix)]
        if project["slug"] == "default": rows += [v for k, v in estimates.items() if ":" not in k]
        project["estimated_cost"] = round(sum(float(v.get("cost", 0) or 0) for v in rows), 2)
        project["effort_hours"] = round(sum(float(v.get("effort_hours", 0) or 0) for v in rows), 2)
        result.append({**project, **{k: extra[k] for k in ("budget", "due_date", "owner", "status", "description", "name", "color") if k in extra}})
    return result


def dashboard(board: str = "") -> dict:
    profiles = read_profiles()
    settings = app_settings()
    projects = read_projects(settings)
    available = {p["slug"] for p in projects}
    board = board if board in available else settings.get("active_board", "default")
    if board not in available:
        board = "default"
    try:
        tasks = json.loads(cmd("kanban", "--board", board, "list", "--json", "--sort", "priority-desc"))
    except Exception as exc:
        raise RuntimeError(f"Could not read tasks for project {board}: {exc}") from exc
    if isinstance(tasks, dict):
        tasks = tasks.get("tasks", [])
    estimates = read_estimates()
    cards = []
    for task in tasks:
        if not isinstance(task, dict):
            continue
        tid = str(task.get("id", ""))
        estimate = estimates.get(f"{board}:{tid}", estimates.get(tid, {}) if board == "default" else {})
        task["estimated_cost"] = float(estimate.get("cost", 0) or 0)
        task["estimate_note"] = estimate.get("note", "")
        task["due_date"] = estimate.get("due_date", "")
        task["tags"] = estimate.get("tags", [])
        task["effort_hours"] = float(estimate.get("effort_hours", 0) or 0)
        # Fail closed: imported/legacy tasks are not implicitly eligible for every profile.
        task["allow_all_profiles"] = False
        task["allowed_profiles"] = estimate.get("allowed_profiles", [])
        task["profile_budgets"] = estimate.get("profile_budgets", {})
        task["max_runtime_seconds"] = int(estimate.get("max_runtime_seconds", 0) or 0)
        task["has_estimate"] = "cost" in estimate
        cards.append(task)
    project = next((p for p in projects if p["slug"] == board), {})
    return {"profiles": profiles, "tasks": cards, "board": board, "project": project, "projects": projects,
            "saved_views": settings["saved_views"], "updated": int(time.time()),
            "task_templates": settings["task_templates"],
            "favorites": {"models": settings["favorite_models"]}, "prompts": settings["prompts"],
            "manager_profile": settings["manager_profile"], "theme": settings["theme"]}


def safe_slug(value: str) -> str:
    if value not in profile_slugs():
        raise ValueError("Unknown Hermes profile")
    return value


def safe_board(value: str) -> str:
    if not re.fullmatch(r"[a-z0-9][a-z0-9-]{0,62}", value):
        raise ValueError("Invalid project ID")
    if value not in {p["slug"] for p in read_projects()}:
        raise ValueError("Unknown project")
    return value


def deep_merge(old, new):
    if isinstance(old, dict) and isinstance(new, dict):
        merged = copy.deepcopy(old)
        for k, v in new.items():
            merged[k] = deep_merge(merged[k], v) if k in merged else v
        return merged
    return new


def strip_secrets(value):
    """Hide credentials in the advanced JSON editor while preserving them on merge."""
    if isinstance(value, dict):
        return {k: ("••••••••" if re.search(r"(api.?key|token|secret|password|credential)", k, re.I) else strip_secrets(v))
                for k, v in value.items() if not re.search(r"(api.?key|token|secret|password|credential)", k, re.I)}
    if isinstance(value, list):
        return [strip_secrets(v) for v in value]
    return value


def profile_hermes_home(slug: str) -> Path:
    return HERMES if slug == "default" else PROFILES / slug


def run_profile_hermes(slug: str, args: list[str], timeout: int = 25, home_override: Path | None = None) -> subprocess.CompletedProcess:
    """Run a Hermes management command against one isolated profile."""
    safe_slug(slug)
    executable = shutil.which("hermes")
    if not executable:
        raise RuntimeError("Hermes CLI is not available")
    env = os.environ.copy()
    env["HERMES_HOME"] = str(home_override or profile_hermes_home(slug))
    if home_override:
        # Generation credentials come from the chosen profile, not an unrelated
        # provider key inherited by the GUI's parent shell.
        names = {name for provider in installed_model_providers() for name in provider.get("env_vars", [])
                 if name.endswith(("_API_KEY", "_TOKEN"))}
        for name in list(env):
            if name in names or name.endswith(("_API_KEY", "_TOKEN")) or name in {"GH_TOKEN", "GITHUB_TOKEN"}:
                env.pop(name, None)
    return subprocess.run([executable, *args], cwd=str(HOME), env=env, text=True,
                          capture_output=True, timeout=timeout, check=False)


def run_isolated_generation(source: str, args: list[str], provider: str, model: str):
    """Use the chosen route without source fallbacks, plugins, tools, or rules."""
    if provider == "auto":
        raise ValueError("Choose an explicit provider for generation instead of Automatic")
    config_path, _ = profile_paths(source)
    config = yaml.safe_load(config_path.read_text()) or {}
    source_model = config.get("model") if isinstance(config.get("model"), dict) else {}
    selected_model = copy.deepcopy(source_model)
    if provider != source_model.get("provider") and provider != "custom":
        selected_model.pop("base_url", None)
        selected_model.pop("api_key", None)
    selected_model.update({"provider": provider, "default": model})
    minimal = {"model": selected_model, "providers": config.get("providers", {}),
               "agent": {"max_turns": 1}, "fallback_providers": [], "fallback_model": None,
               "mcp_servers": {}, "plugins": {"enabled": []}}
    with tempfile.TemporaryDirectory(prefix="hermes-lw-generation-") as folder:
        home = Path(folder)
        write_profile_config(home / "config.yaml", minimal)
        for name in (".env", "auth.json"):
            path = profile_hermes_home(source) / name
            if path.is_file():
                atomic_write(home / name, path.read_text())
        if not (home / ".env").exists():
            atomic_write(home / ".env", "")
        return run_profile_hermes(source, args, timeout=180, home_override=home)


def plugin_list_for_profile(slug: str) -> list[dict]:
    result = run_profile_hermes(slug, ["plugins", "list", "--json"])
    if result.returncode:
        raise RuntimeError("Could not read the Hermes plugin list")
    try:
        value = json.loads(result.stdout)
    except json.JSONDecodeError as exc:
        raise RuntimeError("Hermes returned an invalid plugin list") from exc
    rows = []
    for item in value if isinstance(value, list) else []:
        if not isinstance(item, dict) or not re.fullmatch(r"[a-zA-Z0-9][a-zA-Z0-9_.-]{0,127}", str(item.get("name", ""))):
            continue
        row = dict(item)
        row["enabled"] = str(item.get("status", "")).lower() == "enabled"
        rows.append(row)
    return rows


def tool_list_for_profile(slug: str, platform: str) -> list[dict]:
    if not re.fullmatch(r"[a-z][a-z0-9_-]{0,31}", platform):
        raise ValueError("Invalid Hermes platform")
    result = run_profile_hermes(slug, ["tools", "list", "--platform", platform])
    if result.returncode:
        raise RuntimeError("Could not read the Hermes tool list")
    rows = []
    for line in result.stdout.splitlines():
        match = re.match(r"^\s*[✓✗]\s+(enabled|disabled)\s+([a-zA-Z0-9_.:-]{1,160})\s{2,}(.*)$", line)
        if match:
            state, name, description = match.groups()
            rows.append({"name": name, "enabled": state == "enabled", "description": description.strip()})
    return rows


def mcp_servers_for_profile(slug: str) -> list[dict]:
    config_path, _ = profile_paths(slug)
    try:
        config = yaml.safe_load(config_path.read_text()) or {}
    except (OSError, yaml.YAMLError):
        config = {}
    servers = config.get("mcp_servers") if isinstance(config, dict) else {}
    if not isinstance(servers, dict):
        return []
    result = []
    for name, value in servers.items():
        if not re.fullmatch(r"[a-zA-Z0-9][a-zA-Z0-9_.-]{0,63}", str(name)) or not isinstance(value, dict):
            continue
        command = str(value.get("command") or "")
        url = str(value.get("url") or value.get("endpoint") or "")
        env_values = value.get("env") if isinstance(value.get("env"), dict) else {}
        headers = value.get("headers") if isinstance(value.get("headers"), dict) else {}
        args = value.get("args", []) if isinstance(value.get("args"), list) else []
        result.append({"name": str(name), "transport": "stdio" if command else "http",
                       "command": Path(command).name if command else "", "args_count": len(args),
                       "endpoint_host": urllib.parse.urlsplit(url).hostname or "" if url else "",
                       "env_names": sorted(str(key) for key in env_values),
                       "header_names": sorted(str(key) for key in headers),
                       "enabled": bool(value.get("enabled", True))})
    return result


def mcp_catalog_for_profile(slug: str) -> list[dict]:
    result = run_profile_hermes(slug, ["mcp", "catalog"])
    if result.returncode:
        return []
    rows = []
    for line in result.stdout.splitlines():
        match = re.match(r"^\s*([a-zA-Z0-9][a-zA-Z0-9_.-]{0,63})\s+available\s{2,}(.*)$", line)
        if match:
            name, description = match.groups()
            rows.append({"name": name, "description": description.strip()})
    return rows


def extensions_for_profile(slug: str, platform: str = "cli") -> dict:
    safe_slug(slug)
    return {"profile": slug, "platform": platform,
            "plugins": plugin_list_for_profile(slug),
            "tools": tool_list_for_profile(slug, platform),
            "mcp_servers": mcp_servers_for_profile(slug),
            "mcp_catalog": mcp_catalog_for_profile(slug)}


def perform_extension_action(payload: dict) -> dict:
    slug = safe_slug(str(payload.get("profile", "")))
    kind = str(payload.get("kind", ""))
    action = str(payload.get("action", ""))
    if kind == "plugin":
        if action == "install":
            identifier = str(payload.get("identifier", "")).strip()
            if not identifier or len(identifier) > 300 or any(ord(c) < 32 for c in identifier):
                raise ValueError("Enter a GitHub owner/repository or plugin Git URL")
            args = ["plugins", "install", identifier, "--no-enable"]
            result = run_profile_hermes(slug, args, timeout=120)
        else:
            name = str(payload.get("name", "")).strip()
            if not re.fullmatch(r"[a-zA-Z0-9][a-zA-Z0-9_.-]{0,127}", name):
                raise ValueError("Invalid plugin name")
            plugins = plugin_list_for_profile(slug)
            item = next((plugin for plugin in plugins if plugin.get("name") == name), None)
            if not item:
                raise ValueError("Plugin is not installed for this profile")
            source = str(item.get("source", ""))
            if action == "toggle":
                enabled = bool(payload.get("enabled"))
                if enabled:
                    args = ["plugins", "enable", name,
                            "--allow-tool-override" if payload.get("allow_tool_override") else "--no-allow-tool-override"]
                else:
                    args = ["plugins", "disable", name]
            elif action == "update":
                if source not in {"git", "user"}:
                    raise ValueError("Only Git or user-installed plugins can be updated")
                args = ["plugins", "update", name]
            elif action == "remove":
                if source not in {"git", "user"}:
                    raise ValueError("Bundled plugins cannot be removed")
                args = ["plugins", "remove", name]
            else:
                raise ValueError("Unknown plugin action")
            result = run_profile_hermes(slug, args, timeout=120)
    elif kind == "tool":
        platform = str(payload.get("platform", "cli"))
        name = str(payload.get("name", "")).strip()
        if not re.fullmatch(r"[a-zA-Z0-9_.:-]{1,160}", name):
            raise ValueError("Invalid Hermes tool or toolset name")
        available = tool_list_for_profile(slug, platform)
        if not any(tool["name"] == name for tool in available):
            raise ValueError("This tool is not available for the selected platform")
        verb = "enable" if bool(payload.get("enabled")) else "disable"
        result = run_profile_hermes(slug, ["tools", verb, "--platform", platform, name])
    elif kind == "mcp":
        if action == "catalog":
            name = str(payload.get("name", "")).strip()
            entries = mcp_catalog_for_profile(slug)
            if not any(entry["name"] == name for entry in entries):
                raise ValueError("Choose an MCP app from the Hermes catalog")
            result = run_profile_hermes(slug, ["mcp", "install", name], timeout=120)
        elif action == "add":
            name = str(payload.get("name", "")).strip()
            if not re.fullmatch(r"[a-zA-Z0-9][a-zA-Z0-9_.-]{0,63}", name):
                raise ValueError("MCP app names may use letters, numbers, dots, underscores, and dashes")
            kind_value = str(payload.get("transport", "stdio"))
            auth = str(payload.get("auth", ""))
            if auth and auth not in {"oauth", "header"}:
                raise ValueError("Choose a supported MCP authentication method")
            if kind_value == "http":
                endpoint = str(payload.get("url", "")).strip()
                parsed = urllib.parse.urlsplit(endpoint)
                if not parsed.scheme in {"http", "https"} or not parsed.hostname or parsed.username or parsed.password or len(endpoint) > 2048:
                    raise ValueError("Enter a valid HTTP or HTTPS MCP endpoint without embedded credentials")
                api_key = str(payload.get("api_key", ""))
                if len(api_key) > 8192 or any(c in api_key for c in "\r\n"):
                    raise ValueError("MCP credentials must be 8,192 characters or fewer and contain no line breaks")
                if auth == "header" and not api_key:
                    raise ValueError("Paste a bearer token for header authentication")
                if (api_key or auth == "oauth") and parsed.scheme != "https" and parsed.hostname not in {"localhost", "127.0.0.1", "::1"}:
                    raise ValueError("Use HTTPS for remote MCP apps when sending a credential")
                if name in {server["name"] for server in mcp_servers_for_profile(slug)}:
                    raise ValueError("An MCP app with this name already exists; remove it before adding a replacement")
                # Hermes' CLI wizard requires an interactive terminal. Use its own
                # validated config/env helpers non-interactively instead.
                executable = shutil.which("hermes")
                if not executable:
                    raise RuntimeError("Hermes CLI is not available")
                python = Path(executable).resolve().with_name("python")
                if not python.exists():
                    raise RuntimeError("Could not find the Python environment used by Hermes")
                script = """import json, sys
from hermes_cli.mcp_config import _save_mcp_server, _env_key_for_server, _bearer_auth_headers, _strip_bearer_prefix
from hermes_cli.config import save_env_value
data = json.load(sys.stdin)
name = data['name']
config = {'url': data['url']}
if data.get('auth') == 'oauth':
    config['auth'] = 'oauth'
elif data.get('auth') == 'header':
    key = _env_key_for_server(name)
    save_env_value(key, _strip_bearer_prefix(data['api_key']))
    config['headers'] = _bearer_auth_headers(name)
ok = _save_mcp_server(name, config)
print(json.dumps({'ok': bool(ok)}))
"""
                env = os.environ.copy()
                env["HERMES_HOME"] = str(profile_hermes_home(slug))
                completed = subprocess.run([str(python), "-c", script], input=json.dumps({"name": name, "url": endpoint, "auth": auth, "api_key": api_key}),
                                           env=env, text=True, capture_output=True, timeout=25, check=False)
                if completed.returncode or not completed.stdout.strip().endswith('{"ok": true}'):
                    raise RuntimeError("Hermes could not save the MCP app configuration")
                return {"ok": True, "profile": slug, "message": "MCP app saved to this profile"}
            elif kind_value == "stdio":
                command = str(payload.get("command", "")).strip()
                if not command or len(command) > 256 or any(ord(c) < 32 for c in command):
                    raise ValueError("Enter a local MCP command")
                env_values = payload.get("env", {})
                if not isinstance(env_values, dict):
                    raise ValueError("MCP environment values must be an object")
                for key, value in env_values.items():
                    key = str(key).strip()
                    value = str(value)
                    if not re.fullmatch(r"[A-Z][A-Z0-9_]{0,63}", key) or len(value) > 8192 or any(c in value for c in "\r\n"):
                        raise ValueError("MCP environment names or values are invalid")
                arg_text = str(payload.get("args", ""))
                if len(arg_text) > 2048:
                    raise ValueError("MCP arguments are too long")
                try:
                    parsed_args = shlex.split(arg_text)
                except ValueError as exc:
                    raise ValueError("Check the quotes in the MCP arguments") from exc
                if any(any(ord(c) < 32 for c in item) for item in parsed_args):
                    raise ValueError("MCP arguments contain invalid characters")
                if name in {server["name"] for server in mcp_servers_for_profile(slug)}:
                    raise ValueError("An MCP app with this name already exists; remove it before adding a replacement")
                executable = shutil.which("hermes")
                if not executable:
                    raise RuntimeError("Hermes CLI is not available")
                python = Path(executable).resolve().with_name("python")
                script = """import json, sys
from hermes_cli.mcp_config import _save_mcp_server
data = json.load(sys.stdin)
config = {'command': data['command']}
if data.get('args'): config['args'] = data['args']
if data.get('env'): config['env'] = data['env']
print(json.dumps({'ok': bool(_save_mcp_server(data['name'], config))}))
"""
                env = os.environ.copy()
                env["HERMES_HOME"] = str(profile_hermes_home(slug))
                completed = subprocess.run([str(python), "-c", script], input=json.dumps({"name": name, "command": command, "args": parsed_args, "env": env_values}),
                                           env=env, text=True, capture_output=True, timeout=25, check=False)
                if completed.returncode or not completed.stdout.strip().endswith('{"ok": true}'):
                    raise RuntimeError("Hermes could not save the MCP app configuration")
                return {"ok": True, "profile": slug, "message": "MCP app saved to this profile"}
            else:
                raise ValueError("Choose HTTP or local stdio for the MCP app")
        elif action in {"remove", "test"}:
            name = str(payload.get("name", "")).strip()
            if not any(server["name"] == name for server in mcp_servers_for_profile(slug)):
                raise ValueError("MCP app is not configured for this profile")
            args = ["mcp", "remove" if action == "remove" else "test", name]
            result = run_profile_hermes(slug, args, timeout=90)
        else:
            raise ValueError("Unknown MCP app action")
    else:
        raise ValueError("Unknown extension action")

    if result.returncode:
        # Child output can contain provider URLs or command environment values.
        # Keep those details in Hermes' own logs rather than returning them here.
        raise RuntimeError("Hermes could not complete that extension action. Check its profile setup and logs.")
    return {"ok": True, "profile": slug, "message": "Hermes profile updated"}


def launch_hermes_terminal(payload: dict) -> dict:
    text = str(payload.get("prompt", "")).strip()
    if not text or len(text) > 20000:
        raise ValueError("Enter a prompt of up to 20,000 characters")
    source = safe_slug(str(payload.get("profile", "default")))
    if source in app_settings()["paused_profiles"]:
        raise ValueError("Resume the selected profile before launching it")
    provider = str(payload.get("provider", "")).strip()
    model = str(payload.get("model", "")).strip()
    if provider not in {entry["id"] for entry in installed_model_providers()}:
        raise ValueError("Choose a supported provider")
    if not model or model.startswith("-") or len(model) > 200 or any(c.isspace() for c in model):
        raise ValueError("Enter the exact model ID to launch")
    terminal = shutil.which("xdg-terminal-exec")
    if os.environ.get("HERMES_LW_TOKEN") or not (os.environ.get("WAYLAND_DISPLAY") or os.environ.get("DISPLAY")) or not terminal:
        raise ValueError("A local graphical session with xdg-terminal-exec is required. Open a terminal on the remote host for remote Hermes sessions.")
    subprocess.Popen([terminal, "--title=Hermes LW", "--", "hermes", "-p", source,
                      "--provider", provider, "--model", model, "-z", text],
                     cwd=str(HOME), start_new_session=True, stdin=subprocess.DEVNULL,
                     stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
    return {"ok": True, "message": f"Opened Hermes terminal · {source} · {provider}/{model}"}


class Handler(BaseHTTPRequestHandler):
    def log_message(self, *_):
        pass

    def request_is_local(self):
        host = (self.headers.get("Host") or "").lower()
        origin = self.headers.get("Origin")
        def loopback_authority(value: str) -> bool:
            try:
                parsed = urllib.parse.urlsplit("//" + value)
                return parsed.hostname in {"127.0.0.1", "localhost"} and (parsed.port is None or 1 <= parsed.port <= 65535)
            except ValueError:
                return False
        token = os.environ.get("HERMES_LW_TOKEN", "")
        supplied = self.headers.get("Authorization", "")
        authorized = not token or (supplied.startswith("Bearer ") and secrets.compare_digest(supplied[7:], token))
        valid_origins = origin in (None, "null", "file://") or bool(
            origin and origin.startswith("http://") and loopback_authority(origin[7:]))
        valid_host = loopback_authority(host)
        if token:
            try:
                parsed_host = urllib.parse.urlsplit("//" + host)
                valid_host = bool(parsed_host.hostname and not any(ch in host for ch in "\r\n /\\"))
            except ValueError:
                valid_host = False
        if not loopback_authority(host) and not token:
            self.send_json({"error": "Set HERMES_LW_TOKEN before serving Hermes LW through a remote HTTPS gateway"}, 403)
            return False
        opaque_cross_site = origin == "null" and self.headers.get("Sec-Fetch-Site", "").lower() == "cross-site" and not token
        if not valid_host or not valid_origins or opaque_cross_site or not authorized:
            if token and not authorized:
                self.send_json({"error": "Invalid Hermes LW gateway token"}, 401)
                return False
            self.send_json({"error": "Only the local Hermes LW app may use this API"}, 403)
            return False
        return True

    def send_json(self, data, status=200):
        body = json.dumps(data, ensure_ascii=False, allow_nan=False).encode("utf-8")
        try:
            self.send_response(status)
            self.send_header("Content-Type", "application/json; charset=utf-8")
            self.send_header("Cache-Control", "no-store")
            self.send_header("X-Content-Type-Options", "nosniff")
            self.send_header("Content-Length", str(len(body)))
            origin = self.headers.get("Origin")
            local_opaque_origin = origin == "null" and self.headers.get("Sec-Fetch-Site", "").lower() != "cross-site"
            if local_opaque_origin or origin == "file://" or (
                    origin and origin.startswith("http://") and any(host in origin for host in ("http://127.0.0.1", "http://localhost"))):
                self.send_header("Access-Control-Allow-Origin", origin)
                self.send_header("Vary", "Origin")
                self.send_header("Access-Control-Allow-Headers", "Content-Type")
                self.send_header("Access-Control-Allow-Methods", "GET, POST, OPTIONS")
            self.end_headers()
            self.wfile.write(body)
        except (BrokenPipeError, ConnectionResetError):
            pass

    def read_body(self):
        raw_length = self.headers.get("Content-Length", "0")
        if not raw_length.isdigit():
            raise ValueError("Invalid request length")
        length = int(raw_length)
        if length > MAX_REQUEST_BYTES:
            raise ValueError("Request is too large (maximum 1 MiB)")
        if length == 0:
            return {}
        try:
            payload = json.loads(self.rfile.read(length))
        except (json.JSONDecodeError, UnicodeDecodeError) as exc:
            raise ValueError("Request body must be valid JSON") from exc
        if not isinstance(payload, dict):
            raise ValueError("Request body must be a JSON object")
        return payload

    def do_OPTIONS(self):
        if not self.request_is_local(): return
        self.send_json({})

    def do_GET(self):
        if not self.request_is_local(): return
        try:
            route = urllib.parse.urlparse(self.path)
            if route.path == "/api/health":
                with ACTIVE_POSTS_LOCK:
                    busy = ACTIVE_POSTS
                self.send_json({"app": "hermes-lw", "pid": os.getpid(),
                                "backend_fingerprint": BACKEND_FINGERPRINT, "active_actions": busy})
            elif route.path == "/api/connections":
                self.send_json({"connections": [connection_status(row) for row in read_connections()]})
            elif route.path == "/api/state":
                query = urllib.parse.parse_qs(route.query)
                self.send_json(dashboard(str(query.get("board", [""])[0])))
            elif self.path == "/api/providers":
                self.send_json({"providers": installed_model_providers()})
            elif route.path == "/api/models":
                query = urllib.parse.parse_qs(route.query)
                provider = str(query.get("provider", ["openrouter"])[0]).strip().lower()
                slug = safe_slug(str(query.get("profile", ["default"])[0]))
                base_url = str(query.get("base_url", [""])[0])
                self.send_json(load_model_catalog(force=query.get("refresh") == ["1"], provider=provider,
                                                  slug=slug, base_url=base_url))
            elif route.path == "/api/extensions":
                query = urllib.parse.parse_qs(route.query)
                slug = safe_slug(str(query.get("profile", ["default"])[0]))
                platform = str(query.get("platform", ["cli"])[0])
                self.send_json(extensions_for_profile(slug, platform))
            elif route.path.startswith("/api/profile/"):
                slug = safe_slug(route.path.removeprefix("/api/profile/"))
                config_path, soul_path = profile_paths(slug)
                cfg = yaml.safe_load(config_path.read_text()) or {}
                self.send_json({"profile": slug, "config": strip_secrets(cfg),
                                "openrouter_key_configured": has_env_key(profile_env_path(slug)),
                                "configured_api_keys": credential_env_names(profile_env_path(slug)),
                                "custom_api_key_configured": bool((cfg.get("model") or {}).get("api_key"))})
            else:
                self.send_json({"error": "not found"}, 404)
        except ValueError as exc:
            self.send_json({"error": str(exc)}, 400)
        except Exception as exc:
            self.send_json({"error": str(exc)}, 500)

    def do_POST(self):
        global ACTIVE_POSTS
        # Serialize read/modify/write actions; long inference and proxy requests
        # remain independent so the dashboard and other connections stay usable.
        concurrent = {"/api/profile/generate", "/api/models/recommend", "/api/connections/request", "/api/connections/connect"}
        with ACTIVE_POSTS_LOCK:
            ACTIVE_POSTS += 1
        try:
            if self.path in concurrent:
                self.handle_post()
            else:
                with LOCK:
                    self.handle_post()
        finally:
            with ACTIVE_POSTS_LOCK:
                ACTIVE_POSTS -= 1

    def handle_post(self):
        if not self.request_is_local(): return
        try:
            payload = self.read_body()
            if self.path == "/api/connections/save":
                if payload.get("id"):
                    stop_tunnel(str(payload["id"]))
                item = save_connection(payload)
                self.send_json({"ok": True, "connection": connection_status(item)})
            elif self.path == "/api/connections/connect":
                self.send_json({"ok": True, "connection": connect_tunnel(str(payload.get("id", "")))})
            elif self.path == "/api/connections/disconnect":
                identifier = str(payload.get("id", ""))
                stop_tunnel(identifier)
                item = next((row for row in read_connections() if row.get("id") == identifier), None)
                self.send_json({"ok": True, "connection": connection_status(item) if item else None})
            elif self.path == "/api/connections/remove":
                identifier = str(payload.get("id", ""))
                stop_tunnel(identifier)
                items = [row for row in read_connections() if row.get("id") != identifier]
                save_connections(items)
                self.send_json({"ok": True, "connections": [connection_status(row) for row in items]})
            elif self.path == "/api/connections/request":
                data, status = request_remote_connection(payload)
                self.send_json(data, status)
            elif self.path == "/api/profile/save":
                self.save_profile(payload)
            elif self.path == "/api/profile/key":
                slug = safe_slug(str(payload.get("slug", "")))
                key_name = str(payload.get("key_name", "OPENROUTER_API_KEY")).strip().upper()
                provider = str(payload.get("provider", "openrouter")).strip().lower()
                value = str(payload.get("key", ""))
                if "\n" in value or "\r" in value:
                    raise ValueError("API keys cannot contain line breaks")
                if len(value) > 8192:
                    raise ValueError("API keys must be 8,192 characters or fewer")
                config_path, _ = profile_paths(slug)
                if provider == "custom":
                    cfg = yaml.safe_load(config_path.read_text()) or {}
                    model = cfg.setdefault("model", {})
                    if payload.get("clear"):
                        model.pop("api_key", None)
                    elif value:
                        model["api_key"] = value
                    else:
                        raise ValueError("Paste a key first")
                    write_profile_config(config_path, cfg)
                    configured = bool(model.get("api_key"))
                else:
                    allowed = credential_env_candidates(provider)
                    if key_name not in allowed:
                        raise ValueError(f"{provider} does not use {key_name}; choose a supported API-key provider")
                    env_path = profile_env_path(slug)
                    update_env_key(env_path, key_name, None if payload.get("clear") else value)
                    configured = key_name in credential_env_names(env_path)
                self.send_json({"ok": True, "configured": configured,
                                "configured_api_keys": credential_env_names(profile_env_path(slug))})
            elif self.path == "/api/extensions/action":
                self.send_json(perform_extension_action(payload))
            elif self.path == "/api/task/create":
                title = str(payload.get("title", "")).strip()
                if not title:
                    raise ValueError("Add a task title first")
                if len(title) > 200:
                    raise ValueError("Task titles must be 200 characters or fewer")
                if len(str(payload.get("body", ""))) > 20000:
                    raise ValueError("Task descriptions must be 20,000 characters or fewer")
                payload["due_date"] = iso_date(payload.get("due_date", ""))
                if "cost" in payload:
                    payload["cost"] = nonnegative_number(payload.get("cost", 0), "Cost estimate")
                payload["effort_hours"] = nonnegative_number(payload.get("effort_hours", 0), "Effort estimate")
                try:
                    runtime_seconds = int(payload.get("max_runtime_seconds", 0))
                except (TypeError, ValueError) as exc:
                    raise ValueError("Maximum runtime must be a whole number of seconds") from exc
                if runtime_seconds < 60 or runtime_seconds > 30 * 24 * 60 * 60:
                    raise ValueError("Choose a maximum runtime between 1 minute and 30 days")
                payload["max_runtime_seconds"] = runtime_seconds
                allowed = payload.get("allowed_profiles", [])
                if not isinstance(allowed, list): raise ValueError("Allowed profiles must be a list")
                known_profiles = set(profile_slugs())
                unknown_profiles = {str(slug) for slug in allowed if str(slug) not in known_profiles}
                if unknown_profiles:
                    raise ValueError("Choose profiles that still exist")
                payload["allowed_profiles"] = sorted({str(slug) for slug in allowed})
                if not payload["allowed_profiles"]: raise ValueError("Select at least one profile explicitly; no profile is enabled by default")
                paused_profiles = set(app_settings()["paused_profiles"])
                if set(payload["allowed_profiles"]) & paused_profiles: raise ValueError("Resume paused profiles before allowing them to work on a task")
                profile_budgets = payload.get("profile_budgets", {})
                if not isinstance(profile_budgets, dict): raise ValueError("Set a separate budget for each selected profile")
                clean_budgets = {}
                for slug in payload["allowed_profiles"]:
                    if slug not in profile_budgets: raise ValueError(f"Set a budget for selected profile {slug}")
                    cap = nonnegative_number(profile_budgets[slug], f"{slug} budget")
                    if cap <= 0: raise ValueError(f"{slug} budget must be greater than zero")
                    clean_budgets[slug] = cap
                payload["profile_budgets"] = clean_budgets
                assignee = str(payload.get("assignee", ""))
                if assignee and assignee not in payload["allowed_profiles"]:
                    raise ValueError("The assigned profile must be included in the allowed profile list")
                if assignee in app_settings()["paused_profiles"]:
                    raise ValueError("Resume this profile before assigning new work")
                board = safe_board(str(payload.get("board", app_settings().get("active_board", "default"))))
                args = ["kanban", "--board", board, "create", title, "--json"]
                for key, flag in (("body", "--body"), ("assignee", "--assignee"), ("workspace", "--workspace")):
                    if payload.get(key): args += [flag, str(payload[key])]
                priority = int(payload.get("priority", 0))
                if not 0 <= priority <= 4: raise ValueError("Priority must be between 0 and 4")
                args += ["--priority", str(priority)]
                args += ["--max-runtime", f"{runtime_seconds}s", "--max-retries", "1"]
                if not assignee:
                    # Hermes has no native per-task LW allowlist. Never let its
                    # dispatcher select a default worker for an unassigned card.
                    args += ["--initial-status", "blocked"]
                if payload.get("parent"): args += ["--parent", str(payload["parent"])]
                result = cmd(*args)
                created = json.loads(result) if result.startswith(("{", "[")) else {}
                task_id = str(created.get("id", ""))
                if task_id:
                    self.save_estimate(task_id, payload, board)
                self.send_json({"ok": True, "task": created})
            elif self.path == "/api/task/action":
                self.task_action(payload)
            elif self.path == "/api/task/detail":
                self.task_detail(payload)
            elif self.path == "/api/task/comment":
                self.task_comment(payload)
            elif self.path == "/api/task/link":
                self.task_link(payload)
            elif self.path == "/api/task/estimate":
                self.save_estimate(str(payload.get("id", "")), payload, safe_board(str(payload.get("board", app_settings().get("active_board", "default")))))
                self.send_json({"ok": True})
            elif self.path == "/api/project/create":
                self.create_project(payload)
            elif self.path == "/api/project/save":
                self.save_project(payload)
            elif self.path == "/api/project/select":
                settings = app_settings()
                slug = safe_board(str(payload.get("slug", "default")))
                if next((b for b in read_projects(settings) if b["slug"] == slug), {}).get("archived"):
                    raise ValueError("Restore this archived project before opening its board")
                settings["active_board"] = slug
                save_app_settings(settings)
                self.send_json({"ok": True, "board": settings["active_board"]})
            elif self.path == "/api/project/archive":
                self.archive_project(payload)
            elif self.path == "/api/project/export":
                self.export_project(payload)
            elif self.path == "/api/task/bulk":
                self.bulk_tasks(payload)
            elif self.path == "/api/views/save":
                self.save_view(payload)
            elif self.path == "/api/views/delete":
                self.delete_view(payload)
            elif self.path == "/api/templates/save":
                self.save_template(payload)
            elif self.path == "/api/templates/delete":
                self.delete_template(payload)
            elif self.path == "/api/profile/use":
                cmd("profile", "use", safe_slug(str(payload.get("profile", ""))))
                self.send_json({"ok": True})
            elif self.path == "/api/profile/create":
                self.create_profile(payload)
            elif self.path == "/api/profile/delete":
                self.delete_profile(payload)
            elif self.path == "/api/profile/manage":
                self.manage_profile(payload)
            elif self.path == "/api/profile/generate":
                self.generate_profile_prompt(payload)
            elif self.path == "/api/models/recommend":
                self.recommend_catalog_models(payload)
            elif self.path == "/api/favorite/model":
                self.favorite_model(payload)
            elif self.path == "/api/prompt/save":
                self.save_prompt(payload)
            elif self.path == "/api/prompt/delete":
                self.delete_prompt(payload)
            elif self.path == "/api/theme":
                settings = app_settings()
                settings["theme"] = "dark" if payload.get("theme") == "dark" else "light"
                save_app_settings(settings)
                self.send_json({"ok": True, "theme": settings["theme"]})
            elif self.path == "/api/hermes":
                self.send_json(launch_hermes_terminal(payload))
            else:
                self.send_json({"error": "not found"}, 404)
        except ValueError as exc:
            self.send_json({"error": str(exc)}, 400)
        except Exception as exc:
            self.send_json({"error": str(exc)}, 500)

    def save_profile(self, p):
        slug = safe_slug(str(p.get("slug", "")))
        config_path, soul_path = profile_paths(slug)
        cfg = yaml.safe_load(config_path.read_text()) or {}
        if isinstance(p.get("advanced"), dict):
            cfg = deep_merge(cfg, p["advanced"])
        model = cfg.setdefault("model", {})
        provider = str(p.get("provider", model.get("provider", "auto"))).strip().lower()
        providers = {entry["id"] for entry in installed_model_providers()}
        if provider not in providers:
            raise ValueError("Choose a provider supported by the installed Hermes version")
        base_url = str(p.get("base_url", "")).strip()
        if base_url and not re.match(r"^https?://", base_url, re.I):
            raise ValueError("Provider URL must start with http:// or https://")
        if len(base_url) > 2048 or any(char in base_url for char in "\r\n"):
            raise ValueError("Provider URL is too long or contains invalid characters")
        if base_url:
            parsed_url = urllib.parse.urlsplit(base_url)
            if not parsed_url.hostname or parsed_url.username or parsed_url.password or parsed_url.query or parsed_url.fragment:
                raise ValueError("Provider URL must have a host and cannot contain credentials, query parameters, or a fragment")
        if len(str(p.get("personality", ""))) > 50000:
            raise ValueError("Profile personality must be 50,000 characters or fewer")
        model["default"] = str(p.get("model", model.get("default", ""))).strip()
        model["provider"] = provider
        if provider == "custom":
            if base_url: model["base_url"] = base_url
            else: model.pop("base_url", None)
        else:
            # A custom endpoint must never leak into requests sent to a normal provider.
            model.pop("base_url", None)
        agent = cfg.setdefault("agent", {})
        agent["reasoning_effort"] = str(p.get("reasoning", agent.get("reasoning_effort", "medium")))
        backup = config_path.with_name("config.yaml.hermes-control-backup")
        if not backup.exists():
            atomic_write(backup, config_path.read_text())
        write_profile_config(config_path, cfg)
        atomic_write(soul_path, str(p.get("personality", "")))
        self.send_json({"ok": True})

    def create_profile(self, p):
        slug = str(p.get("slug", "")).strip().lower()
        if not re.fullmatch(r"[a-z0-9][a-z0-9-]{0,39}", slug):
            raise ValueError("Use lowercase letters, numbers, and hyphens for the profile ID")
        if slug == "default" or slug in profile_slugs():
            raise ValueError("That profile already exists or is reserved")
        mode = str(p.get("clone_mode", "empty"))
        description = str(p.get("description", "")).strip()
        soul = str(p.get("personality", ""))
        api_key = str(p.get("openrouter_api_key", ""))
        if "\n" in api_key or "\r" in api_key:
            raise ValueError("API keys cannot contain line breaks")
        if len(api_key) > 8192: raise ValueError("API keys must be 8,192 characters or fewer")
        if len(soul) > 50000: raise ValueError("Profile personality must be 50,000 characters or fewer")
        args = ["profile", "create", slug]
        if description:
            args += ["--description", description]
        if mode in ("clone", "clone_all"):
            source = safe_slug(str(p.get("source", "default")))
            args += ["--clone-from", source]
            if mode == "clone_all": args.append("--clone-all")
            cmd(*args, timeout=90)
            if not p.get("copy_api_key"):
                clear_profile_credentials(slug)
        elif mode == "empty":
            cmd(*args, timeout=90)
        else:
            raise ValueError("Choose an empty profile, a settings clone, or a full clone")
        if soul:
            atomic_write(profile_paths(slug)[1], soul)
        if api_key:
            update_env_key(profile_env_path(slug), "OPENROUTER_API_KEY", api_key)
        self.send_json({"ok": True, "profile": slug})

    def delete_profile(self, p):
        slug = safe_slug(str(p.get("slug", "")))
        if slug == "default":
            raise ValueError("The default profile cannot be deleted")
        try:
            active_output = cmd("profile", "list")
            active = re.search(r"^\s*◆\s*(\S+)", active_output, re.M)
            if active and active.group(1) == slug:
                cmd("profile", "use", "default")
        except Exception:
            pass
        cmd("profile", "delete", slug, "--yes", timeout=90)
        settings = app_settings()
        if settings["manager_profile"] == slug: settings["manager_profile"] = ""
        settings["paused_profiles"] = [x for x in settings["paused_profiles"] if x != slug]
        save_app_settings(settings)
        self.send_json({"ok": True, "profile": slug})

    def manage_profile(self, p):
        action = str(p.get("action", ""))
        settings = app_settings()
        slug = safe_slug(str(p.get("slug", "")))
        if action == "manager":
            if settings["manager_profile"] != slug and slug in settings["paused_profiles"]:
                raise ValueError("Resume this profile before setting it as manager")
            settings["manager_profile"] = slug if settings["manager_profile"] != slug else ""
        elif action == "pause":
            paused = set(settings["paused_profiles"])
            if slug in paused: paused.remove(slug)
            else: paused.add(slug)
            settings["paused_profiles"] = sorted(paused)
        else:
            raise ValueError("Unsupported profile control")
        save_app_settings(settings)
        self.send_json({"ok": True, "manager_profile": settings["manager_profile"],
                        "paused_profiles": settings["paused_profiles"]})

    def generate_profile_prompt(self, p):
        name = str(p.get("name", "")).strip().lower()
        role = str(p.get("role", "")).strip()
        if not re.fullmatch(r"[a-z0-9][a-z0-9-]{0,39}", name):
            raise ValueError("Use a profile ID with lowercase letters, numbers, and hyphens (up to 40 characters)")
        if name == "default" or name in profile_slugs():
            raise ValueError("Choose a new profile ID before generating its personality")
        if len(role) > 2000:
            raise ValueError("Keep the role description under 2,000 characters")
        source = safe_slug(str(p.get("generator_profile", "default")))
        if source not in profile_slugs():
            raise ValueError("Choose an existing profile to generate with")
        provider = str(p.get("provider", "")).strip().lower()
        model = str(p.get("model", "")).strip()
        providers = {entry["id"] for entry in installed_model_providers()}
        if provider not in providers:
            raise ValueError("Choose a supported provider for personality generation")
        if not model or len(model) > 200 or model.startswith("-") or any(char.isspace() or ord(char) < 32 for char in model):
            raise ValueError("Choose a valid model from the selected provider’s catalog")
        inferred_role = role or name.replace("-", " ")
        prompt = f"""Write the complete contents of a Hermes Agent SOUL.md file for a new profile.

The file is a durable working identity and instruction set, not a biography, job ad, or description of an imaginary person. Make it useful during real tasks. Infer a sensible specialty from the profile ID only when the role description does not add enough detail. Do not merely repeat the ID. Do not invent credentials, access, or experience. Do not mention these instructions or explain the file.

Return Markdown only, with these sections and no code fences:
# Role and purpose
# Core strengths
# How to work
# Communication
# Boundaries and quality bar

Write in direct second person, using concrete actions and decision rules. Keep it focused on stable behavior that applies across tasks. Include when to ask a clarifying question, how to handle uncertainty, how to verify important work, and what to report at completion. Avoid generic filler, contradictory traits, exaggerated claims, and task-specific instructions. Aim for 250–400 words.

Profile ID: {name}
Role and specialty requested by the user: {inferred_role}
"""
        # Root-level `-z` seeds an interactive chat. Use chat's one-shot query
        # mode so this request returns the generated file on stdout without a TTY.
        try:
            completed = run_isolated_generation(source, ["chat", "-q", prompt, "-Q", "--source", "tool",
                                                     "--provider", provider, "--model", model,
                                                     "--toolsets", "__hermes_lw_no_tools__", "--ignore-rules"], provider, model)
        except subprocess.TimeoutExpired as exc:
            raise RuntimeError("The selected profile’s Hermes model did not respond within 180 seconds. Check its provider, model, and network settings, then try again.") from exc
        if completed.returncode:
            detail = (completed.stderr or completed.stdout or "Hermes exited without an error message").strip()
            raise RuntimeError("Could not generate the personality: " + detail[-1200:])
        result = completed.stdout.strip()
        result = re.sub(r"^```(?:markdown|md)?\s*", "", result, flags=re.IGNORECASE)
        result = re.sub(r"\s*```$", "", result).strip()
        if result.lower().startswith("soul.md\n"):
            result = result.split("\n", 1)[1].strip()
        if len(result) > 50000:
            raise RuntimeError("Hermes returned an unusually long personality. Try again with a shorter role description.")
        word_count = len(re.findall(r"\b[\w'-]+\b", result))
        required_sections = ("Role and purpose", "Core strengths", "How to work", "Communication", "Boundaries and quality bar")
        sections_present = sum(bool(re.search(r"^#{1,6}\s+" + re.escape(section) + r"\s*$", result, re.I | re.M)) for section in required_sections)
        if word_count < 70 or sections_present < 4:
            raise RuntimeError("Hermes returned an incomplete or unstructured personality. Check the generator profile’s model and try again.")
        self.send_json({"ok": True, "personality": result, "generator_profile": source,
                        "provider": provider, "model": model})

    def recommend_catalog_models(self, p):
        question = str(p.get("question", "")).strip()
        if not question or len(question) > 2000:
            raise ValueError("Describe what you want the model to do (up to 2,000 characters)")
        source = safe_slug(str(p.get("profile", "default")))
        if source not in profile_slugs():
            raise ValueError("Choose an existing profile to supply provider credentials")
        provider = str(p.get("provider", "")).strip().lower()
        model = str(p.get("model", "")).strip()
        providers = {entry["id"] for entry in installed_model_providers()}
        if provider not in providers:
            raise ValueError("Choose a supported provider for the advisor model")
        if not model or len(model) > 200 or model.startswith("-") or any(char.isspace() or ord(char) < 32 for char in model):
            raise ValueError("Choose a valid advisor model from the catalog")
        catalog = load_model_catalog(provider=provider, slug=source)
        model_index = {row["id"]: row for row in catalog.get("models", [])}
        advisor = model_index.get(model)
        if not advisor or advisor.get("price_known") is not True:
            raise ValueError("Advisor request blocked: choose a model with published pricing")
        if "text" not in advisor.get("inputs", []) or "text" not in advisor.get("outputs", []):
            raise ValueError("Choose an advisor model that accepts and returns text")
        raw_candidates = p.get("candidates")
        if not isinstance(raw_candidates, list) or not raw_candidates:
            raise ValueError("Search or filter the catalog to at least one candidate model first")
        if len(raw_candidates) > 30:
            raise ValueError("The advisor can compare up to 30 matching models at a time; narrow the catalog search")
        candidates = []
        seen = set()
        for row in raw_candidates:
            if not isinstance(row, dict):
                continue
            model_id = str(row.get("id", "")).strip()
            if not model_id or len(model_id) > 200 or model_id in seen:
                continue
            if model_id not in model_index:
                raise ValueError("Catalog changed; refresh it before asking for recommendations")
            row = model_index[model_id]
            seen.add(model_id)
            candidates.append({
                "id": model_id,
                "name": str(row.get("name", model_id))[:120],
                "category": str(row.get("category", "Other"))[:40],
                "description": str(row.get("description", ""))[:180],
                "input_usd_per_million": max(0.0, _float(row.get("input_rate"))),
                "output_usd_per_million": max(0.0, _float(row.get("output_rate"))),
                "pricing_available": bool(row.get("price_known", False)),
                "context_tokens": max(0, int(_float(row.get("context_length")))),
                "input_modalities": [str(x)[:20] for x in row.get("inputs", [])[:8] if isinstance(x, str)],
                "output_modalities": [str(x)[:20] for x in row.get("outputs", [])[:8] if isinstance(x, str)],
                "supports_tools": "tools" in row.get("supported_parameters", []),
            })
        if not candidates:
            raise ValueError("No valid catalog models were supplied")
        candidate_json = json.dumps(candidates, ensure_ascii=False, separators=(",", ":"))
        prompt = f"""Help choose a model for this task using ONLY the supplied catalog candidates.

Task and constraints from the user:
{question}

The candidate list reflects the current provider and filters in Hermes LW. Do not invent model IDs or recommend anything outside the list. Weigh task fit, capabilities, context, and published cost. Pricing marked unavailable must be described as unknown, never assumed free. Return 1–3 distinct recommendations in ranked order, with concise reasons and trade-offs. Return valid JSON only in this shape: {{"recommendations":[{{"id":"exact candidate ID","reason":"why it fits","tradeoff":"what to consider"}}],"summary":"brief comparison"}}.

Candidates:
{candidate_json}
"""
        try:
            completed = run_isolated_generation(source, ["chat", "-q", prompt, "-Q", "--source", "tool",
                                                     "--provider", provider, "--model", model,
                                                     "--toolsets", "__hermes_lw_no_tools__", "--ignore-rules"], provider, model)
        except subprocess.TimeoutExpired as exc:
            raise RuntimeError("The advisor model did not respond within 180 seconds. Check provider and network settings.") from exc
        if completed.returncode:
            detail = (completed.stderr or completed.stdout or "Hermes exited without an error message").strip()
            raise RuntimeError("Could not get model recommendations: " + detail[-1000:])
        result = completed.stdout.strip()
        result = re.sub(r"^```(?:json)?\s*|\s*```$", "", result, flags=re.IGNORECASE).strip()
        try:
            answer = json.loads(result)
        except json.JSONDecodeError as exc:
            raise RuntimeError("The advisor model did not return valid recommendations. Try again or choose another model.") from exc
        allowed = {row["id"] for row in candidates}
        recommendations = []
        rows = answer.get("recommendations", []) if isinstance(answer, dict) else []
        if not isinstance(rows, list):
            raise RuntimeError("The advisor returned an invalid recommendation list")
        for row in rows:
            if not isinstance(row, dict) or row.get("id") not in allowed:
                continue
            if any(item["id"] == row["id"] for item in recommendations):
                continue
            recommendations.append({"id": row["id"],
                                    "reason": str(row.get("reason", ""))[:1000],
                                    "tradeoff": str(row.get("tradeoff", ""))[:1000]})
            if len(recommendations) == 3:
                break
        if not recommendations:
            raise RuntimeError("The advisor did not choose any of the visible catalog candidates. Try a narrower question or another advisor model.")
        self.send_json({"ok": True, "recommendations": recommendations,
                        "summary": str(answer.get("summary", ""))[:2000],
                        "advisor_profile": source, "provider": provider, "model": model,
                        "candidate_count": len(candidates)})

    def favorite_model(self, p):
        model_id = str(p.get("id", "")).strip()
        if not model_id: raise ValueError("Missing model ID")
        settings = app_settings()
        favorites = set(settings["favorite_models"])
        if p.get("favorite", True): favorites.add(model_id)
        else: favorites.discard(model_id)
        settings["favorite_models"] = sorted(favorites)
        save_app_settings(settings)
        self.send_json({"ok": True, "favorite_models": settings["favorite_models"]})

    def save_prompt(self, p):
        title, body = str(p.get("title", "")).strip(), str(p.get("body", "")).strip()
        if not title or not body: raise ValueError("Prompt name and prompt text are required")
        settings = app_settings()
        prompts = settings["prompts"]
        prompt_id = str(p.get("id", "")) or secrets.token_hex(6)
        existing = next((row for row in prompts if row.get("id") == prompt_id), None)
        item = {"id": prompt_id, "title": title, "body": body,
                "favorite": bool(p.get("favorite", existing.get("favorite", True) if existing else True))}
        settings["prompts"] = [item if row.get("id") == prompt_id else row for row in prompts]
        if existing is None: settings["prompts"].append(item)
        save_app_settings(settings)
        self.send_json({"ok": True, "prompt": item})

    def delete_prompt(self, p):
        prompt_id = str(p.get("id", ""))
        settings = app_settings()
        settings["prompts"] = [row for row in settings["prompts"] if row.get("id") != prompt_id]
        save_app_settings(settings)
        self.send_json({"ok": True})

    def save_estimate(self, task_id, p, board="default"):
        if not task_id: return
        estimates = read_estimates()
        key = f"{board}:{task_id}"
        current = estimates.get(key, estimates.get(task_id, {}) if board == "default" else {})
        record = dict(current)
        if "cost" in p: record["cost"] = nonnegative_number(p.get("cost", 0), "Cost estimate")
        if "note" in p: record["note"] = str(p.get("note", ""))
        if "due_date" in p: record["due_date"] = iso_date(p.get("due_date", ""))
        if "effort_hours" in p: record["effort_hours"] = nonnegative_number(p.get("effort_hours", 0), "Effort estimate")
        if "max_runtime_seconds" in p:
            try: runtime_seconds = int(p.get("max_runtime_seconds", 0))
            except (TypeError, ValueError) as exc: raise ValueError("Maximum runtime must be a whole number of seconds") from exc
            if runtime_seconds < 60 or runtime_seconds > 30 * 24 * 60 * 60: raise ValueError("Choose a maximum runtime between 1 minute and 30 days")
            record["max_runtime_seconds"] = runtime_seconds
        if "tags" in p:
            tags = p.get("tags", [])
            if isinstance(tags, str): tags = [tag.strip() for tag in tags.split(",")]
            if not isinstance(tags, list): raise ValueError("Tags must be a list or comma-separated text")
            record["tags"] = sorted({str(tag).strip()[:32] for tag in tags if str(tag).strip()})[:12]
        if "allowed_profiles" in p:
            allowed = p.get("allowed_profiles")
            if not isinstance(allowed, list): raise ValueError("Allowed profiles must be a list")
            known = set(profile_slugs())
            unknown = {str(slug) for slug in allowed if str(slug) not in known}
            if unknown: raise ValueError("Choose profiles that still exist")
            selected = sorted({str(slug) for slug in allowed})
            if not selected: raise ValueError("Select at least one eligible profile; tasks cannot be open to all profiles")
            if set(selected) & set(app_settings()["paused_profiles"]): raise ValueError("Resume paused profiles before allowing them to work on a task")
            detail = json.loads(cmd("kanban", "--board", board, "show", task_id, "--json"))
            task = detail.get("task", detail)
            assignee = task.get("assignee")
            if assignee and assignee != "none" and assignee not in selected:
                raise ValueError("Unassign or reassign the task before removing its assigned profile")
            record["allowed_profiles"] = selected
        if "profile_budgets" in p or "allowed_profiles" in p:
            budgets = p.get("profile_budgets", record.get("profile_budgets", {}))
            if not isinstance(budgets, dict): raise ValueError("Profile budgets must be a mapping")
            allowed = record.get("allowed_profiles", [])
            clean = {}
            for slug in allowed:
                if slug not in budgets: raise ValueError(f"Set a budget for selected profile {slug}")
                amount = nonnegative_number(budgets[slug], f"{slug} budget")
                if amount <= 0: raise ValueError(f"{slug} budget must be greater than zero")
                clean[slug] = amount
            record["profile_budgets"] = clean
        estimates[key] = record
        if board == "default": estimates.pop(task_id, None)
        save_estimates(estimates)

    def create_project(self, p):
        slug = str(p.get("slug", "")).strip().lower()
        if not re.fullmatch(r"[a-z0-9][a-z0-9-]{0,62}", slug): raise ValueError("Project ID must use lowercase letters, numbers, and hyphens")
        if slug in {project["slug"] for project in read_projects()}: raise ValueError("A project with that ID already exists")
        name = str(p.get("name", "")).strip() or slug.replace("-", " ").title()
        description = str(p.get("description", "")).strip()
        if len(name) > 120 or len(description) > 5000: raise ValueError("Project name or description is too long")
        due_date = iso_date(p.get("due_date", ""))
        budget = nonnegative_number(p.get("budget", 0), "Project budget")
        args = ["kanban", "boards", "create", slug, "--name", name]
        if description: args += ["--description", description]
        color = str(p.get("color", "#3584e4"))
        if not re.fullmatch(r"#[0-9A-Fa-f]{6}", color): color = "#3584e4"
        args += ["--color", color]
        cmd(*args)
        settings = app_settings()
        settings["active_board"] = slug
        settings["project_meta"][slug] = {"budget": budget,
            "due_date": due_date, "owner": str(p.get("owner", "")), "status": "active", "color": color}
        save_app_settings(settings)
        self.send_json({"ok": True, "slug": slug})

    def save_project(self, p):
        slug = safe_board(str(p.get("slug", "")))
        name = str(p.get("name", "")).strip()
        if len(name) > 120 or len(str(p.get("description", ""))) > 5000: raise ValueError("Project name or description is too long")
        settings = app_settings()
        meta = settings["project_meta"].setdefault(slug, {})
        due_date = iso_date(p.get("due_date", ""))
        budget = nonnegative_number(p.get("budget", 0), "Project budget")
        projects = read_projects(settings)
        current = next((project for project in projects if project["slug"] == slug), {})
        if name and name != current.get("name"):
            cmd("kanban", "boards", "rename", slug, name)
        color = str(p.get("color", current.get("color", "#3584e4")))
        if not re.fullmatch(r"#[0-9A-Fa-f]{6}", color): color = "#3584e4"
        meta.update({"budget": budget,
                     "due_date": due_date, "owner": str(p.get("owner", "")),
                     "description": str(p.get("description", "")), "name": name or current.get("name", slug),
                     "color": color})
        save_app_settings(settings)
        self.send_json({"ok": True})

    def archive_project(self, p):
        slug = safe_board(str(p.get("slug", "")))
        if slug == "default": raise ValueError("The default project cannot be archived")
        cmd("kanban", "boards", "rm", slug)
        settings = app_settings()
        settings["active_board"] = "default"
        save_app_settings(settings)
        self.send_json({"ok": True})

    def export_project(self, p):
        slug = safe_board(str(p.get("slug", app_settings().get("active_board", "default"))))
        state = dashboard(slug)
        out_dir = HOME / "Downloads"
        out_dir.mkdir(parents=True, exist_ok=True)
        path = out_dir / f"hermes-project-{slug}-{time.strftime('%Y%m%d-%H%M%S')}.json"
        atomic_write(path, json.dumps({"project": state["project"], "tasks": state["tasks"]}, indent=2, ensure_ascii=False))
        self.send_json({"ok": True, "path": str(path)})

    def bulk_tasks(self, p):
        board = safe_board(str(p.get("board", app_settings().get("active_board", "default"))))
        ids = list(dict.fromkeys(str(x) for x in p.get("ids", []) if re.fullmatch(r"t_[a-zA-Z0-9_-]+", str(x))))
        if not ids or len(ids) > 100: raise ValueError("Select between 1 and 100 tasks")
        action = str(p.get("action", ""))
        if action == "assign":
            assignee = str(p.get("assignee", "none"))
            if assignee != "none" and assignee in app_settings()["paused_profiles"]: raise ValueError("Resume this profile before assigning work")
            selected_tasks = {task.get("id"): task for task in dashboard(board)["tasks"] if task.get("id") in ids}
            if set(selected_tasks) != set(ids): raise ValueError("One or more selected tasks no longer exist")
            for task_id, task in selected_tasks.items():
                if assignee == "none":
                    if task.get("status") != "blocked":
                        raise ValueError("Block tasks before unassigning them so Hermes cannot choose a default worker")
                else:
                    if assignee not in task.get("allowed_profiles", []):
                        raise ValueError(f"Profile {assignee} is not allowed to work on task {task_id}")
            for tid in ids: cmd("kanban", "--board", board, "assign", tid, assignee)
        elif action in ("complete", "archive"):
            cmd("kanban", "--board", board, action, *ids)
        else: raise ValueError("Choose assign, complete, or archive for a bulk action")
        self.send_json({"ok": True, "count": len(ids)})

    def save_view(self, p):
        name = str(p.get("name", "")).strip()[:50]
        if not name: raise ValueError("Give this board view a name")
        item = {"id": secrets.token_hex(5), "name": name, "status": str(p.get("status", "all")),
                "assignee": str(p.get("assignee", "all")), "query": str(p.get("query", ""))[:120],
                "board": safe_board(str(p.get("board", "default")))}
        settings = app_settings()
        settings["saved_views"] = [v for v in settings["saved_views"] if v.get("name", "").lower() != name.lower()]
        settings["saved_views"].append(item)
        save_app_settings(settings)
        self.send_json({"ok": True, "views": settings["saved_views"]})

    def delete_view(self, p):
        settings = app_settings()
        settings["saved_views"] = [v for v in settings["saved_views"] if v.get("id") != str(p.get("id", ""))]
        save_app_settings(settings)
        self.send_json({"ok": True, "views": settings["saved_views"]})

    def save_template(self, p):
        title, body = str(p.get("title", "")).strip()[:80], str(p.get("body", "")).strip()[:5000]
        if not title: raise ValueError("Give the task template a name")
        settings = app_settings()
        template_id = str(p.get("id", "")) or secrets.token_hex(5)
        existed = any(t.get("id") == template_id for t in settings["task_templates"])
        item = {"id": template_id, "title": title, "body": body,
                "priority": max(0, min(4, int(p.get("priority", 0) or 0))),
                "workspace": str(p.get("workspace", "scratch"))}
        settings["task_templates"] = [item if t.get("id") == template_id else t for t in settings["task_templates"]]
        if not existed:
            settings["task_templates"].append(item)
        save_app_settings(settings)
        self.send_json({"ok": True, "templates": settings["task_templates"]})

    def delete_template(self, p):
        settings = app_settings()
        settings["task_templates"] = [t for t in settings["task_templates"] if t.get("id") != str(p.get("id", ""))]
        save_app_settings(settings)
        self.send_json({"ok": True, "templates": settings["task_templates"]})

    def task_action(self, p):
        tid, action = str(p.get("id", "")), str(p.get("action", ""))
        board = safe_board(str(p.get("board", app_settings().get("active_board", "default"))))
        if not tid: raise ValueError("Missing task id")
        if action == "assign":
            assignee = str(p.get("assignee") or "none")
            current = next((task for task in dashboard(board)["tasks"] if task.get("id") == tid), None)
            if not current: raise ValueError("Task not found")
            if assignee == "none" and current.get("status") != "blocked":
                raise ValueError("Block the task before unassigning it so Hermes cannot choose a default worker")
            if assignee in app_settings()["paused_profiles"] and (not current or current.get("assignee") != assignee):
                raise ValueError("Resume this profile before assigning new work")
            if assignee != "none" and assignee not in current.get("allowed_profiles", []):
                raise ValueError(f"Profile {assignee} is not allowed to work on this task")
            cmd("kanban", "--board", board, "assign", tid, assignee)
        elif action == "complete": cmd("kanban", "--board", board, "complete", tid)
        elif action == "block": cmd("kanban", "--board", board, "block", tid, str(p.get("reason", "Paused from Hermes Control")))
        elif action in ("unblock", "promote"):
            current = next((task for task in dashboard(board)["tasks"] if task.get("id") == tid), None)
            if not current: raise ValueError("Task not found")
            assignee = current.get("assignee")
            if not assignee or assignee not in current.get("allowed_profiles", []):
                raise ValueError("Assign this task to an explicitly approved profile before making it runnable")
            if assignee in app_settings()["paused_profiles"]:
                raise ValueError("Resume the assigned profile before making this task runnable")
            if float(current.get("profile_budgets", {}).get(assignee, 0)) <= 0:
                raise ValueError("Save a positive planning budget for the assigned profile first")
            if action == "unblock": cmd("kanban", "--board", board, "unblock", tid)
            else: cmd("kanban", "--board", board, "promote", tid, "Promoted from Hermes Control")
        elif action == "schedule": cmd("kanban", "--board", board, "schedule", tid, str(p.get("reason", "Scheduled from Hermes Control")))
        elif action == "archive": cmd("kanban", "--board", board, "archive", tid)
        elif action == "priority":
            priority = int(p.get("priority", 0))
            if not 0 <= priority <= 4:
                raise ValueError("Priority must be between 0 and 4")
            with LOCK:
                import sqlite3
                project = next(project for project in read_projects() if project["slug"] == board)
                con = sqlite3.connect(project.get("db_path") or HERMES / "kanban.db", timeout=3)
                try:
                    con.execute("UPDATE tasks SET priority=? WHERE id=?", (priority, tid))
                    if con.total_changes == 0: raise ValueError("Task not found")
                    con.commit()
                finally: con.close()
        else: raise ValueError("Unsupported task action")
        self.send_json({"ok": True})

    def task_detail(self, p):
        tid = str(p.get("id", "")).strip()
        board = safe_board(str(p.get("board", app_settings().get("active_board", "default"))))
        if not re.fullmatch(r"t_[a-zA-Z0-9_-]+", tid): raise ValueError("Invalid task ID")
        self.send_json(json.loads(cmd("kanban", "--board", board, "show", tid, "--json")))

    def task_comment(self, p):
        tid, body = str(p.get("id", "")).strip(), str(p.get("body", "")).strip()
        board = safe_board(str(p.get("board", app_settings().get("active_board", "default"))))
        if not re.fullmatch(r"t_[a-zA-Z0-9_-]+", tid): raise ValueError("Invalid task ID")
        if not body: raise ValueError("Write a comment first")
        if len(body) > 10000: raise ValueError("Comments must be 10,000 characters or fewer")
        author = str(p.get("author", "user")).strip()[:80] or "user"
        cmd("kanban", "--board", board, "comment", tid, body, "--author", author)
        self.task_detail({"id": tid, "board": board})

    def task_link(self, p):
        parent, child = str(p.get("parent_id", "")).strip(), str(p.get("child_id", "")).strip()
        board = safe_board(str(p.get("board", app_settings().get("active_board", "default"))))
        if not re.fullmatch(r"t_[a-zA-Z0-9_-]+", parent) or not re.fullmatch(r"t_[a-zA-Z0-9_-]+", child):
            raise ValueError("Choose two valid task IDs")
        if parent == child: raise ValueError("A task cannot depend on itself")
        cmd("kanban", "--board", board, "link", parent, child)
        self.send_json({"ok": True})


if __name__ == "__main__":
    server = ThreadingHTTPServer(("127.0.0.1", PORT), Handler)
    server.serve_forever()
