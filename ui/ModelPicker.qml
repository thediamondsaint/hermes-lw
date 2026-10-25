import QtQuick
import QtQuick.Controls
import QtQuick.Layouts

FormDialog {
    id: picker
    required property var api
    property alias catalog: catalog
    signal chosen(string modelId, string providerId, string baseUrl)
    signal askAi(var models, string profileSlug, string providerId)
    title: "Choose a model"; showSubmit: false; preferredWidth: 960
    height: Math.min(parent.height - 24, 780)
    function choose(profile, provider, baseUrl, textOnly) {
        catalog.profileSlug = profile || "default"; catalog.providerId = provider || "openrouter"; catalog.baseUrl = baseUrl || ""; catalog.textOnly = !!textOnly
        catalog.searchText = ""; open(); catalog.load(false)
    }
    ModelCatalog {
        id: catalog; api: picker.api; dialogHost: picker.parent; Layout.fillWidth: true; Layout.preferredHeight: Math.max(180, picker.height - 140)
        onChosen: function(modelId, providerId, baseUrl) { picker.chosen(modelId, providerId, baseUrl); picker.close() }
        onAskAi: function(models, profileSlug, providerId) { picker.askAi(models, profileSlug, providerId) }
    }
}
