#!/usr/bin/env python3
"""Small local API for the Hermes LW Quickshell control desk."""
from __future__ import annotations

import copy
import json
import math
import os
import re
import secrets
import subprocess
import threading
import time
import urllib.error
import urllib.parse
import urllib.request
from datetime import date
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
from pathlib import Path

import yaml

HOME = Path.home()
HERMES = HOME / ".hermes"
PROFILES = HERMES / "profiles"
ESTIMATES = HOME / ".local/share/hermes-control/estimates.json"
APP_SETTINGS = HOME / ".local/share/hermes-control/settings.json"
MODEL_CACHE = HOME / ".cache/hermes-control/openrouter-models.json"
PORT = 18731
LOCK = threading.Lock()
MODEL_CACHE_SECONDS = 6 * 60 * 60


def cmd(*args: str, timeout: int = 12) -> str:
    p = subprocess.run(["hermes", *args], text=True, capture_output=True, timeout=timeout)
    if p.returncode:
        raise RuntimeError((p.stderr or p.stdout or "Hermes command failed").strip())
    return p.stdout.strip()


def profile_slugs() -> list[str]:
    return ["default"] + sorted(p.name for p in PROFILES.iterdir() if p.is_dir() and (p / "config.yaml").exists())


def profile_paths(slug: str) -> tuple[Path, Path]:
    if slug == "default":
        return HERMES / "config.yaml", HERMES / "SOUL.md"
    folder = PROFILES / slug
    return folder / "config.yaml", folder / "SOUL.md"


def profile_env_path(slug: str) -> Path:
    return (HERMES if slug == "default" else PROFILES / slug) / ".env"


def app_settings() -> dict:
    try:
        data = json.loads(APP_SETTINGS.read_text())
    except Exception:
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
    APP_SETTINGS.parent.mkdir(parents=True, exist_ok=True)
    tmp = APP_SETTINGS.with_suffix(".tmp")
    tmp.write_text(json.dumps(data, indent=2))
    os.chmod(tmp, 0o600)
    tmp.replace(APP_SETTINGS)


def update_env_key(path: Path, key_name: str, value: str | None) -> None:
    if "\n" in (value or "") or "\r" in (value or ""):
        raise ValueError("API keys cannot contain line breaks")
    path.parent.mkdir(parents=True, exist_ok=True)
    lines = path.read_text().splitlines() if path.exists() else []
    lines = [line for line in lines if not re.match(rf"^\s*(?:export\s+)?{re.escape(key_name)}\s*=", line)]
    if value:
        lines.append(f"{key_name}={value}")
    path.write_text("\n".join(lines) + ("\n" if lines else ""))
    os.chmod(path, 0o600)


def has_env_key(path: Path, key_name: str = "OPENROUTER_API_KEY") -> bool:
    if not path.exists():
        return False
    return any(re.match(rf"^\s*(?:export\s+)?{re.escape(key_name)}\s*=\s*\S+", line)
               for line in path.read_text().splitlines())


def configured_api_keys(path: Path) -> list[str]:
    if not path.exists():
        return []
    found = set()
    for line in path.read_text().splitlines():
        match = re.match(r"^\s*(?:export\s+)?([A-Z][A-Z0-9_]{0,63}_API_KEY)\s*=\s*\S+", line)
        if match:
            found.add(match.group(1))
    return sorted(found)


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
            "reasoning": str(agent.get("reasoning_effort", "medium")),
            "description": str(cfg.get("description", "")),
            "personality": soul.read_text() if soul.exists() else "",
            "active": slug == active,
            "manager": slug == settings["manager_profile"],
            "paused": slug in settings["paused_profiles"],
            "openrouter_key_configured": has_env_key(profile_env_path(slug)),
            "configured_api_keys": configured_api_keys(profile_env_path(slug)),
        })
    return result


def read_estimates() -> dict:
    try:
        return json.loads(ESTIMATES.read_text())
    except Exception:
        return {}


def save_estimates(data: dict) -> None:
    ESTIMATES.parent.mkdir(parents=True, exist_ok=True)
    tmp = ESTIMATES.with_suffix(".tmp")
    tmp.write_text(json.dumps(data, indent=2))
    tmp.replace(ESTIMATES)


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
    try:
        input_rate = float(pricing.get("prompt") or 0) * 1_000_000
    except (TypeError, ValueError):
        input_rate = 0.0
    try:
        output_rate = float(pricing.get("completion") or 0) * 1_000_000
    except (TypeError, ValueError):
        output_rate = 0.0
    try:
        image_rate = float(pricing.get("image") or 0)
    except (TypeError, ValueError):
        image_rate = 0.0
    arch = model.get("architecture") or {}
    return {
        "id": str(model.get("id", "")),
        "name": str(model.get("name") or model.get("id", "")),
        "description": str(model.get("description", "")),
        "category": model_category(model),
        "input_rate": input_rate,
        "output_rate": output_rate,
        "image_rate": image_rate,
        "request_rate": _float(pricing.get("request")),
        "inputs": arch.get("input_modalities") or [],
        "outputs": arch.get("output_modalities") or [],
        "context_length": int(model.get("context_length") or 0),
        "created": int(model.get("created") or 0),
    }


def _float(value) -> float:
    try:
        return float(value or 0)
    except (TypeError, ValueError):
        return 0.0


def load_model_catalog(force: bool = False) -> dict:
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
        models = [normalized_model(item) for item in payload.get("data", []) if item.get("id")]
        data = {"fetched_at": int(time.time()), "models": models}
        MODEL_CACHE.parent.mkdir(parents=True, exist_ok=True)
        tmp = MODEL_CACHE.with_suffix(".tmp")
        tmp.write_text(json.dumps(data))
        tmp.replace(MODEL_CACHE)
        return {"models": models, "fetched_at": data["fetched_at"], "source": "live", "stale": False}
    except (urllib.error.URLError, TimeoutError, OSError, ValueError) as exc:
        if cache.get("models"):
            return {"models": cache["models"], "fetched_at": cache.get("fetched_at", 0), "source": "cache", "stale": True, "error": str(exc)}
        raise RuntimeError(f"Could not load OpenRouter's model catalog: {exc}")


def read_projects(settings: dict | None = None) -> list[dict]:
    settings = settings or app_settings()
    try:
        projects = json.loads(cmd("kanban", "boards", "list", "--json", "--all"))
    except Exception:
        projects = [{"slug": "default", "name": "Default", "description": "", "total": 0, "counts": {}}]
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
    except Exception:
        tasks = []
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
        task["allow_all_profiles"] = "allowed_profiles" not in estimate
        task["allowed_profiles"] = estimate.get("allowed_profiles", [])
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


class Handler(BaseHTTPRequestHandler):
    def log_message(self, *_):
        pass

    def request_is_local(self):
        host = (self.headers.get("Host") or "").lower()
        origin = self.headers.get("Origin")
        valid_hosts = {f"127.0.0.1:{PORT}", f"localhost:{PORT}"}
        valid_origins = {None, "null", "file://", f"http://127.0.0.1:{PORT}", f"http://localhost:{PORT}"}
        opaque_cross_site = origin == "null" and self.headers.get("Sec-Fetch-Site", "").lower() == "cross-site"
        if host not in valid_hosts or origin not in valid_origins or opaque_cross_site:
            self.send_json({"error": "Only the local Hermes LW app may use this API"}, 403)
            return False
        return True

    def send_json(self, data, status=200):
        body = json.dumps(data).encode()
        self.send_response(status)
        self.send_header("Content-Type", "application/json; charset=utf-8")
        origin = self.headers.get("Origin")
        local_opaque_origin = origin == "null" and self.headers.get("Sec-Fetch-Site", "").lower() != "cross-site"
        if local_opaque_origin or origin in ("file://", f"http://127.0.0.1:{PORT}", f"http://localhost:{PORT}"):
            self.send_header("Access-Control-Allow-Origin", origin)
            self.send_header("Vary", "Origin")
            self.send_header("Access-Control-Allow-Headers", "Content-Type")
            self.send_header("Access-Control-Allow-Methods", "GET, POST, OPTIONS")
        self.end_headers()
        self.wfile.write(body)

    def read_body(self):
        return json.loads(self.rfile.read(int(self.headers.get("Content-Length", "0"))) or b"{}")

    def do_OPTIONS(self):
        if not self.request_is_local(): return
        self.send_json({})

    def do_GET(self):
        if not self.request_is_local(): return
        try:
            if self.path.startswith("/api/state"):
                query = urllib.parse.parse_qs(urllib.parse.urlparse(self.path).query)
                self.send_json(dashboard(str(query.get("board", [""])[0])))
            elif self.path.startswith("/api/models"):
                query = urllib.parse.parse_qs(urllib.parse.urlparse(self.path).query)
                self.send_json(load_model_catalog(force=query.get("refresh") == ["1"]))
            elif self.path.startswith("/api/profile/"):
                slug = safe_slug(self.path.split("/")[-1])
                config_path, soul_path = profile_paths(slug)
                cfg = yaml.safe_load(config_path.read_text()) or {}
                self.send_json({"profile": slug, "config": strip_secrets(cfg),
                                "openrouter_key_configured": has_env_key(profile_env_path(slug)),
                                "configured_api_keys": configured_api_keys(profile_env_path(slug))})
            else:
                self.send_json({"error": "not found"}, 404)
        except Exception as exc:
            self.send_json({"error": str(exc)}, 500)

    def do_POST(self):
        if not self.request_is_local(): return
        try:
            payload = self.read_body()
            if self.path == "/api/profile/save":
                self.save_profile(payload)
            elif self.path == "/api/profile/key":
                slug = safe_slug(str(payload.get("slug", "")))
                key_name = str(payload.get("key_name", "OPENROUTER_API_KEY")).strip().upper()
                if not re.fullmatch(r"[A-Z][A-Z0-9_]{0,63}_API_KEY", key_name):
                    raise ValueError("Key name must be a valid environment variable ending in _API_KEY")
                env_path = profile_env_path(slug)
                update_env_key(env_path, key_name, None if payload.get("clear") else str(payload.get("key", "")))
                self.send_json({"ok": True, "configured": has_env_key(env_path, key_name),
                                "configured_api_keys": configured_api_keys(env_path)})
            elif self.path == "/api/task/create":
                title = str(payload.get("title", "")).strip()
                if not title:
                    raise ValueError("Add a task title first")
                payload["due_date"] = iso_date(payload.get("due_date", ""))
                if "cost" in payload:
                    payload["cost"] = nonnegative_number(payload.get("cost", 0), "Cost estimate")
                payload["effort_hours"] = nonnegative_number(payload.get("effort_hours", 0), "Effort estimate")
                allowed = payload.get("allowed_profiles", [])
                if not isinstance(allowed, list): raise ValueError("Allowed profiles must be a list")
                known_profiles = set(profile_slugs())
                payload["allowed_profiles"] = sorted({str(slug) for slug in allowed if str(slug) in known_profiles})
                assignee = str(payload.get("assignee", ""))
                if assignee and assignee not in payload["allowed_profiles"]:
                    raise ValueError("The assigned profile must be included in the allowed profile list")
                if assignee in app_settings()["paused_profiles"]:
                    raise ValueError("Resume this profile before assigning new work")
                board = safe_board(str(payload.get("board", app_settings().get("active_board", "default"))))
                args = ["kanban", "--board", board, "create", title, "--json"]
                for key, flag in (("body", "--body"), ("assignee", "--assignee"), ("workspace", "--workspace")):
                    if payload.get(key): args += [flag, str(payload[key])]
                args += ["--priority", str(int(payload.get("priority", 0)))]
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
                text = str(payload.get("prompt", "")).strip()
                if not text: raise ValueError("Enter a prompt")
                settings = app_settings()
                manager = settings["manager_profile"]
                if manager and manager in settings["paused_profiles"]:
                    raise ValueError("The selected manager profile is paused. Resume it or choose another manager.")
                args = ["hermes"] + (["-p", manager] if manager else []) + ["-z", text]
                subprocess.Popen(args, cwd=str(HOME), start_new_session=True,
                                 stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
                self.send_json({"ok": True, "message": f"Hermes started{(' with ' + manager) if manager else ''}"})
            else:
                self.send_json({"error": "not found"}, 404)
        except Exception as exc:
            self.send_json({"error": str(exc)}, 400)

    def save_profile(self, p):
        slug = safe_slug(str(p.get("slug", "")))
        config_path, soul_path = profile_paths(slug)
        cfg = yaml.safe_load(config_path.read_text()) or {}
        if isinstance(p.get("advanced"), dict):
            cfg = deep_merge(cfg, p["advanced"])
        model = cfg.setdefault("model", {})
        model["default"] = str(p.get("model", model.get("default", ""))).strip()
        model["provider"] = str(p.get("provider", model.get("provider", "auto"))).strip()
        agent = cfg.setdefault("agent", {})
        agent["reasoning_effort"] = str(p.get("reasoning", agent.get("reasoning_effort", "medium")))
        backup = config_path.with_name("config.yaml.hermes-control-backup")
        if not backup.exists(): backup.write_text(config_path.read_text())
        temp = config_path.with_suffix(".yaml.tmp")
        temp.write_text(yaml.safe_dump(cfg, sort_keys=False, allow_unicode=True))
        temp.replace(config_path)
        soul_path.write_text(str(p.get("personality", "")))
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
        args = ["profile", "create", slug]
        if description:
            args += ["--description", description]
        if mode in ("clone", "clone_all"):
            source = safe_slug(str(p.get("source", "default")))
            args += ["--clone-from", source]
            if mode == "clone_all": args.append("--clone-all")
            cmd(*args, timeout=90)
            if not p.get("copy_api_key"):
                update_env_key(profile_env_path(slug), "OPENROUTER_API_KEY", None)
        elif mode == "empty":
            cmd(*args, timeout=90)
        else:
            raise ValueError("Choose an empty profile, a settings clone, or a full clone")
        if soul:
            profile_paths(slug)[1].write_text(soul)
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
        name = str(p.get("name", "")).strip()
        role = str(p.get("role", "")).strip()
        if not name: raise ValueError("Add a profile name first")
        source = safe_slug(str(p.get("generator_profile", "default")))
        prompt = ("Create a concise, high-quality SOUL.md personality file for a Hermes Agent profile. "
                  "Write only the file contents in Markdown, with no explanation and no code fence. "
                  "Include a clear role, strengths, working approach, communication style, and boundaries. "
                  "Keep it practical and specific, around 250-450 words.\n\n"
                  f"Profile name: {name}\nIntended role: {role or name}\n")
        result = cmd("-p", source, "-z", prompt, timeout=150)
        self.send_json({"ok": True, "personality": result})

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
        if "tags" in p:
            tags = p.get("tags", [])
            if isinstance(tags, str): tags = [tag.strip() for tag in tags.split(",")]
            record["tags"] = sorted({str(tag).strip()[:32] for tag in tags if str(tag).strip()})[:12]
        if "allowed_profiles" in p:
            allowed = p.get("allowed_profiles")
            if not isinstance(allowed, list): raise ValueError("Allowed profiles must be a list")
            known = set(profile_slugs())
            record["allowed_profiles"] = sorted({str(slug) for slug in allowed if str(slug) in known})
        estimates[key] = record
        if board == "default": estimates.pop(task_id, None)
        save_estimates(estimates)

    def create_project(self, p):
        slug = str(p.get("slug", "")).strip().lower()
        if not re.fullmatch(r"[a-z0-9][a-z0-9-]{0,62}", slug): raise ValueError("Project ID must use lowercase letters, numbers, and hyphens")
        if slug in {project["slug"] for project in read_projects()}: raise ValueError("A project with that ID already exists")
        name = str(p.get("name", "")).strip() or slug.replace("-", " ").title()
        description = str(p.get("description", "")).strip()
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
        path.write_text(json.dumps({"project": state["project"], "tasks": state["tasks"]}, indent=2, ensure_ascii=False))
        self.send_json({"ok": True, "path": str(path)})

    def bulk_tasks(self, p):
        board = safe_board(str(p.get("board", app_settings().get("active_board", "default"))))
        ids = list(dict.fromkeys(str(x) for x in p.get("ids", []) if re.fullmatch(r"t_[a-zA-Z0-9_-]+", str(x))))
        if not ids or len(ids) > 100: raise ValueError("Select between 1 and 100 tasks")
        action = str(p.get("action", ""))
        if action == "assign":
            assignee = str(p.get("assignee", "none"))
            if assignee in app_settings()["paused_profiles"]: raise ValueError("Resume this profile before assigning work")
            if assignee != "none":
                for task in dashboard(board)["tasks"]:
                    if task.get("id") in ids and not task.get("allow_all_profiles", True) and assignee not in task.get("allowed_profiles", []):
                        raise ValueError(f"Profile {assignee} is not allowed to work on task {task.get('id')}")
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
            if assignee in app_settings()["paused_profiles"] and (not current or current.get("assignee") != assignee):
                raise ValueError("Resume this profile before assigning new work")
            if assignee != "none" and current and not current.get("allow_all_profiles", True) and assignee not in current.get("allowed_profiles", []):
                raise ValueError(f"Profile {assignee} is not allowed to work on this task")
            cmd("kanban", "--board", board, "assign", tid, assignee)
        elif action == "complete": cmd("kanban", "--board", board, "complete", tid)
        elif action == "block": cmd("kanban", "--board", board, "block", tid, str(p.get("reason", "Paused from Hermes Control")))
        elif action == "unblock": cmd("kanban", "--board", board, "unblock", tid)
        elif action == "promote": cmd("kanban", "--board", board, "promote", tid, "Promoted from Hermes Control")
        elif action == "schedule": cmd("kanban", "--board", board, "schedule", tid, str(p.get("reason", "Scheduled from Hermes Control")))
        elif action == "archive": cmd("kanban", "--board", board, "archive", tid)
        elif action == "priority":
            with LOCK:
                import sqlite3
                project = next(project for project in read_projects() if project["slug"] == board)
                con = sqlite3.connect(project.get("db_path") or HERMES / "kanban.db", timeout=3)
                try:
                    con.execute("UPDATE tasks SET priority=? WHERE id=?", (int(p.get("priority", 0)), tid))
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
