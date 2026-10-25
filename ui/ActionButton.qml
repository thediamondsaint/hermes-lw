import QtQuick
import QtQuick.Controls

Button {
    id: control
    property bool primary: false
    property bool danger: false
    implicitHeight: 36
    leftPadding: 12; rightPadding: 12; topPadding: 8; bottomPadding: 8
    font.pixelSize: 13
    contentItem: Text {
        text: control.text; font: control.font
        color: !control.enabled ? control.palette.disabled.buttonText : control.primary || control.danger ? "white" : control.palette.buttonText
        horizontalAlignment: Text.AlignHCenter; verticalAlignment: Text.AlignVCenter
        elide: Text.ElideRight
    }
    background: Rectangle {
        radius: 3
        color: control.danger ? "#a43d42" : control.primary ? (control.down ? "#194a90" : "#2862ae") : control.down ? control.palette.mid : control.hovered ? control.palette.light : control.palette.button
        border.color: control.activeFocus ? "#6caaef" : control.palette.mid
        border.width: control.activeFocus ? 2 : 1
        opacity: control.enabled ? 1 : 0.65
    }
}
