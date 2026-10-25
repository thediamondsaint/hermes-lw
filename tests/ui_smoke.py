"""Click the real QML controls on workspace 4 using synthetic HTTP fixtures.

No real Hermes state, credentials, provider requests, or CLI operations are used.
Requires Quickshell and the QtTest QML module in the desktop session.
"""
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
import json
import os
from pathlib import Path
import shutil
import subprocess
import tempfile
import threading
import time
import urllib.parse

ROOT = Path(__file__).resolve().parents[1]
MODEL = {"id": "fixture/one", "name": "Fixture Text Model", "category": "Text & chat", "description": "Synthetic model", "input_rate": 1, "output_rate": 2, "price_known": True, "inputs": ["text"], "outputs": ["text"], "supported_parameters": ["tools"], "context_length": 128000, "max_completion_tokens": 4000}
PROFILE = {"slug": "default", "model": "fixture/one", "provider": "openrouter", "personality": "Synthetic test profile", "reasoning": "medium"}


class Fixture(BaseHTTPRequestHandler):
    def log_message(self, *args):
        pass

    def reply(self, value, status=200):
        body = json.dumps(value).encode()
        self.send_response(status)
        self.send_header("Content-Type", "application/json")
        self.send_header("Content-Length", str(len(body)))
        self.end_headers()
        self.wfile.write(body)

    def do_GET(self):
        route = urllib.parse.urlsplit(self.path)
        query = urllib.parse.parse_qs(route.query)
        if route.path == "/api/state":
            self.reply({"profiles": [PROFILE], "tasks": [], "projects": [{"slug": "default", "name": "Audit fixture", "total": 0}], "board": "default", "project": {"slug": "default", "name": "Audit fixture"}, "saved_views": [], "task_templates": [], "prompts": [], "manager_profile": "default", "favorites": {"models": []}, "theme": "dark"})
        elif route.path == "/api/providers":
            self.reply({"providers": [{"id": p, "label": p, "env_vars": []} for p in ("auto", "openrouter", "alternate")]})
        elif route.path == "/api/models":
            self.reply({"models": [MODEL], "provider": query.get("provider", ["openrouter"])[0], "source": "fixture"})
        elif route.path == "/api/connections":
            self.reply({"connections": []})
        else:
            self.reply({})

    def do_POST(self):
        payload = json.loads(self.rfile.read(int(self.headers.get("Content-Length", 0))) or b"{}")
        if self.path == "/api/profile/create":
            self.reply({"error": "Use a profile ID"}, 400)
        elif self.path == "/api/models/recommend":
            assert payload["model"] == "fixture/one"
            self.reply({"recommendations": [{"id": "fixture/one", "reason": "Synthetic recommendation", "tradeoff": "Synthetic limitation"}], "summary": "Fixture response", "candidate_count": 1, "provider": "openrouter", "model": "fixture/one"})
        else:
            self.reply({"ok": True})


QML_TESTS = '''
      TestCase {
        name: "HermesControls"
        when: win.visible
        function initTestCase() {
          wait(200)
          root.refresh(); root.loadModelProviders()
          tryVerify(function(){return root.profiles.length === 1 && root.modelProviders.length === 3}, 5000)
        }
        function init() {
          tryCompare(root, "pendingRequests", 0, 5000)
          root.showModels = false; root.showModelAdvisor = false; root.showCreateProfile = false
          root.showProviderManager = false; root.showHermes = false; root.notice = ""
          appViewport.contentX = 0; appViewport.contentY = 0
          catalogViewport.contentX = 0; catalogViewport.contentY = 0
        }
        function cleanup() { if (qtest_results.failed) console.error("UI_AUDIT_FAILURE", qtest_results.functionName) }
        function test_options_toolbar_click() {
          mouseClick(findChild(win.contentItem, "toolbarButton_5"))
          compare(root.page, "Options")
        }
        function test_narrow_tile_scroll_fallback() {
          compare(win.minimumSize.width, 480)
          verify(appViewport.contentWidth >= win.width)
          verify(appViewport.contentHeight >= win.height)
          var offset = Math.max(0, appViewport.contentWidth - appViewport.width)
          appViewport.contentX = offset
          wait(50)
          compare(appViewport.contentX, offset)
        }
        function test_catalog_refresh_preserves_provider() {
          root.openModelCatalog("alternate", "default", "")
          tryCompare(root, "modelCatalogLoading", false, 5000)
          catalogViewport.contentX = Math.max(0, catalogRefreshButton.mapToItem(catalogViewport.contentItem, 0, 0).x - 100)
          wait(50)
          mouseClick(catalogRefreshButton)
          tryCompare(root, "modelCatalogLoading", false, 5000)
          compare(root.modelCatalogProvider, "alternate")
        }
        function test_advisor_escape_keeps_catalog_open() {
          root.openModelCatalog("openrouter", "default", "")
          tryCompare(root, "modelCatalogLoading", false, 5000)
          root.openModelAdvisor(); root.closeTopDialog()
          compare(root.showModelAdvisor, false)
          compare(root.showModels, true)
        }
        function test_connection_switch_preserves_pending_generation() {
          var current = root.activeConnectionId
          root.generatingPersonality = true
          root.activateConnection("not-a-real-connection")
          compare(root.activeConnectionId, current)
          compare(root.generatingPersonality, true)
          verify(root.notice.indexOf("Wait for") === 0)
          root.generatingPersonality = false
        }
        function test_profile_scroll_and_visible_validation() {
          root.openCreateProfileDialog()
          tryCompare(root, "modelCatalogLoading", false, 5000)
          wait(100)
          verify(createProfileScroll.contentHeight > createProfileScroll.height)
          createProfileScroll.contentY = createProfileScroll.contentHeight - createProfileScroll.height
          wait(50)
          mouseClick(createProfileSubmit)
          tryCompare(root, "notice", "Use a profile ID", 5000)
          verify(notificationToast.visible)
          compare(notificationToast.z, 100)
          compare(root.creatingProfile, false)
        }
        function test_advisor_request_click() {
          root.openModelCatalog("openrouter", "default", "")
          tryCompare(root, "modelCatalogLoading", false, 5000)
          root.openModelAdvisor()
          modelAdvisorQuestionInput.text = "Choose a model to audit a Python repo"
          modelAdvisorScroll.contentY = Math.max(0, modelAdvisorAskButton.mapToItem(modelAdvisorForm, 0, 0).y - 100)
          wait(100)
          mouseClick(modelAdvisorAskButton)
          tryVerify(function(){return root.modelAdvisorRecommendations.length === 1}, 5000)
          compare(root.modelAdvisorLoading, false)
          compare(root.modelAdvisorRecommendations[0].id, "fixture/one")
        }
        function cleanupTestCase() { console.log("UI_AUDIT_RESULTS", qtest_results.passCount, qtest_results.failCount); Qt.quit() }
      }
'''


def main():
    server = ThreadingHTTPServer(("127.0.0.1", 0), Fixture)
    threading.Thread(target=server.serve_forever, daemon=True).start()
    rule_key = "hermes_lw_audit_" + str(os.getpid())
    lua_key = json.dumps(rule_key)
    subprocess.run(["hyprctl", "eval", f"_G[{lua_key}] = hl.window_rule({{name={lua_key}, match={{title='^Hermes LW audit fixture$'}}, workspace='4 silent', no_initial_focus=true}})"], check=True, capture_output=True)
    try:
        with tempfile.TemporaryDirectory(prefix="hermes-lw-ui-audit-") as folder:
            target = Path(folder)
            for name in ("HttpClient.qml", "XpTitleBar.qml"):
                shutil.copy2(ROOT / name, target / name)
            source = (ROOT / "Main.qml").read_text()
            source = source.replace("import Quickshell", "import Quickshell\nimport QtTest", 1)
            source = source.replace("http://127.0.0.1:18731", f"http://127.0.0.1:{server.server_port}")
            source = source.replace('title: "Hermes LW"', 'title: "Hermes LW audit fixture"')
            source = source.replace("implicitWidth: 1500", "implicitWidth: 1150").replace("implicitHeight: 960", "implicitHeight: 720")
            anchor = "      Rectangle {\n      width: appViewport.contentWidth; height: appViewport.contentHeight\n      color: root.bg"
            assert source.count(anchor) == 1
            source = source.replace(anchor, anchor + QML_TESTS, 1)
            (target / "Main.qml").write_text(source)
            child = subprocess.Popen(["qs", "-p", str(target / "Main.qml")], stdout=subprocess.PIPE, stderr=subprocess.PIPE, text=True)
            tiled = False
            deadline = time.monotonic() + 12
            while child.poll() is None and time.monotonic() < deadline:
                clients = json.loads(subprocess.check_output(["hyprctl", "clients", "-j"], text=True))
                window = next((c for c in clients if c.get("pid") == child.pid), None)
                if window and window.get("mapped", True) and not window.get("floating", True) and window.get("workspace", {}).get("id") == 4:
                    tiled = True
                    break
                time.sleep(0.05)
            try:
                stdout, stderr = child.communicate(timeout=45)
            except subprocess.TimeoutExpired as error:
                child.kill()
                stdout, stderr = child.communicate()
                print(stdout + stderr)
                raise
            output = stdout + stderr
            print(output)
            if child.returncode or "FAIL!" in output or "Failed to load" in output or "ReferenceError" in output:
                raise SystemExit(1)
            if not tiled:
                raise SystemExit("The audit fixture did not open as a normal tiled window")
            print("TILED_UI: floating=false workspace=4")
            marker = __import__("re").search(r"UI_AUDIT_RESULTS (\d+) (\d+)", output)
            if not marker or int(marker[2]) or int(marker[1]) < 8:
                raise SystemExit("UI control tests did not pass: " + (marker[0] if marker else "no completion marker"))
    finally:
        subprocess.run(["hyprctl", "eval", f"if _G[{lua_key}] then _G[{lua_key}]:set_enabled(false); _G[{lua_key}] = nil end"], capture_output=True)
        server.shutdown()
        server.server_close()


if __name__ == "__main__":
    main()
