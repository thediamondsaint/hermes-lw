import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import Quickshell

ColumnLayout {
    id: page
    required property var api
    required property var host
    property alias providerForm: providers
    property alias connectionForm: connectionForm
    property alias section: sections.currentIndex
    Label { text: "Settings"; font.pixelSize: 21; font.bold: true }
    TabBar { id: sections; Layout.fillWidth: true
        TabButton { implicitHeight: 36; text: "General" } TabButton { implicitHeight: 36; text: "Connections" } TabButton { implicitHeight: 36; text: "Providers" } TabButton { implicitHeight: 36; text: "Prompts" }
    }
    ScrollView {
        id: scroll; Layout.fillWidth: true; Layout.fillHeight: true; clip: true; contentWidth: availableWidth
        ScrollBar.horizontal.policy: ScrollBar.AlwaysOff
        ColumnLayout {
            width: scroll.availableWidth; spacing: 12
            ColumnLayout {
                visible: sections.currentIndex === 0; Layout.fillWidth: true; spacing: 12
                Label { Layout.fillWidth: true; text: "One tab per Hermes connection. Profiles, tasks and providers belong to the selected connection."; wrapMode: Text.WordWrap }
                Label { Layout.fillWidth: true; text: "Current connection: " + (page.api.connection().name || "Local Hermes"); font.bold: true; wrapMode: Text.WrapAnywhere }
                Label { Layout.fillWidth: true; text: "Dark mode is saved on the selected Hermes connection."; wrapMode: Text.WordWrap }
                ActionButton { text: page.api.dark ? "Switch to light mode" : "Switch to dark mode"; onClicked: page.api.request("POST", "/api/theme", {theme: page.api.dark ? "light" : "dark"}, function(v) { page.api.dark = v.theme === "dark" }) }
                Label { text: "Startup project"; font.bold: true }
                Picker { id: startup; Layout.fillWidth: true; model: page.api.projects; textRole: "name"; valueRole: "slug"; currentIndex: Math.max(0, page.api.projects.map(function(p) { return p.slug }).indexOf(page.api.board)) }
                ActionButton { text: "Save startup project"; enabled: startup.currentIndex >= 0; onClicked: page.api.mutate("/api/project/select", {slug: startup.currentValue}, function() { page.api.board = startup.currentValue; page.api.message = "Startup project saved" }) }
                Label { text: "Spending & task access"; font.bold: true }
                Label { Layout.fillWidth: true; text: "Task profile selections are enforced through Hermes LW. Dollar budgets are planning metadata; configure provider-side key limits for actual spend caps. Pausing a profile blocks new assignments here but does not cancel running workers."; wrapMode: Text.WordWrap }
                Label { text: "Connection status"; font.bold: true }
                Label { Layout.fillWidth: true; text: page.api.connected ? "Backend reachable. Refresh reloads the selected project and profiles." : "Backend unavailable. Check the connection, then Refresh."; wrapMode: Text.WordWrap }
            }
            ColumnLayout {
                visible: sections.currentIndex === 1; Layout.fillWidth: true; spacing: 10
                ActionButton { text: "Add connection"; primary: true; objectName: "addConnection"; onClicked: connectionForm.start(null) }
                Repeater { model: page.api.connections
                    Frame {
                        required property var modelData; Layout.fillWidth: true
                        contentItem: ColumnLayout {
                            Label { Layout.fillWidth: true; text: modelData.name + " · " + modelData.kind; font.bold: true; wrapMode: Text.WrapAnywhere }
                            Label { Layout.fillWidth: true; text: modelData.kind === "ssh" ? modelData.host || "" : modelData.kind === "https" ? modelData.url || "" : "This computer"; wrapMode: Text.WrapAnywhere; opacity: 0.8 }
                            Flow {
                                Layout.fillWidth: true; spacing: 6
                                ActionButton { text: "Open"; onClicked: page.api.activate(modelData.id) }
                                ActionButton { visible: modelData.id !== "local"; text: "Edit"; onClicked: connectionForm.start(modelData) }
                                ActionButton { visible: modelData.kind === "ssh"; text: "Disconnect"; enabled: !!modelData.connected && !page.api.pending; onClicked: page.api.request("POST", "/api/connections/disconnect", {id: modelData.id}, function() { page.api.loadConnections(); page.api.message = "SSH connection closed" }, null, 30000, "disconnect", true) }
                                ActionButton { visible: modelData.id !== "local"; text: "Remove…"; danger: true; onClicked: { removeConnection.item = modelData; removeConnection.open() } }
                            }
                        }
                    }
                }
            }
            ColumnLayout {
                visible: sections.currentIndex === 2; Layout.fillWidth: true; spacing: 12
                Label { Layout.fillWidth: true; text: "Select a profile, then edit its inference provider, model and private credentials."; wrapMode: Text.WordWrap }
                Picker { id: providerProfile; Layout.fillWidth: true; model: page.api.profiles; textRole: "slug"; valueRole: "slug"; Accessible.name: "Profile for provider settings" }
                Label { Layout.fillWidth: true; text: { var p = page.api.profile(providerProfile.currentValue); return (p.provider || "No provider") + " / " + (p.model || "No model") } wrapMode: Text.WrapAnywhere }
                ActionButton { text: "Open provider settings…"; primary: true; objectName: "providerSettings"; enabled: providerProfile.currentIndex >= 0; onClicked: providers.start(providerProfile.currentValue) }
                Label { Layout.fillWidth: true; text: "OpenRouter key-limit errors mean the key’s provider-side budget is exhausted. Change that limit in OpenRouter or save another key. Cloning a key does not create a new spending allowance."; wrapMode: Text.WordWrap; opacity: 0.8 }
            }
            ColumnLayout {
                visible: sections.currentIndex === 3; Layout.fillWidth: true; spacing: 10
                ActionButton { text: "New prompt"; primary: true; onClicked: prompts.start(null) }
                Field { id: promptSearch; Layout.fillWidth: true; placeholderText: "Search prompts…" }
                Repeater { model: page.api.prompts.filter(function(p) { return (p.title + " " + p.body).toLowerCase().indexOf(promptSearch.text.toLowerCase()) >= 0 })
                    Frame {
                        required property var modelData; Layout.fillWidth: true
                        contentItem: ColumnLayout {
                            Label { Layout.fillWidth: true; text: (modelData.favorite ? "★ " : "") + modelData.title; font.bold: true; wrapMode: Text.WordWrap }
                            Label { Layout.fillWidth: true; text: modelData.body; maximumLineCount: 4; elide: Text.ElideRight; wrapMode: Text.WrapAnywhere; textFormat: Text.PlainText; opacity: 0.8 }
                            Flow {
                                Layout.fillWidth: true; spacing: 6
                                ActionButton { text: "Edit"; onClicked: prompts.start(modelData) }
                                ActionButton { text: "Copy"; onClicked: { Quickshell.clipboardText = modelData.body; page.api.message = "Prompt copied" } }
                                ActionButton { text: modelData.favorite ? "Unfavorite" : "Favorite"; onClicked: page.api.mutate("/api/prompt/save", {id: modelData.id, title: modelData.title, body: modelData.body, favorite: !modelData.favorite}) }
                                ActionButton { text: "Run locally…"; enabled: page.api.connectionId === "local"; onClicked: { runPrompt.body = modelData.body; runPrompt.open() } }
                                ActionButton { text: "Delete…"; danger: true; onClicked: { removePrompt.promptId = modelData.id; removePrompt.open() } }
                            }
                        }
                    }
                }
                Label { visible: page.api.prompts.length === 0; text: "No saved prompts. Add reusable instructions here."; Layout.fillWidth: true; wrapMode: Text.WordWrap }
            }
        }
    }
    ConnectionForm { id: connectionForm; parent: page.host; api: page.api }
    ProviderForm { id: providers; objectName: "providerForm"; parent: page.host; api: page.api }
    PromptForm { id: prompts; parent: page.host; api: page.api }
    FormDialog { id: removeConnection; parent: page.host; property var item: ({}); title: "Remove connection"; primaryText: "Remove"
        Label { Layout.fillWidth: true; text: "Remove the saved connection “" + (removeConnection.item.name || "") + "”?"; wrapMode: Text.WordWrap }
        onSubmitted: { busy = true; page.api.request("POST", "/api/connections/remove", {id: item.id}, function() { removeConnection.busy = false; removeConnection.close(); if (page.api.connectionId === removeConnection.item.id) page.api.activate("local"); page.api.loadConnections() }, function(v) { removeConnection.busy = false; removeConnection.error = v.error }, 30000, "remove-connection", true) }
    }
    FormDialog { id: removePrompt; parent: page.host; property string promptId: ""; title: "Delete prompt"; primaryText: "Delete"
        Label { text: "Delete this saved prompt?" }
        onSubmitted: { busy = true; page.api.mutate("/api/prompt/delete", {id: promptId}, function() { removePrompt.busy = false; removePrompt.close() }, function(v) { removePrompt.busy = false; removePrompt.error = v.error }) }
    }
    FormDialog { id: runPrompt; parent: page.host; property string body: ""; title: "Run prompt in Hermes"; primaryText: "Open Hermes terminal"
        Picker { id: runProfile; Layout.fillWidth: true; model: page.api.profiles; textRole: "slug"; valueRole: "slug" }
        Label { Layout.fillWidth: true; text: { var p = page.api.profile(runProfile.currentValue); return "Uses " + p.provider + " / " + p.model + ". Opens an interactive terminal. Provider charges may apply." } wrapMode: Text.WrapAnywhere }
        onSubmitted: { busy = true; var p = page.api.profile(runProfile.currentValue); page.api.request("POST", "/api/hermes", {profile: p.slug, provider: p.provider, model: p.model, prompt: body}, function(v) { runPrompt.busy = false; runPrompt.close(); page.api.message = v.message }, function(v) { runPrompt.busy = false; runPrompt.error = v.error }, 30000, "launch-hermes") }
    }
}
