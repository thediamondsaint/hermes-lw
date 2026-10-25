import QtQuick
import QtQuick.Controls
import QtQuick.Layouts

FormDialog {
    id: form
    required property var api
    property alias modelPicker: modelPicker
    property bool editing: false
    property string savedSlug: ""
    property string sourceSlug: "default"
    property string providerId: "openrouter"
    property string modelId: ""
    property string baseUrl: ""
    property string generatorModel: ""
    property string generatorProvider: "openrouter"
    property string pickerTarget: "profile"
    property string status: ""
    property bool modelChosen: false
    property bool advanced: false
    readonly property string profileSlug: savedSlug || api.slug(nameInput.text)
    title: editing || savedSlug ? "Edit profile" : "New profile"
    primaryText: editing || savedSlug ? "Save profile" : "Create profile"
    function startCreate(source) {
        editing = false; savedSlug = ""; sourceSlug = source || "default"; modelChosen = false
        var p = api.profile(sourceSlug)
        nameInput.text = ""; roleInput.text = ""; personality.text = ""; keyInput.text = ""
        providerId = p.provider && p.provider !== "auto" ? p.provider : "openrouter"; modelId = p.model || ""; baseUrl = p.base_url || ""
        generatorModel = modelId; generatorProvider = providerId; differentModel.checked = false
        copyKeys.checked = true; copyMode.currentIndex = 2; advanced = false; status = ""; open()
    }
    function setSource(slug) {
        sourceSlug = slug
        if (!modelChosen) { var p = api.profile(slug); providerId = p.provider && p.provider !== "auto" ? p.provider : "openrouter"; modelId = p.model || ""; baseUrl = p.base_url || "" }
    }
    function startEdit(p) {
        editing = true; savedSlug = p.slug; sourceSlug = p.slug
        nameInput.text = p.slug; roleInput.text = ""; personality.text = p.personality || ""; keyInput.text = ""
        providerId = p.provider && p.provider !== "auto" ? p.provider : "openrouter"; modelId = p.model || ""; baseUrl = p.base_url || ""
        generatorModel = modelId; generatorProvider = providerId; differentModel.checked = false
        reasoning.currentIndex = Math.max(0, reasoning.model.indexOf(p.reasoning || "medium"))
        advanced = false; status = ""; open()
    }
    function generate() {
        if (busy) return
        if (!/^[a-z0-9][a-z0-9-]{0,39}$/.test(profileSlug)) { error = "Enter a name that produces a profile ID of 1–40 letters, numbers or hyphens."; return }
        var selectedModel = differentModel.checked ? generatorModel : modelId
        var selectedProvider = differentModel.checked ? generatorProvider : providerId
        if (!selectedModel) { error = "Choose a text model before generating."; return }
        busy = true; error = ""; status = "Generating with " + selectedProvider + " / " + selectedModel + "…"
        api.request("POST", "/api/profile/generate", {name: profileSlug, role: roleInput.text, generator_profile: sourceSlug, provider: selectedProvider, model: selectedModel}, function(value) {
            form.busy = false
            if (!value.personality) { form.error = "The model returned no personality. Your existing text is preserved."; form.status = ""; return }
            personality.text = value.personality; form.status = "Draft ready. Review and edit it before saving."
        }, function(value) { form.busy = false; form.status = ""; form.error = value.error }, 195000, "generate-profile")
    }
    function finish(slug) {
        if (!keyInput.text.trim()) { busy = false; close(); api.selectedProfile = slug; api.refresh(); api.message = "Profile saved"; return }
        var keyName = keyVariable.currentText
        api.request("POST", "/api/profile/key", {slug: slug, provider: providerId, key_name: keyName || "CUSTOM_API_KEY", key: keyInput.text}, function() {
            keyInput.text = ""; form.busy = false; form.close(); form.api.selectedProfile = slug; form.api.refresh(); form.api.message = "Profile and key saved"
        }, function(value) { form.busy = false; form.error = "Profile saved, but the key was not saved: " + value.error; form.api.refresh() }, 30000, "profile-key")
    }
    Label { text: "Name"; font.bold: true }
    Field { id: nameInput; objectName: "profileName"; Layout.fillWidth: true; readOnly: form.editing || !!form.savedSlug; enabled: !form.busy; placeholderText: "e.g. Code reviewer"; selectByMouse: true }
    Label { Layout.fillWidth: true; text: "Profile ID: " + (form.profileSlug || "enter a name"); wrapMode: Text.WrapAnywhere; opacity: 0.75; font.pixelSize: 12 }
    Label { text: form.editing ? "Goal for an AI draft (optional)" : "What should this profile do?"; font.bold: true }
    Field { id: roleInput; objectName: "profileRole"; Layout.fillWidth: true; enabled: !form.busy; placeholderText: "e.g. Find bugs and security issues in GitHub repos"; selectByMouse: true }
    Label { text: "Model"; font.bold: true }
    Label { Layout.fillWidth: true; text: form.providerId + " / " + (form.modelId || "Choose a model"); wrapMode: Text.WrapAnywhere; objectName: "profileModelLabel" }
    ActionButton { text: "Choose model…"; enabled: !form.busy; objectName: "profileChooseModel"; onClicked: { form.pickerTarget = "profile"; modelPicker.choose(form.sourceSlug, form.providerId, form.baseUrl, true) } }
    Label { text: "Personality"; font.bold: true }
    Editor { id: personality; objectName: "profilePersonality"; Layout.fillWidth: true; Layout.preferredHeight: 190; wrapMode: TextEdit.Wrap; selectByMouse: true; enabled: !form.busy; placeholderText: form.editing ? "How this profile should work and communicate…" : "Leave empty to keep the source personality, write your own, or generate a draft." }
    ActionButton { objectName: "generateProfile"; text: form.busy ? "Working…" : "Generate draft (paid)"; enabled: !form.busy; onClicked: form.generate() }
    Choice { id: differentModel; text: "Use a different model to write the draft"; enabled: !form.busy }
    ActionButton { visible: differentModel.checked; text: "Choose draft model…"; enabled: !form.busy; onClicked: { form.pickerTarget = "generator"; modelPicker.choose(form.sourceSlug, form.generatorProvider, "", true) } }
    Label { Layout.fillWidth: true; text: "Generation: " + (differentModel.checked ? form.generatorProvider + " / " + form.generatorModel : form.providerId + " / " + form.modelId) + "\nCredentials from: " + form.sourceSlug + ". Provider charges may apply. Opening this form makes no model request."; wrapMode: Text.WrapAnywhere; font.pixelSize: 12; opacity: 0.8 }
    Label { Layout.fillWidth: true; visible: form.status.length > 0; text: form.status; wrapMode: Text.WordWrap }
    ActionButton { Layout.fillWidth: true; text: (form.advanced ? "▾ " : "▸ ") + "Copy settings, provider & API key"; onClicked: form.advanced = !form.advanced }
    ColumnLayout {
        Layout.fillWidth: true; visible: form.advanced; spacing: 10
        Label { visible: !form.editing; text: "Copy from"; font.bold: true }
        Picker { visible: !form.editing; Layout.fillWidth: true; model: form.api.profiles; textRole: "slug"; valueRole: "slug"; currentIndex: Math.max(0, form.api.profiles.map(function(p) { return p.slug }).indexOf(form.sourceSlug)); enabled: !form.busy; onActivated: form.setSource(currentValue) }
        Picker { id: copyMode; objectName: "profileCopyMode"; visible: !form.editing; Layout.fillWidth: true; model: ["Blank profile", "Copy settings, personality & skills", "Full copy (default)"]; enabled: !form.busy }
        Choice { id: copyKeys; objectName: "profileCopyKeys"; visible: !form.editing; text: "Copy source API keys"; checked: true; enabled: copyMode.currentIndex > 0 && !form.busy }
        Label { visible: !form.editing; Layout.fillWidth: true; text: "Default: full copy of default, including keys. Copied keys share their provider spending limits."; wrapMode: Text.WordWrap; font.pixelSize: 12 }
        Label { text: "Provider"; font.bold: true }
        Picker { Layout.fillWidth: true; model: form.api.providers; textRole: "label"; valueRole: "id"; currentIndex: form.api.providerIndex(form.providerId); enabled: !form.busy; onActivated: { form.providerId = currentValue; form.modelId = ""; form.baseUrl = "" } }
        Field { objectName: "profileManualModel"; Layout.fillWidth: true; text: form.modelId; onTextEdited: { form.modelId = text.trim(); form.modelChosen = true } placeholderText: "Exact model ID (manual override)"; selectByMouse: true; enabled: !form.busy }
        Field { visible: form.providerId === "custom"; Layout.fillWidth: true; text: form.baseUrl; onTextEdited: form.baseUrl = text; placeholderText: "http(s)://your-server/v1"; selectByMouse: true; enabled: !form.busy }
        Label { text: "Reasoning"; visible: form.editing; font.bold: true }
        Picker { id: reasoning; visible: form.editing; Layout.fillWidth: true; model: ["none", "low", "medium", "high"]; enabled: !form.busy }
        Label { text: "New provider key (optional)"; font.bold: true }
        Picker { id: keyVariable; Layout.fillWidth: true; model: {
            var p = form.api.providers.filter(function(p) { return p.id === form.providerId })[0]
            return p ? (p.env_vars || []).filter(function(n) { return n.endsWith("_API_KEY") || n.endsWith("_TOKEN") }) : []
        } visible: count > 1; enabled: !form.busy }
        Field { id: keyInput; objectName: "profileApiKey"; Layout.fillWidth: true; echoMode: TextInput.Password; placeholderText: "Leave empty to keep existing / copied keys"; selectByMouse: true; enabled: !form.busy }
        Label { Layout.fillWidth: true; text: "Keys are saved privately to this profile. Existing secret values are never displayed. OAuth providers use Hermes’ sign-in flow."; wrapMode: Text.WordWrap; font.pixelSize: 12; opacity: 0.75 }
    }
    onSubmitted: {
        if (!/^[a-z0-9][a-z0-9-]{0,39}$/.test(profileSlug)) { error = "Enter a name that produces a valid profile ID (up to 40 characters)."; return }
        if (!modelId) { error = "Choose a model first."; return }
        busy = true; error = ""
        var exists = editing || !!savedSlug
        var payload = {slug: profileSlug, provider: providerId, model: modelId, base_url: baseUrl, personality: personality.text, reasoning: reasoning.currentText}
        if (!exists) Object.assign(payload, {source: sourceSlug, clone_mode: ["empty", "clone", "clone_all"][copyMode.currentIndex], copy_api_key: copyKeys.checked, description: roleInput.text})
        api.request("POST", exists ? "/api/profile/save" : "/api/profile/create", payload, function(value) { form.savedSlug = value.profile || form.profileSlug; form.finish(form.savedSlug) }, function(value) { form.busy = false; form.error = value.error }, 105000, "save-profile")
    }
    ModelPicker {
        id: modelPicker; parent: form.parent; api: form.api
        onChosen: function(modelId, providerId, baseUrl) {
            if (form.pickerTarget === "generator") { form.generatorModel = modelId; form.generatorProvider = providerId }
            else { form.modelId = modelId; form.providerId = providerId; form.baseUrl = baseUrl; form.modelChosen = true }
        }
        onAskAi: function(models, profileSlug, providerId) { advisor.start(models, profileSlug, providerId) }
    }
    AdvisorDialog { id: advisor; parent: form.parent; api: form.api; onFindModel: function(id) { modelPicker.catalog.searchText = id } }
}
