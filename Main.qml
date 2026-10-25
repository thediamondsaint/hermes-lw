import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import Quickshell
import "ui"

ShellRoot {
    id: root
    AppState { id: app }
    Component.onCompleted: app.initialize()
    FloatingWindow {
        id: win
        title: "Hermes LW"
        visible: true
        implicitWidth: 1180; implicitHeight: 800
        minimumSize: Qt.size(480, 360)
        color: app.dark ? "#171c24" : "#ece9d8"
        Pane {
            id: shell; anchors.fill: parent; padding: 0
            palette.window: app.dark ? "#202731" : "#ece9d8"
            palette.base: app.dark ? "#171d26" : "#ffffff"
            palette.text: app.dark ? "#e8eef7" : "#182235"
            palette.windowText: app.dark ? "#e8eef7" : "#182235"
            palette.button: app.dark ? "#303c4d" : "#f4f1e5"
            palette.buttonText: app.dark ? "#e8eef7" : "#182235"
            palette.mid: app.dark ? "#4c5d72" : "#a7a391"
            palette.light: app.dark ? "#3c4e66" : "#ffffff"
            palette.highlight: "#2c66b2"
            palette.highlightedText: "#ffffff"
            palette.placeholderText: app.dark ? "#93a0b2" : "#626b75"
            font.pixelSize: 13
            background: Rectangle { color: shell.palette.window }
            ColumnLayout {
                anchors.fill: parent; spacing: 0
                Rectangle {
                    Layout.fillWidth: true; implicitHeight: 42
                    gradient: Gradient { GradientStop { position: 0; color: "#2c62ae" } GradientStop { position: 1; color: "#193c6c" } }
                    Label { anchors.left: parent.left; anchors.leftMargin: 16; anchors.verticalCenter: parent.verticalCenter; text: "Hermes LW"; color: "white"; font.bold: true; font.pixelSize: 16 }
                    Label { anchors.centerIn: parent; visible: parent.width > 620; text: app.connection().name || "Local Hermes"; color: "#dceaff"; font.pixelSize: 12 }
                    ActionButton { anchors.right: parent.right; anchors.rightMargin: 8; anchors.verticalCenter: parent.verticalCenter; width: 30; height: 28; text: "×"; danger: true; onClicked: Qt.quit(); Accessible.name: "Close Hermes LW" }
                }
                RowLayout {
                    Layout.fillWidth: true; Layout.margins: 10; spacing: 8
                    ScrollView {
                        Layout.fillWidth: true; implicitHeight: 38; contentHeight: availableHeight; clip: true
                        ScrollBar.vertical.policy: ScrollBar.AlwaysOff
                        Row {
                            spacing: 4
                            Repeater { model: app.connections
                                ActionButton { required property var modelData; text: modelData.name || modelData.id; primary: app.connectionId === modelData.id; onClicked: app.activate(modelData.id); objectName: "connection_" + modelData.id }
                            }
                        }
                    }
                    ActionButton { text: "+"; implicitWidth: 38; Accessible.name: "Manage connections"; onClicked: { app.page = "Settings"; settingsPage.section = 1 } }
                    ActionButton { text: "Refresh"; enabled: !app.busy("refresh"); onClicked: app.refresh(); objectName: "refreshButton" }
                }
                TabBar {
                    id: navigation; Layout.fillWidth: true; currentIndex: ["Tasks", "Profiles", "Models", "Settings"].indexOf(app.page)
                    Repeater { model: ["Tasks", "Profiles", "Models", "Settings"]
                        TabButton { implicitHeight: 38; required property string modelData; text: modelData; onClicked: app.page = modelData; objectName: "page_" + modelData }
                    }
                }
                Frame {
                    Layout.fillWidth: true; Layout.margins: 10; visible: app.error.length > 0; padding: 10
                    background: Rectangle { color: app.dark ? "#402a30" : "#ffdedb"; border.color: "#b96363"; radius: 3 }
                    RowLayout { anchors.fill: parent
                        Label { Layout.fillWidth: true; text: app.error; wrapMode: Text.WrapAnywhere; color: app.dark ? "#ffb4b4" : "#7d2020"; maximumLineCount: 5; elide: Text.ElideRight; objectName: "globalError" }
                        ActionButton { text: "Dismiss"; onClicked: app.error = "" }
                    }
                }
                StackLayout {
                    Layout.fillWidth: true; Layout.fillHeight: true; Layout.margins: 12
                    currentIndex: navigation.currentIndex
                    TasksPage { id: tasksPage; api: app; host: shell }
                    ProfilesPage { id: profilesPage; api: app; host: shell }
                    ModelsPage { id: modelsPage; api: app; host: shell }
                    SettingsPage { id: settingsPage; api: app; host: shell }
                }
                RowLayout {
                    Layout.fillWidth: true; Layout.margins: 10
                    Label { text: app.pending ? "Working · " + app.pending + " request(s)" : app.connected ? "Connected" : "Connection unavailable"; color: app.connected ? shell.palette.text : "#e79479"; font.pixelSize: 12 }
                    Label { Layout.fillWidth: true; text: app.message; elide: Text.ElideRight; font.pixelSize: 12 }
                    ActionButton { text: app.dark ? "Light" : "Dark"; implicitHeight: 28; onClicked: app.request("POST", "/api/theme", {theme: app.dark ? "light" : "dark"}, function(value) { app.dark = value.theme === "dark" }) }
                }
            }
        }
    }
}
