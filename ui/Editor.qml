import QtQuick
import QtQuick.Controls

ScrollView {
    id: control
    property alias text: editor.text
    property alias placeholderText: editor.placeholderText
    property alias readOnly: editor.readOnly
    property alias selectByMouse: editor.selectByMouse
    property alias wrapMode: editor.wrapMode
    property alias textFormat: editor.textFormat
    implicitWidth: 240; implicitHeight: 140
    contentWidth: availableWidth
    clip: true
    ScrollBar.horizontal.policy: ScrollBar.AlwaysOff
    ScrollBar.vertical: ScrollBar { policy: ScrollBar.AsNeeded; active: true }
    TextArea {
        id: editor
        implicitWidth: 240
        implicitHeight: Math.max(control.availableHeight, contentHeight + topPadding + bottomPadding)
        width: control.availableWidth
        wrapMode: TextEdit.Wrap
        selectByMouse: true
        padding: 10
    }
}
