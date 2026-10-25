import QtQuick
import QtQuick.Controls
import QtQuick.Layouts

FormDialog {
    id: form
    required property var api
    property string connectionId: ""
    title: connectionId ? "Edit connection" : "Add connection"; primaryText: "Save connection"
    function start(c) {
        connectionId = c ? c.id : ""; name.text = c ? c.name : ""; kind.currentIndex = c && c.kind === "https" ? 1 : 0
        host.text = c ? c.host || "" : ""; sshPort.value = c ? c.ssh_port || 22 : 22; remotePort.value = c ? c.remote_port || 18731 : 18731
        url.text = c ? c.url || "" : ""; token.text = ""; open()
    }
    Label { text: "Connection name"; font.bold: true }
    Field { id: name; Layout.fillWidth: true; placeholderText: "Connection name, e.g. Hermes VPS"; objectName: "connectionName" }
    Label { text: "Connection type"; font.bold: true }
    Picker { id: kind; Layout.fillWidth: true; model: ["SSH / VPS", "HTTPS / cloud gateway"] }
    Label { Layout.fillWidth: true; text: kind.currentIndex === 0 ? "Uses your existing OpenSSH config and keys. Hermes LW must be running on the remote machine." : "Uses a remote Hermes LW HTTPS gateway. Its access token is stored privately by the local backend."; wrapMode: Text.WordWrap }
    Field { id: host; visible: kind.currentIndex === 0; Layout.fillWidth: true; placeholderText: "SSH alias or user@host" }
    Label { visible: kind.currentIndex === 0; text: "SSH port" }
    SpinBox { implicitHeight: 36; id: sshPort; visible: kind.currentIndex === 0; from: 1; to: 65535; value: 22; editable: true }
    Label { visible: kind.currentIndex === 0; text: "Remote Hermes LW port" }
    SpinBox { implicitHeight: 36; id: remotePort; visible: kind.currentIndex === 0; from: 1024; to: 65535; value: 18731; editable: true }
    Field { id: url; visible: kind.currentIndex === 1; Layout.fillWidth: true; placeholderText: "https://hermes.example.com" }
    Field { id: token; visible: kind.currentIndex === 1; Layout.fillWidth: true; echoMode: TextInput.Password; placeholderText: form.connectionId ? "Gateway token (blank keeps existing)" : "Gateway token" }
    onSubmitted: {
        busy = true
        api.request("POST", "/api/connections/save", {id: connectionId, name: name.text, kind: kind.currentIndex === 0 ? "ssh" : "https", host: host.text, ssh_port: sshPort.value, remote_port: remotePort.value, url: url.text, token: token.text}, function() { form.busy = false; token.text = ""; form.close(); form.api.loadConnections(); form.api.message = "Connection saved. Select its tab to connect." }, function(v) { form.busy = false; form.error = v.error }, 30000, "save-connection", true)
    }
}
