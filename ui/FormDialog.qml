import QtQuick
import QtQuick.Controls
import QtQuick.Layouts

Dialog {
    id: dialog
    default property alias fields: form.data
    property var paletteSource: parent
    property var viewport: scroll.contentItem
    palette: paletteSource.palette
    font.pixelSize: 13
    property string error: ""
    property string primaryText: "Save"
    property bool busy: false
    property bool showSubmit: true
    property int preferredWidth: 620
    property alias scroll: scroll
    signal submitted()
    modal: true; dim: true
    x: Math.round((parent.width - width) / 2); y: Math.round((parent.height - height) / 2)
    width: Math.max(280, Math.min(preferredWidth, parent.width - 24))
    height: Math.min(parent.height - 24, Math.max(230, form.implicitHeight + 135))
    padding: 16
    closePolicy: busy ? Popup.NoAutoClose : Popup.CloseOnEscape
    header: Rectangle {
        implicitHeight: 42
        gradient: Gradient { GradientStop { position: 0; color: "#285ba5" } GradientStop { position: 1; color: "#173966" } }
        Label { anchors.left: parent.left; anchors.leftMargin: 14; anchors.right: closeButton.left; anchors.rightMargin: 8; anchors.verticalCenter: parent.verticalCenter; text: dialog.title; font.bold: true; font.pixelSize: 14; color: "white"; elide: Text.ElideRight }
        ActionButton { id: closeButton; objectName: "dialogClose"; anchors.right: parent.right; anchors.rightMargin: 7; anchors.verticalCenter: parent.verticalCenter; width: 30; height: 28; text: "×"; danger: true; enabled: !dialog.busy; onClicked: dialog.close(); Accessible.name: "Close " + dialog.title }
    }
    background: Rectangle { color: dialog.palette.window; border.color: "#577da7"; radius: 4 }
    contentItem: ScrollView {
        id: scroll; clip: true; contentWidth: availableWidth
        ScrollBar.horizontal.policy: ScrollBar.AlwaysOff
        ScrollBar.vertical: ScrollBar {
            policy: ScrollBar.AsNeeded; active: true; implicitWidth: 10
            contentItem: Rectangle { implicitWidth: 8; implicitHeight: 32; radius: 3; color: "#708eae" }
            background: Rectangle { color: dialog.palette.base; radius: 3 }
        }
        ColumnLayout {
            id: form; width: Math.max(0, scroll.availableWidth - 12); spacing: 10
            Label { Layout.fillWidth: true; visible: dialog.error.length > 0; text: dialog.error; color: "#ed9292"; wrapMode: Text.WrapAnywhere; font.pixelSize: 13; padding: 8; background: Rectangle { color: "#402a30"; radius: 3 } }
        }
    }
    footer: DialogButtonBox {
        padding: 12; spacing: 8
        ActionButton { objectName: "dialogCancel"; text: dialog.showSubmit ? "Cancel" : "Close"; enabled: !dialog.busy; onClicked: dialog.close(); DialogButtonBox.buttonRole: DialogButtonBox.RejectRole }
        ActionButton { objectName: "dialogSubmit"; visible: dialog.showSubmit; text: dialog.busy ? "Working…" : dialog.primaryText; primary: true; enabled: !dialog.busy; onClicked: dialog.submitted(); DialogButtonBox.buttonRole: DialogButtonBox.ActionRole }
    }
    onErrorChanged: if (visible && error && viewport) viewport.contentY = 0
    onOpened: { error = ""; viewport.contentY = 0 }
}
