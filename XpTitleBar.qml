import QtQuick

Rectangle {
  id: bar
  property string caption: "Window"
  property bool darkMode: false
  signal closeRequested()

  width: parent ? parent.width : 400
  height: 28
  gradient: Gradient {
    GradientStop { position: 0; color: bar.darkMode ? "#405c85" : "#5b91e8" }
    GradientStop { position: 1; color: bar.darkMode ? "#233b60" : "#1553b5" }
  }

  Rectangle {
    x: 6; y: 5; width: 18; height: 18
    color: "#245ed0"; border.color: "#dceaff"
    Text { anchors.centerIn: parent; text: "H"; color: "white"; font.pixelSize: 11; font.bold: true }
  }
  Text {
    anchors.left: parent.left; anchors.leftMargin: 31
    anchors.right: closeButton.left; anchors.rightMargin: 8
    anchors.verticalCenter: parent.verticalCenter
    text: bar.caption; color: "white"; font.pixelSize: 11; font.bold: true
    elide: Text.ElideRight
  }
  Rectangle {
    id: closeButton
    anchors.right: parent.right; anchors.rightMargin: 5
    anchors.verticalCenter: parent.verticalCenter
    width: 24; height: 20
    color: closeHover.containsMouse ? "#e34b3f" : "#c44c45"
    border.color: closeHover.containsMouse ? "#ffe3d6" : "#f3b5a7"
    Text { anchors.centerIn: parent; text: "×"; color: "white"; font.pixelSize: 17; font.bold: true; y: -1 }
    MouseArea {
      id: closeHover; anchors.fill: parent; hoverEnabled: true
      onClicked: bar.closeRequested()
    }
  }
}
