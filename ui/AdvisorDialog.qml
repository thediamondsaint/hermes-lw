import QtQuick
import QtQuick.Controls
import QtQuick.Layouts

FormDialog {
    id: advisor
    required property var api
    property var candidates: []
    property string profileSlug: "default"
    property string providerId: "openrouter"
    property string modelId: ""
    property var recommendations: []
    property string summary: ""
    signal findModel(string id)
    title: "Ask AI which model to use"; primaryText: "Ask AI (paid)"
    function start(models, profile, provider) {
        candidates = models; profileSlug = profile; providerId = provider
        recommendations = []; summary = ""; question.text = ""
        var options = models.filter(function(m) { return m.price_known === true && (m.inputs || []).indexOf("text") >= 0 && (m.outputs || []).indexOf("text") >= 0 })
        var current = api.profile(profile).model
        modelId = options.some(function(m) { return m.id === current }) ? current : ""
        open()
    }
    Label { Layout.fillWidth: true; text: "Describe your goal and budget. Choose the model that will write this recommendation; this is a paid request when that provider charges."; wrapMode: Text.WordWrap }
    Editor { id: question; objectName: "advisorQuestion"; Layout.fillWidth: true; Layout.preferredHeight: 100; placeholderText: "e.g. Audit a GitHub repo for bugs. I need careful reasoning at low cost."; wrapMode: TextEdit.Wrap; selectByMouse: true }
    Label { Layout.fillWidth: true; text: "Recommendation model: " + (advisor.modelId || "Choose a priced text model"); wrapMode: Text.WrapAnywhere; font.bold: true }
    ActionButton { text: "Choose recommendation model…"; enabled: !advisor.busy; onClicked: picker.choose(advisor.profileSlug, advisor.providerId, "", true) }
    Label { Layout.fillWidth: true; text: "Credentials: " + advisor.profileSlug + " · " + advisor.providerId + ". Candidates: up to 30 matching models. Actual usage and provider retries determine cost."; wrapMode: Text.WordWrap; opacity: 0.8 }
    Label { visible: advisor.busy; text: "Waiting for the model. Do not start another request."; wrapMode: Text.WordWrap; Layout.fillWidth: true }
    Label { Layout.fillWidth: true; visible: advisor.summary.length > 0; text: advisor.summary; wrapMode: Text.WordWrap }
    Repeater { model: advisor.recommendations
        Frame { required property var modelData; Layout.fillWidth: true
            contentItem: ColumnLayout {
                Label { Layout.fillWidth: true; text: modelData.id; font.bold: true; wrapMode: Text.WrapAnywhere }
                Label { Layout.fillWidth: true; text: modelData.reason + "\n" + (modelData.tradeoff || ""); wrapMode: Text.WordWrap }
                ActionButton { text: "Find this model"; onClicked: { advisor.findModel(modelData.id); advisor.close() } }
            }
        }
    }
    onSubmitted: {
        if (!question.text.trim() || !modelId) { error = "Enter your goal and choose a recommendation model first."; return }
        busy = true; error = ""
        api.request("POST", "/api/models/recommend", {question: question.text, profile: profileSlug, provider: providerId, model: modelId, candidates: candidates.slice(0,30)}, function(value) {
            advisor.busy = false; advisor.summary = value.summary || ""; advisor.recommendations = value.recommendations || []
        }, function(value) { advisor.busy = false; advisor.error = value.error }, 195000, "advisor")
    }
    ModelPicker {
        id: picker; parent: advisor.parent; api: advisor.api
        onChosen: function(modelId, providerId) { if (providerId !== advisor.providerId) { advisor.error = "Choose the recommendation model from " + advisor.providerId + ", the provider of these candidates."; return }; advisor.modelId = modelId }
    }
}
