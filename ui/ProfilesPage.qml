import QtQuick
import QtQuick.Controls
import QtQuick.Layouts

ColumnLayout {
    id: page
    required property var api
    required property var host
    property alias editor: editor
    RowLayout {
        Layout.fillWidth: true
        Label { text: "Profiles"; font.pixelSize: 21; font.bold: true; Layout.fillWidth: true }
        ActionButton { text: "New profile"; enabled: page.api.connected && !page.api.busy("refresh"); primary: true; objectName: "newProfile"; onClicked: editor.startCreate("default") }
    }
    Field { id: search; Layout.fillWidth: true; placeholderText: "Search profiles…"; selectByMouse: true }
    ListView {
        id: list; Layout.fillWidth: true; Layout.fillHeight: true; clip: true; spacing: 10
        model: page.api.profiles.filter(function(p) { return (p.slug + " " + p.model + " " + p.description).toLowerCase().indexOf(search.text.toLowerCase()) >= 0 })
        delegate: Frame {
            id: card; required property var modelData; width: list.width; padding: 14; height: body.implicitHeight + 28
            ColumnLayout {
                id: body; width: card.availableWidth; spacing: 8
                Label { Layout.fillWidth: true; text: card.modelData.slug + (card.modelData.manager ? " · Manager" : "") + (card.modelData.paused ? " · Paused" : ""); font.pixelSize: 16; font.bold: true; wrapMode: Text.WrapAnywhere }
                Label { Layout.fillWidth: true; text: card.modelData.provider + " / " + card.modelData.model; wrapMode: Text.WrapAnywhere }
                Label { Layout.fillWidth: true; text: card.modelData.description || (card.modelData.personality || "No personality set").slice(0,160); wrapMode: Text.WordWrap; maximumLineCount: 3; elide: Text.ElideRight; opacity: 0.75 }
                Flow {
                    Layout.fillWidth: true; spacing: 6
                    ActionButton { text: "Edit"; primary: true; objectName: "editProfile_" + card.modelData.slug; onClicked: { page.api.selectedProfile = card.modelData.slug; editor.startEdit(card.modelData) } }
                    ActionButton { text: "Clone"; onClicked: editor.startCreate(card.modelData.slug) }
                    ActionButton { id: moreButton; text: "More…"; onClicked: { var at = moreButton.mapToItem(card, 0, moreButton.height); moreMenu.x = at.x; moreMenu.y = at.y; moreMenu.open() } }
                }
            }
            Menu { palette: page.host.palette;
                id: moreMenu
                MenuItem { text: card.modelData.paused ? "Resume profile" : "Pause new assignments"; enabled: !page.api.busy("manage-profile"); onTriggered: page.api.mutate("/api/profile/manage", {slug: card.modelData.slug, action: "pause"}, null, null, 30000, "manage-profile") }
                MenuItem { text: card.modelData.manager ? "Clear manager" : "Set as manager"; enabled: !page.api.busy("manage-profile"); onTriggered: page.api.mutate("/api/profile/manage", {slug: card.modelData.slug, action: "manager"}, null, null, 30000, "manage-profile") }
                MenuItem { text: "Tools & apps…"; onTriggered: tools.start(card.modelData.slug) }
                MenuSeparator {}
                MenuItem { text: "Delete profile…"; enabled: card.modelData.slug !== "default"; onTriggered: { deletion.slug = card.modelData.slug; deletion.open() } }
            }
        }
        ScrollBar.vertical: ScrollBar {}
        Label { anchors.centerIn: parent; text: "No matching profiles"; visible: list.count === 0 }
    }
    Label { Layout.fillWidth: true; text: "Pause blocks new Hermes LW assignments. It does not cancel already-running work."; wrapMode: Text.WordWrap; opacity: 0.7; font.pixelSize: 12 }
    ProfileForm { id: editor; parent: page.host; api: page.api; objectName: "profileForm" }
    ToolsDialog { id: tools; parent: page.host; api: page.api }
    FormDialog {
        id: deletion; parent: page.host; property string slug: ""; title: "Delete profile"; primaryText: "Delete profile"
        Label { Layout.fillWidth: true; text: "Delete " + deletion.slug + " and its profile files? This cannot be undone."; wrapMode: Text.WordWrap }
        onSubmitted: { busy = true; page.api.mutate("/api/profile/delete", {slug: slug}, function() { deletion.busy = false; deletion.close() }, function(v) { deletion.busy = false; deletion.error = v.error }) }
    }
}
