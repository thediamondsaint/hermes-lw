import QtQuick
import QtQuick.Controls

CheckBox {
    id: control
    implicitHeight: Math.max(34, contentItem.implicitHeight + 8)
    topPadding: 4; bottomPadding: 4
    font.pixelSize: 13
    contentItem: Label {
        text: control.text; font: control.font
        leftPadding: control.indicator.width + control.spacing
        verticalAlignment: Text.AlignVCenter
        wrapMode: Text.Wrap
    }
}
