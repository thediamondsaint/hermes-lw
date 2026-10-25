import QtQuick
import QtQuick.Controls
import QtQuick.Layouts

FormDialog {
    id: tools
    required property var api
    property string profileSlug: "default"
    property var extensions: ({})
    property int loadId: 0
    title: "Tools & apps · " + profileSlug; showSubmit: false; preferredWidth: 760
    function start(slug) { profileSlug = slug; extensions = ({}); open(); load() }
    function load() {
        var id = ++loadId; busy = true
        api.request("GET", "/api/extensions?profile=" + encodeURIComponent(profileSlug) + "&platform=" + platform.currentText, null, function(value) { if (id === tools.loadId) { tools.busy = false; tools.extensions = value } }, function(value) { if (id === tools.loadId) { tools.busy = false; tools.error = value.error } }, 100000)
    }
    function act(payload) {
        busy = true; error = ""
        payload.profile = profileSlug; payload.platform = platform.currentText
        api.request("POST", "/api/extensions/action", payload, function() { tools.load() }, function(value) { tools.busy = false; tools.error = value.error }, 150000, "extension-action")
    }
    Label { Layout.fillWidth: true; text: "Capabilities belong to this profile. Install only plugins and apps you trust."; wrapMode: Text.WordWrap }
    RowLayout {
        Layout.fillWidth: true
        Picker { id: platform; Layout.fillWidth: true; model: ["cli", "gateway"]; enabled: !tools.busy; onActivated: tools.load(); Accessible.name: "Tool platform" }
        ActionButton { text: "Refresh"; enabled: !tools.busy; onClicked: tools.load() }
    }
    Label { visible: tools.busy; text: "Working with Hermes…" }
    TabBar { id: sections; Layout.fillWidth: true; TabButton { implicitHeight: 36; text: "Tools" } TabButton { implicitHeight: 36; text: "Plugins" } TabButton { implicitHeight: 36; text: "Apps (MCP)" } }
    ColumnLayout {
        visible: sections.currentIndex === 0; Layout.fillWidth: true
        Repeater { model: tools.extensions.tools || []
            Choice { required property var modelData; Layout.fillWidth: true; text: modelData.name; checked: !!modelData.enabled; enabled: !tools.busy; onClicked: tools.act({kind: "tool", name: modelData.name, enabled: checked}) }
        }
        Label { visible: (tools.extensions.tools || []).length === 0 && !tools.busy; text: "No tools returned for this platform." }
    }
    ColumnLayout {
        visible: sections.currentIndex === 1; Layout.fillWidth: true; spacing: 10
        Repeater { model: tools.extensions.plugins || []
            Frame { required property var modelData; Layout.fillWidth: true
                contentItem: ColumnLayout {
                    Label { text: modelData.name; font.bold: true; Layout.fillWidth: true; wrapMode: Text.WrapAnywhere }
                    Flow { Layout.fillWidth: true; spacing: 6
                        ActionButton { text: modelData.enabled ? "Disable" : "Enable"; enabled: !tools.busy; onClicked: tools.act({kind: "plugin", action: "toggle", name: modelData.name, enabled: !modelData.enabled, allow_tool_override: false}) }
                        ActionButton { text: "Update"; enabled: !tools.busy && ["git","user"].indexOf(modelData.source) >= 0; onClicked: tools.act({kind: "plugin", action: "update", name: modelData.name}) }
                        ActionButton { text: "Remove"; danger: true; enabled: !tools.busy && ["git","user"].indexOf(modelData.source) >= 0; onClicked: tools.act({kind: "plugin", action: "remove", name: modelData.name}) }
                    }
                }
            }
        }
        Field { id: pluginSource; Layout.fillWidth: true; placeholderText: "GitHub owner/repository or plugin Git URL"; selectByMouse: true }
        Choice { id: trust; text: "I trust this plugin’s code" }
        ActionButton { text: "Install disabled"; enabled: !tools.busy && trust.checked && pluginSource.text.trim().length > 0; onClicked: tools.act({kind: "plugin", action: "install", identifier: pluginSource.text}) }
    }
    ColumnLayout {
        visible: sections.currentIndex === 2; Layout.fillWidth: true; spacing: 10
        Repeater { model: tools.extensions.mcp_servers || []
            Frame { required property var modelData; Layout.fillWidth: true
                contentItem: ColumnLayout {
                    Label { Layout.fillWidth: true; text: modelData.name + " · " + (modelData.endpoint_host || modelData.command || modelData.transport || "MCP"); wrapMode: Text.WrapAnywhere }
                    RowLayout {
                        ActionButton { text: "Test"; enabled: !tools.busy; onClicked: tools.act({kind: "mcp", action: "test", name: modelData.name}) }
                        ActionButton { text: "Remove"; danger: true; enabled: !tools.busy; onClicked: tools.act({kind: "mcp", action: "remove", name: modelData.name}) }
                    }
                }
            }
        }
        Picker { id: catalog; Layout.fillWidth: true; model: tools.extensions.mcp_catalog || []; textRole: "name"; Accessible.name: "MCP app catalog" }
        ActionButton { text: "Install selected app"; enabled: !tools.busy && catalog.currentIndex >= 0; onClicked: tools.act({kind: "mcp", action: "catalog", name: catalog.currentText}) }
        ActionButton { text: "Add custom app…"; enabled: !tools.busy; onClicked: addApp.open() }
    }
    FormDialog {
        id: addApp; parent: tools.parent; title: "Add MCP app"; primaryText: "Add app"
        Field { id: appName; Layout.fillWidth: true; placeholderText: "App name (letters, numbers, hyphens)" }
        Picker { id: transport; Layout.fillWidth: true; model: ["HTTP server", "Local command (stdio)"] }
        Field { id: url; visible: transport.currentIndex === 0; Layout.fillWidth: true; placeholderText: "https://server/mcp" }
        Picker { id: auth; visible: transport.currentIndex === 0; Layout.fillWidth: true; model: ["No auth", "Bearer token", "OAuth"] }
        Field { id: token; visible: transport.currentIndex === 0 && auth.currentIndex === 1; Layout.fillWidth: true; echoMode: TextInput.Password; placeholderText: "Bearer token" }
        Field { id: command; visible: transport.currentIndex === 1; Layout.fillWidth: true; placeholderText: "Command, e.g. uvx" }
        Field { id: args; visible: transport.currentIndex === 1; Layout.fillWidth: true; placeholderText: "Arguments (shell quoting supported)" }
        Editor { id: env; visible: transport.currentIndex === 1; Layout.fillWidth: true; Layout.preferredHeight: 70; text: "{}"; placeholderText: "Environment as JSON"; wrapMode: TextEdit.Wrap }
        Label { Layout.fillWidth: true; text: "Adding an app grants this profile access to its tools. Only connect trusted apps."; wrapMode: Text.WordWrap }
        onSubmitted: {
            var environment = {}
            if (transport.currentIndex === 1) { try { environment = JSON.parse(env.text) } catch(e) { error = "Enter a valid JSON object for the environment."; return } }
            busy = true
            tools.api.request("POST", "/api/extensions/action", {profile: tools.profileSlug, kind: "mcp", action: "add", transport: transport.currentIndex === 0 ? "http" : "stdio", name: appName.text, url: url.text, auth: ["none", "header", "oauth"][auth.currentIndex], api_key: token.text, command: command.text, args: args.text, env: environment}, function() { addApp.busy = false; token.text = ""; addApp.close(); tools.load() }, function(v) { addApp.busy = false; addApp.error = v.error }, 100000, "add-mcp")
        }
    }
}
