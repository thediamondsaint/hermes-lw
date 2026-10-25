import QtQuick
import QtQuick.Controls
import QtQuick.Layouts

FormDialog {
    id: form
    required property var api
    property string profileSlug: "default"
    property string providerId: "openrouter"
    property string modelId: ""
    property string baseUrl: ""
    title: "Provider settings · " + profileSlug; primaryText: "Save provider"
    function start(slug) {
        profileSlug = slug; var p = api.profile(slug)
        providerId = p.provider && p.provider !== "auto" ? p.provider : "openrouter"; modelId = p.model || ""; baseUrl = p.base_url || ""
        key.text = ""; reasoning.currentIndex = Math.max(0, reasoning.model.indexOf(p.reasoning || "medium")); open()
    }
    function finish() { busy = false; close(); api.refresh(); api.message = "Provider settings saved" }
    Label { text: "Provider"; font.bold: true }
    Picker { Layout.fillWidth: true; model: form.api.providers; textRole: "label"; valueRole: "id"; currentIndex: form.api.providerIndex(form.providerId); enabled: !form.busy; onActivated: { form.providerId = currentValue; form.modelId = ""; form.baseUrl = "" } }
    Label { text: "Model"; font.bold: true }
    Field { objectName: "providerModel"; Layout.fillWidth: true; text: form.modelId; onTextEdited: form.modelId = text; placeholderText: "Exact provider model ID"; selectByMouse: true; enabled: !form.busy }
    ActionButton { text: "Browse provider models…"; enabled: !form.busy; onClicked: picker.choose(form.profileSlug, form.providerId, form.baseUrl, true) }
    Field { visible: form.providerId === "custom"; Layout.fillWidth: true; text: form.baseUrl; onTextEdited: form.baseUrl = text; placeholderText: "http(s)://server/v1"; enabled: !form.busy }
    Label { text: "Reasoning"; font.bold: true }
    Picker { id: reasoning; Layout.fillWidth: true; model: ["none", "low", "medium", "high"]; enabled: !form.busy }
    Label { text: "Provider credential"; font.bold: true }
    Picker { id: keyName; Layout.fillWidth: true; model: {
        var provider = form.api.providers.filter(function(p) { return p.id === form.providerId })[0]
        return provider ? (provider.env_vars || []).filter(function(n) { return n.endsWith("_API_KEY") || n.endsWith("_TOKEN") }) : []
    } enabled: !form.busy; visible: count > 0 }
    Label { Layout.fillWidth: true; text: form.providerId === "custom" ? (form.api.profile(form.profileSlug).custom_api_key_configured ? "Custom endpoint key is configured." : "No custom endpoint key saved.") : keyName.count ? ((form.api.profile(form.profileSlug).configured_api_keys || []).indexOf(keyName.currentText) >= 0 ? keyName.currentText + " is configured." : "No saved " + keyName.currentText + " for this profile.") : "This provider uses Hermes sign-in / system credentials. Run hermes model to authenticate."; wrapMode: Text.WordWrap }
    Field { id: key; objectName: "providerApiKey"; Layout.fillWidth: true; echoMode: TextInput.Password; placeholderText: "New key (leave blank to keep existing)"; selectByMouse: true; enabled: !form.busy && (keyName.count > 0 || form.providerId === "custom") }
    ActionButton { text: "Clear saved key…"; danger: true; enabled: !form.busy && (keyName.count > 0 || form.providerId === "custom"); onClicked: clearKey.open() }
    Label { Layout.fillWidth: true; text: "Keys are stored privately in the selected profile. A copied key shares the same provider account and spending limit. Saving settings does not run a model."; wrapMode: Text.WordWrap; opacity: 0.8 }
    onSubmitted: {
        if (!modelId.trim()) { error = "Choose or enter a model ID."; return }
        busy = true; var p = api.profile(profileSlug)
        api.request("POST", "/api/profile/save", {slug: profileSlug, provider: providerId, model: modelId, base_url: baseUrl, reasoning: reasoning.currentText, personality: p.personality || ""}, function() {
            if (!key.text.trim()) { form.finish(); return }
            form.api.request("POST", "/api/profile/key", {slug: form.profileSlug, provider: form.providerId, key_name: keyName.currentText || "CUSTOM_API_KEY", key: key.text}, function() { key.text = ""; form.finish() }, function(v) { form.busy = false; form.error = "Provider saved, but key was not saved: " + v.error; form.api.refresh() }, 30000, "provider-key")
        }, function(v) { form.busy = false; form.error = v.error }, 100000, "save-provider")
    }
    ModelPicker { id: picker; parent: form.parent; api: form.api; onChosen: function(modelId, providerId, baseUrl) { form.modelId = modelId; form.providerId = providerId; form.baseUrl = baseUrl } onAskAi: function(models, profileSlug, providerId) { advisor.start(models, profileSlug, providerId) } }
    AdvisorDialog { id: advisor; parent: form.parent; api: form.api; onFindModel: function(id) { picker.catalog.searchText = id } }
    FormDialog {
        id: clearKey; parent: form.parent; title: "Clear provider key"; primaryText: "Clear key"
        Label { Layout.fillWidth: true; text: "Remove this profile’s " + (keyName.currentText || "custom endpoint key") + "? Other cloned copies are unchanged."; wrapMode: Text.WordWrap }
        onSubmitted: { busy = true; form.api.mutate("/api/profile/key", {slug: form.profileSlug, provider: form.providerId, key_name: keyName.currentText || "CUSTOM_API_KEY", clear: true}, function() { clearKey.busy = false; clearKey.close() }, function(v) { clearKey.busy = false; clearKey.error = v.error }, 30000, "clear-key") }
    }
}
