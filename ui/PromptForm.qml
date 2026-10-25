import QtQuick
import QtQuick.Controls
import QtQuick.Layouts

FormDialog {
    id: form
    required property var api
    property string promptId: ""
    title: promptId ? "Edit prompt" : "New prompt"; primaryText: "Save prompt"
    function start(p) { promptId = p ? p.id || "" : ""; name.text = p ? p.title || "" : ""; body.text = p ? p.body || "" : ""; favorite.checked = p ? !!p.favorite : true; open() }
    Field { id: name; Layout.fillWidth: true; placeholderText: "Prompt name" }
    Editor { id: body; Layout.fillWidth: true; Layout.preferredHeight: 260; placeholderText: "Reusable instructions…"; wrapMode: TextEdit.Wrap; selectByMouse: true }
    Choice { id: favorite; text: "Favorite prompt"; checked: true }
    onSubmitted: { busy = true; api.mutate("/api/prompt/save", {id: promptId, title: name.text, body: body.text, favorite: favorite.checked}, function() { form.busy = false; form.close() }, function(v) { form.busy = false; form.error = v.error }, 30000, "save-prompt") }
}
