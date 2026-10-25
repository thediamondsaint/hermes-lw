import QtQuick
import QtQuick.Controls
import QtQuick.Layouts

ColumnLayout {
    id: access
    required property var api
    property var selected: []
    property var budgets: ({})
    property string suggestionText: ""
    property bool suggestions: false
    readonly property bool valid: selected.length > 0 && selected.every(function(slug) { return Number(access.budgets[slug]) > 0 && isFinite(Number(access.budgets[slug])) && !access.api.profile(slug).paused })
    spacing: 8
    Label { text: "Allowed profiles & planning budgets"; font.bold: true; Layout.fillWidth: true; wrapMode: Text.WordWrap }
    Label { Layout.fillWidth: true; text: "Only profiles you check can be assigned through Hermes LW. No profile is selected automatically."; wrapMode: Text.WordWrap; font.pixelSize: 12 }
    Repeater { model: access.api.profiles
        ColumnLayout {
            required property var modelData; Layout.fillWidth: true; spacing: 3
            Choice {
                Layout.fillWidth: true
                text: modelData.slug + (modelData.paused ? " (paused)" : "") + (access.suggestions && access.suggestionText.toLowerCase().split(/\W+/).some(function(w) { return w.length > 3 && (modelData.slug + " " + modelData.description + " " + modelData.personality).toLowerCase().indexOf(w) >= 0 }) ? " · suggested" : "")
                checked: access.selected.indexOf(modelData.slug) >= 0; enabled: !modelData.paused
                objectName: "allowProfile_" + modelData.slug
                onClicked: { var selected = access.selected.slice(); if (checked) selected.push(modelData.slug); else selected = selected.filter(function(s) { return s !== modelData.slug }); access.selected = selected }
            }
            Field { Layout.fillWidth: true; visible: access.selected.indexOf(modelData.slug) >= 0; placeholderText: "Planning budget in USD (required, greater than 0)"; text: access.budgets[modelData.slug] === undefined ? "" : String(access.budgets[modelData.slug]); validator: DoubleValidator { bottom: 0; locale: "C" } objectName: "budget_" + modelData.slug
                onTextEdited: { var budgets = Object.assign({}, access.budgets); budgets[modelData.slug] = Number(text); access.budgets = budgets }
            }
        }
    }
    Label { Layout.fillWidth: true; text: "Dollar amounts are planning metadata, not hard spend caps. Provider-side key limits enforce spending. Other Hermes clients can bypass this app’s allowlist."; wrapMode: Text.WordWrap; font.pixelSize: 12; opacity: 0.8 }
}
