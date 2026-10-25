import QtQuick
import QtQuick.Controls
import QtQuick.Layouts

FormDialog {
    id: form
    required property var api
    property bool suggestions: false
    title: "New task"; primaryText: "Create task"
    function start(seed) {
        titleInput.text = seed ? seed.title || "" : ""; bodyInput.text = seed ? seed.body || "" : ""
        access.selected = []; access.budgets = ({}); assignee.currentIndex = 0
        runtime.value = 30; due.text = ""; tags.text = ""; open()
    }
    function submit() {
        if (!titleInput.text.trim()) { error = "Enter a task title."; return }
        if (!access.valid) { error = "Select each allowed profile and enter a positive planning budget for it."; return }
        busy = true; error = ""
        api.request("POST", "/api/task/create", {board: api.board, title: titleInput.text, body: bodyInput.text, allowed_profiles: access.selected, profile_budgets: access.budgets, assignee: assignee.currentIndex > 0 ? assignee.currentText : "", max_runtime_seconds: runtime.value * 60, priority: priority.currentIndex, workspace: workspace.currentIndex === 1 ? "worktree" : "scratch", due_date: due.text, tags: tags.text, cost: 0, effort_hours: 0}, function() { form.busy = false; form.close(); form.api.message = "Task created"; form.api.refresh() }, function(value) { form.busy = false; form.error = value.error }, 100000, "create-task")
    }
    Label { text: "Title"; font.bold: true }
    Field { id: titleInput; objectName: "taskTitle"; Layout.fillWidth: true; placeholderText: "What needs to be done?"; selectByMouse: true; enabled: !form.busy }
    Label { text: "Details & acceptance criteria"; font.bold: true }
    Editor { id: bodyInput; objectName: "taskBody"; Layout.fillWidth: true; Layout.preferredHeight: 140; wrapMode: TextEdit.Wrap; selectByMouse: true; placeholderText: "Context, constraints and what a good result looks like…"; enabled: !form.busy }
    Picker { id: template; Layout.fillWidth: true; model: [{title: "Use a saved template…"}].concat(form.api.data.task_templates || []); textRole: "title"; enabled: !form.busy; onActivated: if (currentIndex > 0) { var item = model[currentIndex]; titleInput.text = item.title; bodyInput.text = item.body || ""; priority.currentIndex = item.priority || 0 } }
    ActionButton { text: "Save as template"; enabled: !form.busy && !!titleInput.text.trim(); onClicked: form.api.request("POST", "/api/templates/save", {title: titleInput.text, body: bodyInput.text, priority: priority.currentIndex, workspace: workspace.currentText}, function() { form.api.refresh(); form.api.message = "Template saved" }) }
    ProfileAccess { id: access; objectName: "taskAccess"; Layout.fillWidth: true; api: form.api; enabled: !form.busy; suggestions: form.suggestions; suggestionText: titleInput.text + " " + bodyInput.text }
    Label { text: "Assign to"; font.bold: true }
    Picker { id: assignee; objectName: "taskAssignee"; Layout.fillWidth: true; model: ["Leave unassigned (starts blocked)"].concat(access.selected); enabled: !form.busy }
    Label { Layout.fillWidth: true; text: "An assigned task may become runnable in Hermes. Leave it unassigned to review it first."; wrapMode: Text.WordWrap; font.pixelSize: 12 }
    Label { text: "Maximum runtime (minutes)"; font.bold: true }
    SpinBox { implicitHeight: 36; id: runtime; from: 1; to: 43200; value: 30; editable: true; enabled: !form.busy }
    Label { text: "Priority"; font.bold: true }
    Picker { id: priority; Layout.fillWidth: true; model: ["0 · Normal", "1 · Low", "2 · Medium", "3 · High", "4 · Urgent"]; enabled: !form.busy }
    Label { text: "Workspace"; font.bold: true }
    Picker { id: workspace; Layout.fillWidth: true; model: ["scratch", "worktree"]; enabled: !form.busy }
    Field { id: due; Layout.fillWidth: true; placeholderText: "Due date: YYYY-MM-DD (optional)"; enabled: !form.busy }
    Field { id: tags; Layout.fillWidth: true; placeholderText: "Tags, separated by commas (optional)"; enabled: !form.busy }
    onSubmitted: submit()
}
