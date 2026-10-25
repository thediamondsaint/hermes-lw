"""Verify desktop-4 tiling, then click rendered native controls in Xvfb.

Uses a fake backend, fake keys and synthetic data. --capture writes screenshots.
No real profiles, providers, remote hosts, or Hermes CLI actions are used.
"""
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
import json
import sys
import os
from pathlib import Path
import shutil
import subprocess
import tempfile
import threading
import time
import urllib.parse

ROOT = Path(__file__).resolve().parents[1]
MODELS = [dict(id="fixture/one", name="Affordable text", category="Text & chat", input_rate=1, output_rate=2, price_known=True, inputs=["text"], outputs=["text"], context_length=128000), dict(id="fixture/two", name="Code reviewer", category="Coding", input_rate=3, output_rate=4, price_known=True, inputs=["text"], outputs=["text"], context_length=200000)]
PROFILES = [dict(slug=slug, model="fixture/one", provider="openrouter", personality="Audit code carefully.", reasoning="medium", paused=slug == "paused", configured_api_keys=["OPENROUTER_API_KEY"]) for slug in ("default", "worker", "paused")]
TASKS = [dict(id="t_fixture", title="Audit a repository", status="blocked", assignee="", allowed_profiles=["worker"], profile_budgets={"worker": 2}, estimated_cost=1.5, priority=2, body="Check correctness", tags=[])]
CALLS = []
COMMENTS = []


def state():
    return dict(profiles=PROFILES, tasks=TASKS, projects=[dict(slug="default", name="Fixture project")], board="default", project=dict(slug="default", name="Fixture project"), saved_views=[], task_templates=[], prompts=[], manager_profile="default", favorites=dict(models=[]), theme="dark")


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
        if route.path == "/api/_capture":
            name = query.get("name", [""])[0]
            if name not in ("profile-form", "provider-form", "task-form"):
                self.reply(dict(error="Invalid fixture capture name"), 400)
                return
            values = [int(query.get(key, ["0"])[0]) for key in ("width", "height", "x", "y")]
            width, height, x, y = values
            subprocess.run(["import", "-window", "root", "-crop", f"{width}x{height}+{x}+{y}", f"/tmp/hermes-rebuilt-{name}.png"], check=True, timeout=10)
            self.reply(dict(ok=True))
        elif route.path == "/api/state":
            self.reply(state())
        elif route.path == "/api/providers":
            self.reply(dict(providers=[dict(id=p, label=p, env_vars=["OPENROUTER_API_KEY"] if p == "openrouter" else []) for p in ("auto", "openrouter", "alternate", "custom")]))
        elif route.path == "/api/models":
            self.reply(dict(models=MODELS, provider=query.get("provider", ["openrouter"])[0], source="fixture"))
        elif route.path == "/api/connections":
            self.reply(dict(connections=[dict(id="remote", name="Fixture cloud", kind="https", url="https://fixture.invalid"), dict(id="ssh", name="Fixture SSH", kind="ssh", host="fixture", connected=False)]))
        elif route.path == "/api/extensions":
            self.reply(dict(plugins=[], tools=[], mcp_servers=[], mcp_catalog=[]))
        else:
            self.reply({"error": "Unexpected GET fixture route"}, 404)

    def do_POST(self):
        payload = json.loads(self.rfile.read(int(self.headers.get("Content-Length", 0))) or b"{}")
        CALLS.append((self.path, payload))
        if self.path == "/api/profile/create":
            assert payload["clone_mode"] == "clone_all" and payload["copy_api_key"] is True and payload["source"] == "default"
            PROFILES.append(dict(PROFILES[0], slug=payload["slug"], model=payload["model"]))
            self.reply(dict(profile=payload["slug"]))
        elif self.path == "/api/profile/generate":
            assert payload["provider"] == "openrouter" and payload["model"] == "fixture/one"
            if payload["name"] == "error-case":
                self.reply(dict(error="The OpenRouter key has reached its spending limit."), 400)
            else:
                self.reply(dict(personality="# Role and purpose\nReview code and verify findings carefully."))
        elif self.path == "/api/profile/save":
            for item in PROFILES:
                if item["slug"] == payload["slug"]:
                    item.update({k: v for k, v in payload.items() if k in ("model", "provider", "personality", "reasoning", "base_url")})
            self.reply(dict(ok=True))
        elif self.path == "/api/profile/key":
            assert payload["key"] == "fake-ui-test-only" and payload["key_name"] == "OPENROUTER_API_KEY"
            self.reply(dict(ok=True))
        elif self.path == "/api/task/create":
            assert payload["allowed_profiles"] == ["worker"] and payload["profile_budgets"]["worker"] == 2
            assert payload["assignee"] == "" and payload["max_runtime_seconds"] >= 60
            self.reply(dict(task=dict(id="t_created")))
        elif self.path == "/api/task/detail":
            self.reply(dict(task=TASKS[0], comments=COMMENTS))
        elif self.path == "/api/task/comment":
            assert payload["id"] == "t_fixture" and payload["body"] == "Verified the finding"
            COMMENTS.append(dict(author="Fixture", body=payload["body"]))
            self.reply(dict(ok=True))
        elif self.path == "/api/connections/connect":
            assert payload["id"] == "ssh"
            self.reply(dict(connection=dict(id="ssh", name="Fixture SSH", kind="ssh", connected=True, url=f"http://127.0.0.1:{self.server.server_port}")))
        elif self.path == "/api/connections/request":
            assert "body" in payload and "timeout_ms" in payload
            if payload["method"] == "POST":
                assert payload["path"] == "/api/profile/save" and payload["body"]["slug"] == "worker"
                self.reply(dict(ok=True))
            else:
                self.reply(state() if payload["path"].startswith("/api/state") else dict(providers=[dict(id="openrouter", label="OpenRouter", env_vars=["OPENROUTER_API_KEY"])]))
        elif self.path == "/api/favorite/model":
            assert payload["id"] == "fixture/one"
            self.reply(dict(favorite_models=["fixture/one"] if payload["favorite"] else []))
        elif self.path == "/api/theme":
            self.reply(dict(theme=payload["theme"]))
        else:
            self.reply(dict(ok=True))


QML_TESTS = '''
    TestCase {
        name: "RebuiltHermesControls"
        when: win.visible
        function initTestCase() { tryVerify(function(){return app.profiles.length === 3 && app.providers.length === 3}, 10000) }
        function assertEqual(actual, expected, message) {
            if (actual !== expected) console.error("ASSERT", message || "", JSON.stringify(actual), "expected", JSON.stringify(expected))
            compare(actual, expected, message || "")
        }
        function find(item, name) {
            if (!item) return null
            if (item.objectName === name) return item
            var direct = findChild(item, name)
            if (direct) return direct
            if (item.children) for (var i = 0; i < item.children.length; i++) { var found = find(item.children[i], name); if (found) return found }
            return null
        }
        function polish(item) {
            if (!item) return
            if (item.children) for (var i = 0; i < item.children.length; i++) polish(item.children[i])
            if (item.forceLayout) item.forceLayout()
        }
        function scrollTo(dialog, item) {
            polish(dialog.contentItem)
            var flick = dialog.scroll.contentItem
            flick.contentY = Math.max(0, Math.min(flick.contentHeight - flick.height, item.mapToItem(flick.contentItem, 0,0).y - 70))
            wait(60)
        }
        function click(item) { verify(!!item, "control exists"); polish(shell); wait(60); mouseClick(item); wait(40) }
        function init() {
            tryCompare(app, "pending", 0, 10000)
            profilesPage.editor.modelPicker.close(); profilesPage.editor.close()
            tasksPage.creator.close(); tasksPage.details.close(); tasksPage.projectForm.close()
            settingsPage.providerForm.close(); settingsPage.connectionForm.close(); modelsPage.confirmation.close()
            if (app.connectionId !== "local") { app.activate("local"); tryCompare(app,"pending",0,10000) }
            app.page = "Tasks"; app.error = ""; app.message = ""; wait(60)
        }
        function cleanup() { if (qtest_results.failed) console.error("UI_AUDIT_FAILURE", qtest_results.functionName) }
        function test_navigation_and_narrow_window() {
            assertEqual(win.minimumSize.width, 480)
            click(find(win.contentItem, "page_Settings")); assertEqual(app.page, "Settings")
            click(find(win.contentItem, "page_Profiles")); assertEqual(app.page, "Profiles")
            verify(shell.width <= win.width)
        }
        function test_long_personality_has_its_own_scroll_area() {
            profilesPage.editor.startEdit(app.profile("worker")); var form=profilesPage.editor
            var editor=find(form.contentItem,"profilePersonality")
            editor.text=Array(150).join("Review code carefully and verify the results.\n")
            wait(100)
            verify(editor.contentHeight > editor.availableHeight)
            verify(editor.height <= 200)
        }
        function test_minimum_window_keeps_forms_scrollable() {
            var previousWidth = win.implicitWidth; var previousHeight = win.implicitHeight
            win.implicitWidth = 480; win.implicitHeight = 360; wait(150)
            profilesPage.editor.startCreate("default"); var form=profilesPage.editor
            verify(form.width <= win.width - 20); verify(form.height <= win.height - 20)
            verify(form.scroll.contentItem.contentHeight > form.scroll.contentItem.height)
            find(form.contentItem,"profileName").text="Small window"
            var button=find(form.contentItem,"profileChooseModel"); scrollTo(form,button); click(button)
            var picker=form.modelPicker
            tryCompare(picker.catalog,"loading",false,5000)
            verify(picker.width <= win.width - 20); verify(picker.height <= win.height - 20)
            picker.close(); form.close()
            win.implicitWidth=previousWidth; win.implicitHeight=previousHeight; wait(100)
        }
        function test_new_profile_defaults_and_create() {
            app.page = "Profiles"; click(find(profilesPage, "newProfile"))
            var form = profilesPage.editor
            verify(form.visible); assertEqual(form.sourceSlug,"default")
            assertEqual(find(form.contentItem,"profileCopyMode").currentIndex,2)
            assertEqual(find(form.contentItem,"profileCopyKeys").checked,true)
            find(form.contentItem,"profileName").text = "New Helper"
            assertEqual(form.profileSlug,"new-helper")
            click(find(form.footer,"dialogSubmit"))
            tryCompare(form,"visible",false,5000)
            tryVerify(function(){return app.profiles.some(function(p){return p.slug === "new-helper"})},5000)
        }
        function test_generation_click_populates_draft() {
            profilesPage.editor.startCreate("default")
            var form=profilesPage.editor
            find(form.contentItem,"profileName").text="Code reviewer"
            var button=find(form.contentItem,"generateProfile"); scrollTo(form,button); click(button)
            tryVerify(function(){return find(form.contentItem,"profilePersonality").text.indexOf("# Role") === 0},5000)
            assertEqual(form.busy,false)
        }
        function test_generation_error_preserves_text_and_allows_retry() {
            profilesPage.editor.startCreate("default"); var form=profilesPage.editor
            find(form.contentItem,"profileName").text="Error case"
            find(form.contentItem,"profilePersonality").text="Keep my draft"
            var button=find(form.contentItem,"generateProfile"); scrollTo(form,button); click(button)
            tryVerify(function(){return form.error.indexOf("spending limit") >= 0},5000)
            assertEqual(find(form.contentItem,"profilePersonality").text,"Keep my draft")
            verify(button.enabled); assertEqual(form.scroll.contentItem.contentY,0)
        }
        function test_profile_model_catalog_selects_without_saving() {
            profilesPage.editor.startCreate("default"); var form=profilesPage.editor
            click(find(form.contentItem,"profileChooseModel"))
            var picker=form.modelPicker
            tryCompare(picker.catalog,"loading",false,5000)
            verify(picker.visible)
            var list=find(picker.contentItem,"modelList")
            tryVerify(function(){return list.count === 2 && list.itemAtIndex(1) !== null},5000)
            var select=find(list.itemAtIndex(1),"selectModel_fixture/two")
            if (!select) select=find(list.itemAtIndex(0),"selectModel_fixture/two")
            click(select)
            tryCompare(picker,"visible",false,5000)
            assertEqual(form.modelId,"fixture/two")
            verify(form.visible)
        }
        function test_task_rejects_missing_profile_selection() {
            click(find(tasksPage,"newTask")); var form=tasksPage.creator
            find(form.contentItem,"taskTitle").text="My task"
            click(find(form.footer,"dialogSubmit"))
            verify(form.error.indexOf("Select each allowed") >= 0)
            assertEqual(form.busy,false); verify(form.visible)
        }
        function test_task_requires_budget_and_starts_unassigned() {
            tasksPage.creator.start(null); var form=tasksPage.creator
            find(form.contentItem,"taskTitle").text="Test explicit access"
            var access=find(form.contentItem,"taskAccess")
            var allow=find(access,"allowProfile_worker"); scrollTo(form,allow); click(allow)
            verify(access.selected.indexOf("worker") >= 0); verify(!access.valid)
            access.budgets=({worker:2}); verify(access.valid)
            assertEqual(find(form.contentItem,"taskAssignee").currentIndex,0)
            click(find(form.footer,"dialogSubmit")); tryCompare(form,"visible",false,5000)
        }
        function test_existing_profile_editor_loads_saved_text() {
            app.page="Profiles"
            profilesPage.editor.startEdit(app.profile("worker")); var form=profilesPage.editor
            assertEqual(form.profileSlug,"worker")
            assertEqual(find(form.contentItem,"profilePersonality").text,"Audit code carefully.")
            verify(find(form.contentItem,"profileName").readOnly)
        }
        function test_provider_settings_is_its_own_form() {
            app.page="Settings"; settingsPage.section=2
            click(find(settingsPage,"providerSettings"))
            verify(settingsPage.providerForm.visible)
            assertEqual(settingsPage.providerForm.title,"Provider settings · default")
            verify(!profilesPage.editor.visible)
            verify(!!find(settingsPage.providerForm.contentItem,"providerApiKey"))
        }
        function test_provider_save_includes_private_key() {
            app.page="Settings"; settingsPage.section=2
            settingsPage.providerForm.start("default"); var form=settingsPage.providerForm
            find(form.contentItem,"providerApiKey").text="fake-ui-test-only"
            click(find(form.footer,"dialogSubmit"))
            tryCompare(form,"visible",false,5000)
            tryCompare(app,"pending",0,5000)
        }
        function test_task_comment_roundtrip() {
            tasksPage.details.start(app.tasks[0]); var form=tasksPage.details
            tryCompare(app,"pending",0,5000)
            var field=find(form.contentItem,"taskComment")
            field.text="Verified the finding"
            var button=find(form.contentItem,"addTaskComment")
            scrollTo(form,button); click(button)
            tryVerify(function(){return form.detail.comments && form.detail.comments.length > 0},5000)
            assertEqual(form.detail.comments[0].body,"Verified the finding")
        }
        function test_project_form_submits() {
            tasksPage.projectForm.start(null); var form=tasksPage.projectForm
            find(form.contentItem,"projectName").text="New project"
            click(find(form.footer,"dialogSubmit"))
            tryCompare(form,"visible",false,5000)
        }
        function test_catalog_search_and_refresh() {
            app.page="Models"; modelsPage.configure()
            tryCompare(modelsPage.catalog,"loading",false,5000)
            modelsPage.catalog.searchText="Code reviewer"
            assertEqual(modelsPage.catalog.filtered.length,1)
            modelsPage.catalog.providerId="alternate"; modelsPage.catalog.load(true)
            tryCompare(modelsPage.catalog,"loading",false,5000)
            assertEqual(modelsPage.catalog.providerId,"alternate")
            modelsPage.catalog.searchText=""
        }
        function test_favorite_model_roundtrip() {
            app.toggleFavorite("fixture/one")
            tryVerify(function(){return app.favorites.indexOf("fixture/one") >= 0},5000)
            app.toggleFavorite("fixture/one")
            tryVerify(function(){return app.favorites.indexOf("fixture/one") < 0},5000)
        }
        function test_remote_tab_routes_through_local_proxy() {
            verify(app.activate("remote"))
            tryCompare(app,"pending",0,5000)
            assertEqual(app.connectionId,"remote"); verify(app.connected)
            app.request("POST","/api/profile/save",{slug:"worker"},function(){app.message="remote payload arrived"})
            tryCompare(app,"message","remote payload arrived",5000)
            verify(app.activate("local")); tryCompare(app,"pending",0,5000)
        }
        function test_ssh_tab_connects_then_uses_tunnel() {
            verify(app.activate("ssh")); tryCompare(app,"pending",0,5000)
            assertEqual(app.connectionId,"ssh"); verify(app.connection().connected)
            verify(app.connection().url.indexOf("http://127.0.0.1:") === 0)
            verify(app.profiles.length >= 3 && app.connected)
            verify(app.activate("local")); tryCompare(app,"pending",0,5000)
        }
        function test_pending_request_blocks_connection_switch() {
            app.request("POST","/api/profile/save",{slug:"default"},function(){})
            verify(!app.activate("remote"))
            assertEqual(app.connectionId,"local")
            tryCompare(app,"pending",0,5000)
        }
        function cleanupTestCase() { console.log("UI_AUDIT_RESULTS", qtest_results.passCount, qtest_results.failCount); Qt.quit() }
    }
'''


def main():
    server = ThreadingHTTPServer(("127.0.0.1", 0), Fixture)
    threading.Thread(target=server.serve_forever, daemon=True).start()
    virtual = "--virtual" in sys.argv
    capture = "--capture" in sys.argv
    key = "hermes_lw_audit_" + str(os.getpid())
    quoted = json.dumps(key)
    if not virtual:
        subprocess.run(["hyprctl", "eval", f"_G[{quoted}] = hl.window_rule({{name={quoted},match={{title='^Hermes LW audit fixture$'}},workspace='4 silent',no_initial_focus=true}})"], check=True, capture_output=True)
    try:
        with tempfile.TemporaryDirectory(prefix="hermes-lw-ui-audit-") as folder:
            target = Path(folder)
            shutil.copytree(ROOT / "ui", target / "ui")
            shutil.copy2(ROOT / "HttpClient.qml", target / "HttpClient.qml")
            service = (ROOT / "AppState.qml").read_text().replace("http://127.0.0.1:18731", f"http://127.0.0.1:{server.server_port}")
            (target / "AppState.qml").write_text(service)
            source = (ROOT / "Main.qml").read_text().replace("import Quickshell", "import Quickshell\nimport QtTest", 1).replace('title: "Hermes LW"', 'title: "Hermes LW audit fixture"', 1)
            tests = QML_TESTS
            if capture:
                screenshot = '''
        function test_z_capture_pages() {
            function capturePage(name) {
                wait(250)
                var captured = false
                shell.grabToImage(function(result) { result.saveToFile("/tmp/hermes-rebuilt-" + name + ".png"); captured = true })
                tryVerify(function(){return captured}, 5000)
            }
            app.page = "Tasks"; capturePage("tasks")
            app.page = "Profiles"; capturePage("profiles")
            app.page = "Models"; tryCompare(modelsPage.catalog,"loading",false,5000); capturePage("models")
            app.page = "Settings"; settingsPage.section=2; capturePage("settings")
            function captureDialog(name) {
                wait(300)
                var origin=shell.mapToGlobal(0,0)
                var done=false
                var xhr=new XMLHttpRequest()
                xhr.onreadystatechange=function(){if(xhr.readyState===XMLHttpRequest.DONE)done=xhr.status===200}
                xhr.open("GET",app.endpoint+"/api/_capture?name="+name+"&width="+Math.round(shell.width)+"&height="+Math.round(shell.height)+"&x="+Math.round(origin.x)+"&y="+Math.round(origin.y)); xhr.send()
                tryVerify(function(){return done},15000)
            }
            app.page="Profiles"; profilesPage.editor.startCreate("default")
            find(profilesPage.editor.contentItem,"profileName").text="Code reviewer"
            find(profilesPage.editor.contentItem,"profileRole").text="Audit GitHub repos for bugs and security issues"
            captureDialog("profile-form"); profilesPage.editor.close()
            app.page="Settings"; settingsPage.providerForm.start("default")
            captureDialog("provider-form"); settingsPage.providerForm.close()
            app.page="Tasks"; tasksPage.creator.start(null)
            find(tasksPage.creator.contentItem,"taskTitle").text="Audit a repository"
            find(tasksPage.creator.contentItem,"taskBody").text="Inspect the code, verify findings and report concrete bugs."
            captureDialog("task-form"); tasksPage.creator.close()
        }
'''
                tests = tests.replace("        function cleanupTestCase()", screenshot + "        function cleanupTestCase()")
            if virtual:
                source = source.replace('            id: shell; anchors.fill: parent; padding: 0', '            id: shell; anchors.fill: parent; padding: 0\n' + tests, 1)
                source = source.replace('implicitWidth: 1180; implicitHeight: 800', 'implicitWidth: 1000; implicitHeight: 760')
            (target / "Main.qml").write_text(source)
            child = subprocess.Popen(["qs", "-n", "-p", str(target / "Main.qml")], stdout=subprocess.PIPE, stderr=subprocess.PIPE, text=True)
            tiled = False
            deadline = time.monotonic() + 12
            while not virtual and child.poll() is None and time.monotonic() < deadline:
                clients = json.loads(subprocess.check_output(["hyprctl", "clients", "-j"], text=True))
                window = next((c for c in clients if c.get("pid") == child.pid), None)
                if window and not window.get("floating", True) and window.get("workspace", {}).get("id") == 4:
                    tiled = True
                    break
                time.sleep(.05)
            if not virtual:
                if not tiled:
                    child.terminate()
                    stdout, stderr = child.communicate(timeout=10)
                    print(stdout + stderr)
                    raise SystemExit("The fixture was not tiled on desktop 4")
                for attempt in range(2):
                    if attempt:
                        child = subprocess.Popen(["qs", "-n", "-p", str(target / "Main.qml")], stdout=subprocess.PIPE, stderr=subprocess.PIPE, text=True)
                        window = None
                        deadline = time.monotonic() + 12
                        while child.poll() is None and time.monotonic() < deadline:
                            clients = json.loads(subprocess.check_output(["hyprctl", "clients", "-j"], text=True))
                            window = next((c for c in clients if c.get("pid") == child.pid), None)
                            if window and not window.get("floating", True) and window.get("workspace", {}).get("id") == 4:
                                break
                            time.sleep(.05)
                        if not window:
                            child.terminate()
                            stdout, stderr = child.communicate(timeout=5)
                            print(stdout + stderr)
                            raise SystemExit("Closing the fixture prevented its next single-instance launch")
                    selector = json.dumps("address:" + window["address"])
                    subprocess.run(["hyprctl", "eval", f"hl.dispatch(hl.dsp.window.close({{window={selector}}}))"], check=True, capture_output=True)
                    try:
                        stdout, stderr = child.communicate(timeout=5)
                    except subprocess.TimeoutExpired:
                        child.kill(); stdout, stderr = child.communicate(); print(stdout + stderr)
                        raise SystemExit("Window-manager close left a headless Quickshell instance running")
                    if child.returncode:
                        print(stdout + stderr)
                        raise SystemExit("The fixture failed while closing")
                print("TILED_UI: floating=false workspace=4")
                print("CLOSE_REOPEN: compositor close exits cleanly; single-instance relaunch succeeds")
            else:
                try:
                    stdout, stderr = child.communicate(timeout=100)
                except subprocess.TimeoutExpired:
                    child.kill(); stdout, stderr = child.communicate(); print(stdout + stderr); raise
                output = stdout + stderr
                print(output)
                if child.returncode or any(value in output for value in ("UI_AUDIT_FAILURE", "Failed to load", "ReferenceError", "TypeError", "Binding loop")):
                    raise SystemExit(1)
                marker = __import__("re").search(r"UI_AUDIT_RESULTS (\d+) (\d+)", output)
                if not marker or int(marker[2]) or int(marker[1]) < 20:
                    raise SystemExit("UI checks failed")
                print("VIRTUAL_UI: native controls rendered in Xvfb")
                print("FIXTURE_REQUESTS:", len(CALLS), "(no real provider requests)")
    finally:
        if not virtual:
            subprocess.run(["hyprctl", "eval", f"if _G[{quoted}] then _G[{quoted}]:set_enabled(false); _G[{quoted}]=nil end"], capture_output=True)
        server.shutdown(); server.server_close()
    if not virtual:
        environment = os.environ.copy()
        environment.pop("WAYLAND_DISPLAY", None)
        environment.update(QT_QPA_PLATFORM="xcb", QT_QUICK_BACKEND="software")
        result = subprocess.run(["xvfb-run", "-a", "-s", "-screen 0 1280x960x24", sys.executable, __file__, "--virtual"] + (["--capture"] if capture else []), env=environment)
        if result.returncode:
            raise SystemExit(result.returncode)


if __name__ == "__main__":
    main()
