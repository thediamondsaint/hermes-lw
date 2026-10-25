import QtQuick
import QtQuick.Controls
import QtQuick.Layouts

FormDialog {
    id: details
    required property var api
    property var task: ({})
    property var detail: ({})
    property int loadId: 0
    property string board: "default"
    title: "Task details"; primaryText: "Save planning & access"
    function start(item) {
        task = item; board = api.board; detail = ({}); access.selected = (item.allowed_profiles || []).slice(); access.budgets = Object.assign({}, item.profile_budgets || {})
        estimate.text = String(item.estimated_cost || 0); effort.text = String(item.effort_hours || 0); due.text = item.due_date || ""; tags.text = (item.tags || []).join(", "); note.text = item.estimate_note || ""; comment.text = ""
        open(); load()
    }
    function load() {
        var serial = ++loadId
        api.request("POST", "/api/task/detail", {board: board, id: task.id}, function(value) { if (serial === details.loadId) details.detail = value }, function(v) { if (serial === details.loadId) details.error = v.error })
    }
    function action(verb, payload) {
        if (busy) return
        busy = true; error = ""
        api.request("POST", "/api/task/action", Object.assign({board: board, id: task.id, action: verb}, payload || {}), function() { details.busy = false; details.api.refresh(); details.close(); details.api.message = "Task updated" }, function(v) { details.busy = false; details.error = v.error }, 100000, "task-action")
    }
    Label { Layout.fillWidth: true; text: details.task.title || ""; font.pixelSize: 18; font.bold: true; wrapMode: Text.WrapAnywhere }
    Label { Layout.fillWidth: true; text: (details.task.status || "") + " · " + (details.task.assignee || "Unassigned") + " · " + (details.task.id || ""); wrapMode: Text.WordWrap; opacity: 0.75 }
    Editor { Layout.fillWidth: true; Layout.preferredHeight: 140; readOnly: true; text: (details.detail.task || details.task).body || "No task description"; wrapMode: TextEdit.Wrap; selectByMouse: true; textFormat: TextEdit.PlainText }
    Flow {
        Layout.fillWidth: true; spacing: 6
        ActionButton { text: "Complete"; enabled: !details.busy && details.task.status !== "done"; onClicked: details.action("complete") }
        ActionButton { text: details.task.status === "blocked" || details.task.status === "scheduled" ? "Unblock" : "Block"; enabled: !details.busy; onClicked: details.action(details.task.status === "blocked" || details.task.status === "scheduled" ? "unblock" : "block") }
        ActionButton { text: "Promote"; enabled: !details.busy; onClicked: details.action("promote") }
        ActionButton { text: "Schedule"; enabled: !details.busy; onClicked: details.action("schedule") }
        ActionButton { text: "Archive…"; enabled: !details.busy; onClicked: archive.open() }
    }
    RowLayout {
        Layout.fillWidth: true
        Picker { id: assignee; Layout.fillWidth: true; model: ["Unassigned"].concat(details.task.allowed_profiles || []); currentIndex: Math.max(0, model.indexOf(details.task.assignee)); Accessible.name: "Task assignee" }
        ActionButton { text: "Assign"; enabled: !details.busy; onClicked: details.action("assign", {assignee: assignee.currentIndex === 0 ? "none" : assignee.currentText}) }
    }
    RowLayout {
        Layout.fillWidth: true
        Picker { id: priority; Layout.fillWidth: true; model: ["0 · Normal", "1 · Low", "2 · Medium", "3 · High", "4 · Urgent"]; currentIndex: details.task.priority || 0; Accessible.name: "Task priority" }
        ActionButton { text: "Set priority"; enabled: !details.busy; onClicked: details.action("priority", {priority: priority.currentIndex}) }
    }
    ProfileAccess { id: access; Layout.fillWidth: true; api: details.api; enabled: !details.busy }
    Label { text: "Estimated cost (USD)"; font.bold: true }
    Field { id: estimate; Layout.fillWidth: true; placeholderText: "Estimated cost in USD"; validator: DoubleValidator { bottom: 0; locale: "C" } Accessible.name: "Estimated cost" }
    Label { text: "Estimated effort (hours)"; font.bold: true }
    Field { id: effort; Layout.fillWidth: true; placeholderText: "Estimated effort in hours"; validator: DoubleValidator { bottom: 0; locale: "C" } Accessible.name: "Effort hours" }
    Label { text: "Due date (YYYY-MM-DD)"; font.bold: true }
    Field { id: due; Layout.fillWidth: true; placeholderText: "Due date: YYYY-MM-DD"; Accessible.name: "Due date" }
    Label { text: "Tags"; font.bold: true }
    Field { id: tags; Layout.fillWidth: true; placeholderText: "Tags, separated by commas"; Accessible.name: "Task tags" }
    Label { text: "Planning notes"; font.bold: true }
    Editor { id: note; Layout.fillWidth: true; Layout.preferredHeight: 70; placeholderText: "Planning notes"; wrapMode: TextEdit.Wrap }
    Label { text: "Comments"; font.bold: true }
    Repeater { model: details.detail.comments || []
        Label { required property var modelData; Layout.fillWidth: true; text: (modelData.author || "") + ": " + modelData.body; wrapMode: Text.WrapAnywhere; textFormat: Text.PlainText }
    }
    Editor { id: comment; objectName: "taskComment"; Layout.fillWidth: true; Layout.preferredHeight: 75; placeholderText: "Write a progress note or handoff…"; wrapMode: TextEdit.Wrap }
    ActionButton { objectName: "addTaskComment"; text: "Add comment"; enabled: !details.busy && !!comment.text.trim(); onClicked: {
        details.busy = true
        details.api.request("POST", "/api/task/comment", {board: details.board, id: details.task.id, body: comment.text}, function() { details.busy = false; comment.text = ""; details.load() }, function(v) { details.busy = false; details.error = v.error }, 30000, "comment")
    } }
    Label { text: "Add dependency"; font.bold: true }
    Picker { id: dependency; Layout.fillWidth: true; model: details.api.tasks.filter(function(t) { return t.id !== details.task.id }); textRole: "title"; valueRole: "id" }
    ActionButton { text: "Link: this task must finish first"; enabled: !details.busy && dependency.currentIndex >= 0; onClicked: {
        details.busy = true
        details.api.request("POST", "/api/task/link", {board: details.board, parent_id: details.task.id, child_id: dependency.currentValue}, function() { details.busy = false; details.load() }, function(v) { details.busy = false; details.error = v.error }, 30000, "dependency")
    } }
    onSubmitted: {
        if (!access.valid) { error = "Select allowed profiles and give each a positive planning budget."; return }
        busy = true
        api.request("POST", "/api/task/estimate", {board: board, id: task.id, allowed_profiles: access.selected, profile_budgets: access.budgets, cost: Number(estimate.text), effort_hours: Number(effort.text), due_date: due.text, tags: tags.text, note: note.text}, function() { details.busy = false; details.close(); details.api.refresh(); details.api.message = "Task planning and access saved" }, function(v) { details.busy = false; details.error = v.error }, 30000, "task-policy")
    }
    FormDialog { id: archive; parent: details.parent; title: "Archive task"; primaryText: "Archive"
        Label { Layout.fillWidth: true; text: "Archive “" + (details.task.title || "") + "”?"; wrapMode: Text.WordWrap }
        onSubmitted: { close(); details.action("archive") }
    }
}
