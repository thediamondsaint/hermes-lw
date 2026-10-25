import concurrent.futures
import importlib.util
import json
import os
from pathlib import Path
import subprocess
import tempfile
import threading
import unittest
from unittest.mock import patch, MagicMock
import urllib.request

import yaml

ROOT = Path(__file__).resolve().parents[1]
spec = importlib.util.spec_from_file_location("hermes_lw_backend", ROOT / "backend.py")
backend = importlib.util.module_from_spec(spec)
spec.loader.exec_module(backend)


class BackendTests(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.addCleanup(self.temp.cleanup)
        self.home = Path(self.temp.name)
        self.hermes = self.home / ".hermes"
        self.hermes.mkdir()
        (self.hermes / "config.yaml").write_text(yaml.safe_dump({"model": {"provider": "openrouter", "default": "example/advisor"}, "fallback_providers": [{"provider": "other", "model": "other/model"}], "mcp_servers": {"private": {"command": "never-run"}}}))
        self.profiles = self.hermes / "profiles"
        self.settings = self.home / "settings.json"
        for name, value in {"HOME": self.home, "HERMES": self.hermes, "PROFILES": self.profiles,
                            "APP_SETTINGS": self.settings, "ESTIMATES": self.home / "estimates.json"}.items():
            p = patch.object(backend, name, value)
            p.start()
            self.addCleanup(p.stop)
        self.handler = object.__new__(backend.Handler)
        self.responses = []
        self.handler.send_json = lambda data, status=200: self.responses.append((status, data))
        self.providers = [{"id": "openrouter", "env_vars": ["OPENROUTER_API_KEY", "OPENROUTER_BASE_URL"]}]
        p = patch.object(backend, "installed_model_providers", return_value=self.providers)
        p.start()
        self.addCleanup(p.stop)

    def make_profile(self, slug="clone", env=True):
        folder = self.profiles / slug
        folder.mkdir(parents=True)
        (folder / "config.yaml").write_text(yaml.safe_dump({"model": {"default": "example/model", "api_key": "fake-secret", "base_url": "https://example.test/v1"}, "providers": {"example": {"api_key": "fake-nested", "base_url": "https://example.test/v1"}}}))
        if env:
            (folder / ".env").write_text("OPENROUTER_API_KEY=fake\nOPENROUTER_BASE_URL=https://example.test/v1\nAPP_TOKEN=fake-token\nSETTING=keep\n")
        (folder / "auth.json").write_text('{"fake":"credential"}')
        return folder

    def test_new_install_without_profiles_directory(self):
        self.assertEqual(backend.profile_slugs(), ["default"])

    def test_clone_removes_secrets_but_keeps_endpoints(self):
        folder = self.make_profile()
        backend.clear_profile_credentials("clone")
        env = (folder / ".env").read_text()
        self.assertNotIn("API_KEY", env)
        self.assertNotIn("APP_TOKEN", env)
        self.assertIn("OPENROUTER_BASE_URL", env)
        self.assertFalse((folder / "auth.json").exists())
        cfg = yaml.safe_load((folder / "config.yaml").read_text())
        self.assertNotIn("api_key", cfg["model"])
        self.assertNotIn("api_key", cfg["providers"]["example"])
        self.assertEqual(cfg["model"]["base_url"], "https://example.test/v1")

    def test_clone_scrubs_config_even_without_env_file(self):
        folder = self.make_profile(env=False)
        backend.clear_profile_credentials("clone")
        self.assertFalse((folder / "auth.json").exists())
        self.assertNotIn("api_key", yaml.safe_load((folder / "config.yaml").read_text())["model"])

    def test_wrong_shape_state_files_recover(self):
        self.settings.write_text("[]")
        backend.ESTIMATES.write_text("[]")
        self.assertEqual(backend.app_settings()["favorite_models"], [])
        self.assertEqual(backend.read_estimates(), {})

    def advisor_payload(self):
        return {"question": "Audit a Python repo", "profile": "default", "provider": "openrouter",
                "model": "example/advisor", "candidates": [{"id": "example/candidate", "input_rate": 999}]}

    def catalog(self, priced=True):
        return {"models": [{"id": "example/advisor", "price_known": priced, "inputs": ["text"], "outputs": ["text"]},
                           {"id": "example/candidate", "price_known": True, "input_rate": 1, "output_rate": 2, "inputs": ["text"], "outputs": ["text"]}]}

    def test_advisor_rejects_unknown_price_before_inference(self):
        with patch.object(backend, "load_model_catalog", return_value=self.catalog(False)), patch.object(backend, "run_profile_hermes") as run:
            with self.assertRaisesRegex(ValueError, "published pricing"):
                self.handler.recommend_catalog_models(self.advisor_payload())
            run.assert_not_called()

    def test_advisor_uses_server_metadata_and_validates_ids(self):
        answer = {"recommendations": [{"id": "not-in-catalog", "reason": "invented"}, {"id": "example/candidate", "reason": "fits", "tradeoff": "slower"}], "summary": "comparison"}
        with patch.object(backend, "load_model_catalog", return_value=self.catalog()), patch.object(backend, "run_profile_hermes", return_value=subprocess.CompletedProcess([], 0, json.dumps(answer), "")) as run:
            self.handler.recommend_catalog_models(self.advisor_payload())
        args = run.call_args.args[1]
        self.assertIn("--ignore-rules", args)
        self.assertEqual(args[args.index("--toolsets") + 1], "__hermes_lw_no_tools__")
        prompt = args[args.index("-q") + 1]
        self.assertIn('"input_usd_per_million":1.0', prompt)
        self.assertNotIn("999", prompt)
        self.assertEqual([r["id"] for r in self.responses[-1][1]["recommendations"]], ["example/candidate"])

    def test_advisor_rejects_forged_candidate(self):
        payload = self.advisor_payload()
        payload["candidates"] = [{"id": "forged"}]
        with patch.object(backend, "load_model_catalog", return_value=self.catalog()), patch.object(backend, "run_profile_hermes") as run:
            with self.assertRaisesRegex(ValueError, "Catalog changed"):
                self.handler.recommend_catalog_models(payload)
            run.assert_not_called()

    def test_generation_uses_temporary_config_without_fallbacks_or_tools(self):
        (self.hermes / ".env").write_text("OPENROUTER_API_KEY=fake-source-key\n")
        original = (self.hermes / "config.yaml").read_text()
        generated_homes = []
        def run(source, args, timeout, home_override):
            generated_homes.append(home_override)
            config = yaml.safe_load((home_override / "config.yaml").read_text())
            self.assertEqual(config["fallback_providers"], [])
            self.assertIsNone(config["fallback_model"])
            self.assertEqual(config["mcp_servers"], {})
            self.assertEqual(config["model"]["default"], "example/selected")
            self.assertEqual((home_override / ".env").read_text(), "OPENROUTER_API_KEY=fake-source-key\n")
            self.assertEqual((home_override / ".env").stat().st_mode & 0o777, 0o600)
            return subprocess.CompletedProcess(args, 0, "answer", "")
        with patch.object(backend, "check_generation_budget"), patch.object(backend, "run_profile_hermes", side_effect=run):
            backend.run_isolated_generation("default", ["chat"], "openrouter", "example/selected")
        self.assertFalse(generated_homes[0].exists())
        self.assertEqual((self.hermes / "config.yaml").read_text(), original)

    def test_exhausted_openrouter_budget_blocks_inference(self):
        (self.hermes / ".env").write_text("OPENROUTER_API_KEY=fake-test-only\n")
        response = MagicMock()
        response.__enter__.return_value.read.return_value = b'{"data":{"limit_remaining":0}}'
        with patch.object(backend.urllib.request, "urlopen", return_value=response) as status, patch.object(backend, "run_profile_hermes") as run:
            with self.assertRaisesRegex(ValueError, "spending limit"):
                backend.run_isolated_generation("default", ["chat"], "openrouter", "example/model")
        self.assertEqual(status.call_args.args[0].get_method(), "GET")
        self.assertEqual(status.call_args.args[0].full_url, "https://openrouter.ai/api/v1/key")
        run.assert_not_called()

    def test_openrouter_preflight_does_not_use_inherited_keys(self):
        with patch.dict(os.environ, {"OPENROUTER_API_KEY": "wrong-desktop-key"}), patch.object(backend.urllib.request, "urlopen") as request:
            backend.check_generation_budget("default", "openrouter")
        request.assert_not_called()

    def test_openrouter_preflight_defers_to_separately_configured_pool(self):
        (self.hermes / ".env").write_text("OPENROUTER_API_KEY=fake-test-only\n")
        (self.hermes / "auth.json").write_text(json.dumps({"credential_pool": {"openrouter": [{"source": "manual"}]}}))
        with patch.object(backend.urllib.request, "urlopen") as request:
            backend.check_generation_budget("default", "openrouter")
        request.assert_not_called()

    def test_openrouter_budget_accepts_positive_and_unlimited_limits(self):
        (self.hermes / ".env").write_text("OPENROUTER_API_KEY=fake-test-only\n")
        for remaining in (10, None):
            response = MagicMock()
            response.__enter__.return_value.read.return_value = json.dumps({"data": {"limit_remaining": remaining}}).encode()
            with patch.object(backend.urllib.request, "urlopen", return_value=response):
                backend.check_generation_budget("default", "openrouter")

    def test_generation_rejects_automatic_provider_before_launch(self):
        with patch.object(backend, "run_profile_hermes") as run:
            with self.assertRaisesRegex(ValueError, "explicit provider"):
                backend.run_isolated_generation("default", ["chat"], "auto", "model")
            run.assert_not_called()

    def test_personality_keeps_useful_draft_without_exact_headings(self):
        draft = "# Role and purpose\n" + ("Review code carefully and verify each finding with concrete evidence. " * 12)
        response = "Warning: Unknown toolsets: internal\n" + draft
        with patch.object(backend, "run_isolated_generation", return_value=subprocess.CompletedProcess([], 0, response, "session_id: test")) as run:
            self.handler.generate_profile_prompt({"name": "reviewer", "generator_profile": "default", "provider": "openrouter", "model": "example/selected"})
        self.assertEqual(self.responses[-1][1]["personality"], draft.strip())
        self.assertIn("--cli", run.call_args.args[1])

    def test_personality_reports_provider_error_instead_of_session_metadata(self):
        response = subprocess.CompletedProcess([], 1, "Provider rejected the model: model not found", "\nsession_id: example\n")
        with patch.object(backend, "run_isolated_generation", return_value=response):
            with self.assertRaisesRegex(RuntimeError, "Provider rejected the model") as error:
                self.handler.generate_profile_prompt({"name": "reviewer", "generator_profile": "default", "provider": "openrouter", "model": "example/selected"})
        self.assertNotIn("session_id", str(error.exception))

    def test_personality_can_be_generated_for_existing_profile(self):
        draft = "# Role and purpose\n" + "Review code with evidence and verify important findings carefully. " * 10
        with patch.object(backend, "run_isolated_generation", return_value=subprocess.CompletedProcess([], 0, draft, "")):
            self.handler.generate_profile_prompt({"name": "default", "generator_profile": "default", "provider": "openrouter", "model": "example/model"})
        self.assertEqual(self.responses[-1][1]["personality"], draft.strip())

    def test_scanner_warning_does_not_masquerade_as_generation_error(self):
        result = subprocess.CompletedProcess([], 1, "Warning: Unknown toolsets: __hermes_lw_no_tools__\n⚠ tirith security scanner enabled but not available — command scanning will use pattern matching only", "session_id: example")
        with patch.object(backend, "run_isolated_generation", return_value=result):
            with self.assertRaisesRegex(RuntimeError, "Hermes returned no answer") as error:
                self.handler.generate_profile_prompt({"name": "reviewer", "provider": "openrouter", "model": "example/model"})
        self.assertNotIn("tirith", str(error.exception))

    def test_create_persists_selected_model_and_provider(self):
        def create(*args, **kwargs):
            self.make_profile("reviewer")
        with patch.object(backend, "cmd", side_effect=create):
            self.handler.create_profile({"slug": "reviewer", "clone_mode": "clone", "copy_api_key": False, "source": "default", "provider": "openrouter", "model": "example/chosen"})
        config = yaml.safe_load((self.profiles / "reviewer" / "config.yaml").read_text())
        self.assertEqual(config["model"], {"provider": "openrouter", "default": "example/chosen"})
        self.assertEqual(self.responses[-1][1]["profile"], "reviewer")

    def test_create_defaults_to_full_default_clone_with_keys(self):
        with patch.object(backend, "cmd") as command, patch.object(backend, "clear_profile_credentials") as scrub:
            self.handler.create_profile({"slug": "reviewer"})
        command.assert_called_once_with("profile", "create", "reviewer", "--clone-from", "default", "--clone-all", timeout=90)
        scrub.assert_not_called()

    def test_create_can_explicitly_omit_cloned_keys(self):
        with patch.object(backend, "cmd"), patch.object(backend, "clear_profile_credentials") as scrub:
            self.handler.create_profile({"slug": "reviewer", "copy_api_key": False})
        scrub.assert_called_once_with("reviewer")

    def test_invalid_profile_model_rejected_before_clone(self):
        with patch.object(backend, "cmd") as run:
            with self.assertRaisesRegex(ValueError, "valid model"):
                self.handler.create_profile({"slug": "reviewer", "provider": "openrouter", "model": "--bad"})
            run.assert_not_called()

    def test_cannot_remove_assigned_profile_from_allowlist(self):
        self.make_profile("worker")
        with patch.object(backend, "cmd", return_value=json.dumps({"task": {"assignee": "worker"}})):
            with self.assertRaisesRegex(ValueError, "Unassign or reassign"):
                self.handler.save_estimate("t_example", {"allowed_profiles": ["default"], "profile_budgets": {"default": 1}}, "default")
        self.assertEqual(backend.read_estimates(), {})

    def test_new_allowlist_requires_matching_budgets(self):
        with patch.object(backend, "cmd", return_value=json.dumps({"task": {"assignee": None}})):
            with self.assertRaisesRegex(ValueError, "budget"):
                self.handler.save_estimate("t_example", {"allowed_profiles": ["default"]}, "default")
        self.assertEqual(backend.read_estimates(), {})

    def test_priority_rejects_out_of_range_before_database_access(self):
        with patch.object(backend, "safe_board", return_value="default"), self.assertRaisesRegex(ValueError, "Priority"):
            self.handler.task_action({"id": "t_example", "action": "priority", "priority": 99})

    def test_unassigned_task_creation_starts_blocked(self):
        self.handler.path = "/api/task/create"
        self.handler.request_is_local = lambda: True
        self.handler.read_body = lambda: {"title": "Isolated test", "max_runtime_seconds": 60,
                                         "allowed_profiles": ["default"], "profile_budgets": {"default": 1}}
        def command(*args, **kwargs):
            return json.dumps({"id": "t_example"}) if "create" in args else json.dumps({"task": {"assignee": None}})
        with patch.object(backend, "safe_board", return_value="default"), patch.object(backend, "cmd", side_effect=command) as run:
            self.handler.handle_post()
        self.assertEqual(self.responses[-1][0], 200)
        args = run.call_args_list[0].args
        self.assertEqual(args[args.index("--initial-status") + 1], "blocked")
        self.assertEqual(args[args.index("--max-retries") + 1], "1")

    def test_runnable_actions_reject_unapproved_or_unassigned_worker(self):
        for assignee in (None, "other"):
            with self.subTest(assignee=assignee), patch.object(backend, "safe_board", return_value="default"), patch.object(backend, "dashboard", return_value={"tasks": [{"id": "t_example", "assignee": assignee, "allowed_profiles": ["default"]}]}), patch.object(backend, "cmd") as run:
                with self.assertRaisesRegex(ValueError, "explicitly approved"):
                    self.handler.task_action({"id": "t_example", "action": "promote"})
                run.assert_not_called()

    def test_unassigning_runnable_task_is_rejected(self):
        with patch.object(backend, "safe_board", return_value="default"), patch.object(backend, "dashboard", return_value={"tasks": [{"id": "t_example", "assignee": "default", "status": "ready", "allowed_profiles": ["default"]}]}), patch.object(backend, "cmd") as run:
            with self.assertRaisesRegex(ValueError, "Block the task"):
                self.handler.task_action({"id": "t_example", "action": "assign", "assignee": "none"})
            run.assert_not_called()

    def test_approved_budgeted_worker_can_be_unblocked(self):
        task = {"id": "t_example", "assignee": "default", "allowed_profiles": ["default"], "profile_budgets": {"default": 1}}
        with patch.object(backend, "safe_board", return_value="default"), patch.object(backend, "dashboard", return_value={"tasks": [task]}), patch.object(backend, "cmd") as run:
            self.handler.task_action({"id": "t_example", "action": "unblock"})
            run.assert_called_once_with("kanban", "--board", "default", "unblock", "t_example")

    def test_terminal_launch_has_visible_terminal_and_exact_arguments(self):
        text = "literal $(must-not-run) `also-literal`"
        with patch.dict(os.environ, {"WAYLAND_DISPLAY": "test-display", "HERMES_LW_TOKEN": ""}), patch.object(backend.shutil, "which", return_value="/usr/bin/xdg-terminal-exec"), patch.object(backend.subprocess, "Popen") as spawn:
            backend.launch_hermes_terminal({"prompt": text, "profile": "default", "provider": "openrouter", "model": "example/model"})
        argv = spawn.call_args.args[0]
        self.assertEqual(argv[0], "/usr/bin/xdg-terminal-exec")
        self.assertEqual(argv[-1], text)
        self.assertEqual(argv[argv.index("--model") + 1], "example/model")

    def test_concurrent_favorites_do_not_lose_updates(self):
        server = backend.ThreadingHTTPServer(("127.0.0.1", 0), backend.Handler)
        thread = threading.Thread(target=server.serve_forever, daemon=True)
        thread.start()
        try:
            def add(index):
                req = urllib.request.Request(f"http://127.0.0.1:{server.server_port}/api/favorite/model", data=json.dumps({"id": f"model-{index}"}).encode(), headers={"Content-Type": "application/json"})
                with urllib.request.urlopen(req, timeout=5) as response:
                    self.assertEqual(response.status, 200)
            with concurrent.futures.ThreadPoolExecutor(max_workers=6) as pool:
                list(pool.map(add, range(12)))
            self.assertEqual(len(backend.app_settings()["favorite_models"]), 12)
        finally:
            server.shutdown()
            server.server_close()


if __name__ == "__main__":
    unittest.main()
