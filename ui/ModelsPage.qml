import QtQuick
import QtQuick.Controls
import QtQuick.Layouts

ColumnLayout {
    id: page
    required property var api
    required property var host
    property alias catalog: catalog
    property alias confirmation: confirmation
    spacing: 10
    RowLayout {
        Layout.fillWidth: true
        Label { text: "Models"; font.pixelSize: 21; font.bold: true; Layout.fillWidth: true }
        Picker { model: page.api.profiles; textRole: "slug"; valueRole: "slug"; currentIndex: Math.max(0, page.api.profiles.map(function(p) { return p.slug }).indexOf(page.api.selectedProfile)); onActivated: { page.api.selectedProfile = currentValue; page.configure() } Accessible.name: "Profile for model selection" }
    }
    Label { Layout.fillWidth: true; text: "Search the provider catalog. Select a model to review and save it for the profile above."; wrapMode: Text.WordWrap; opacity: 0.8 }
    ModelCatalog {
        id: catalog; api: page.api; dialogHost: page.host; Layout.fillWidth: true; Layout.fillHeight: true
        onChosen: function(modelId, providerId, baseUrl) { confirmation.modelId = modelId; confirmation.providerId = providerId; confirmation.baseUrl = baseUrl; confirmation.open() }
        onAskAi: function(models, profileSlug, providerId) { advisor.start(models, profileSlug, providerId) }
    }
    function configure() {
        var p = api.profile(api.selectedProfile)
        catalog.profileSlug = api.selectedProfile; catalog.providerId = p.provider && p.provider !== "auto" ? p.provider : "openrouter"; catalog.baseUrl = p.base_url || ""; catalog.load(false)
    }
    onVisibleChanged: if (visible && api.profiles.length) configure()
    Connections { target: page.api; function onDataChanged() { if (page.visible && page.api.profiles.length && !catalog.loading) page.configure() } }
    FormDialog {
        id: confirmation; parent: page.host
        property string modelId: ""; property string providerId: ""; property string baseUrl: ""
        title: "Change profile model"; primaryText: "Save model"
        Label { Layout.fillWidth: true; text: "Save " + confirmation.providerId + " / " + confirmation.modelId + " for " + page.api.selectedProfile + "?"; wrapMode: Text.WrapAnywhere }
        onSubmitted: {
            var p = page.api.profile(page.api.selectedProfile); busy = true
            page.api.mutate("/api/profile/save", {slug: p.slug, provider: providerId, model: modelId, base_url: baseUrl, reasoning: p.reasoning || "medium", personality: p.personality || ""}, function() { confirmation.busy = false; confirmation.close(); page.api.message = "Model saved" }, function(v) { confirmation.busy = false; confirmation.error = v.error })
        }
    }
    AdvisorDialog { id: advisor; parent: page.host; api: page.api; onFindModel: function(id) { catalog.searchText = id } }
}
