import QtQuick
import QtQuick.Controls
import QtQuick.Layouts

ColumnLayout {
    id: page
    required property var api
    required property var host
    property alias creator: creator
    property alias details: details
    property alias projectForm: projectForm
    property bool filters: false
    property var statuses: [
        {name: "Waiting", states: ["triage", "todo", "ready", "scheduled"], color: "#699bce"},
        {name: "Working", states: ["running", "review"], color: "#c4a766"},
        {name: "Blocked", states: ["blocked"], color: "#c17b7b"},
        {name: "Done", states: ["done"], color: "#7caf96"}
    ]
    RowLayout {
        Layout.fillWidth: true
        Label { text: "Tasks"; Layout.fillWidth: true; font.pixelSize: 21; font.bold: true }
        Choice { id: suggest; text: "AI/Profiles"; ToolTip.visible: hovered; ToolTip.text: "Show local profile suggestions. Profiles are never auto-selected and this makes no model request." }
        ActionButton { text: "New task"; enabled: page.api.connected && !page.api.busy("refresh"); primary: true; objectName: "newTask"; onClicked: creator.start(null) }
    }
    RowLayout {
        Layout.fillWidth: true
        Picker { id: project; Layout.fillWidth: true; model: page.api.projects; textRole: "name"; valueRole: "slug"; currentIndex: Math.max(0, page.api.projects.map(function(p) { return p.slug }).indexOf(page.api.board)); onActivated: page.api.refresh(currentValue); Accessible.name: "Project" }
        ActionButton { text: "Project…"; onClicked: projectMenu.popup() }
        ActionButton { text: page.filters ? "Hide filters" : "Filters"; onClicked: page.filters = !page.filters }
    }
    Field { id: search; Layout.fillWidth: true; placeholderText: "Search tasks, tags or assignees…"; selectByMouse: true; objectName: "taskSearch" }
    RowLayout {
        visible: page.filters; Layout.fillWidth: true
        Picker { id: assigneeFilter; Layout.fillWidth: true; model: ["All profiles"].concat(page.api.profiles.map(function(p) { return p.slug })); Accessible.name: "Filter by assignee" }
        Picker { id: savedView; Layout.fillWidth: true; model: [{name: "Saved views…"}].concat((page.api.data.saved_views || []).filter(function(v) { return v.board === page.api.board })); textRole: "name"; onActivated: if (currentIndex > 0) { search.text = model[currentIndex].query || ""; assigneeFilter.currentIndex = Math.max(0, assigneeFilter.model.indexOf(model[currentIndex].assignee || "All profiles")) } }
        ActionButton { text: "Save view"; onClicked: saveView.open() }
    }
    Label { Layout.fillWidth: true; text: page.api.tasks.length + " tasks · " + page.api.tasks.filter(function(t) { return t.status === "blocked" }).length + " blocked"; font.pixelSize: 12; opacity: 0.75 }
    Flickable {
        id: board; Layout.fillWidth: true; Layout.fillHeight: true; clip: true
        contentWidth: columns.implicitWidth; contentHeight: height; flickableDirection: Flickable.HorizontalFlick; boundsBehavior: Flickable.StopAtBounds
        ScrollBar.horizontal: ScrollBar { policy: board.contentWidth > board.width ? ScrollBar.AlwaysOn : ScrollBar.AlwaysOff }
        Row {
            id: columns; spacing: 10; height: board.height - 14
            Repeater { model: page.statuses
                Frame {
                    id: column; required property var modelData
                    width: Math.max(230, (board.width - 30) / 4); height: columns.height; padding: 10
                    ColumnLayout {
                        anchors.fill: parent; spacing: 10
                        RowLayout {
                            Layout.fillWidth: true
                            Rectangle { width: 7; height: 18; color: column.modelData.color; radius: 2 }
                            Label { text: column.modelData.name; font.bold: true; Layout.fillWidth: true }
                            Label { text: String(cards.count); opacity: 0.7 }
                        }
                        ListView {
                            id: cards; Layout.fillWidth: true; Layout.fillHeight: true; clip: true; spacing: 8
                            model: page.api.tasks.filter(function(t) {
                                var found = (t.title + " " + (t.body || "") + " " + (t.assignee || "") + " " + (t.tags || []).join(" ")).toLowerCase().indexOf(search.text.toLowerCase()) >= 0
                                return column.modelData.states.indexOf(t.status) >= 0 && found && (assigneeFilter.currentIndex === 0 || t.assignee === assigneeFilter.currentText)
                            })
                            delegate: ItemDelegate {
                                id: card; required property var modelData
                                width: cards.width; padding: 12; implicitHeight: cardText.implicitHeight + 24
                                objectName: "task_" + modelData.id
                                background: Rectangle { radius: 4; color: card.hovered ? card.palette.light : card.palette.base; border.color: card.palette.mid }
                                contentItem: ColumnLayout {
                                    id: cardText; spacing: 8
                                    Label { Layout.fillWidth: true; text: card.modelData.title; font.bold: true; wrapMode: Text.WrapAnywhere; maximumLineCount: 4; elide: Text.ElideRight }
                                    Label { Layout.fillWidth: true; text: card.modelData.status + " · " + (card.modelData.assignee || "Unassigned"); wrapMode: Text.WordWrap; opacity: 0.8; font.pixelSize: 12 }
                                    Label { Layout.fillWidth: true; text: "P" + Number(card.modelData.priority || 0) + " · " + page.api.money(card.modelData.estimated_cost) + (card.modelData.due_date ? " · due " + card.modelData.due_date : ""); wrapMode: Text.WordWrap; font.pixelSize: 12 }
                                }
                                onClicked: details.start(modelData)
                            }
                            ScrollBar.vertical: ScrollBar {}
                            Label { anchors.centerIn: parent; text: "No tasks"; opacity: 0.5; visible: cards.count === 0 }
                        }
                    }
                }
            }
        }
    }
    Menu { palette: page.host.palette;
        id: projectMenu
        MenuItem { text: "New project…"; onTriggered: projectForm.start(null) }
        MenuItem { text: "Edit project…"; onTriggered: projectForm.start(page.api.data.project || {}) }
        MenuItem { text: "Export to Downloads"; onTriggered: page.api.mutate("/api/project/export", {slug: page.api.board}, function(v) { page.api.message = "Exported: " + v.path }) }
        MenuItem { text: "Archive project…"; enabled: page.api.board !== "default"; onTriggered: archiveProject.open() }
    }
    TaskForm { id: creator; objectName: "taskForm"; parent: page.host; api: page.api; suggestions: suggest.checked }
    TaskDetails { id: details; parent: page.host; api: page.api }
    ProjectForm { id: projectForm; parent: page.host; api: page.api }
    FormDialog { id: archiveProject; parent: page.host; title: "Archive project"; primaryText: "Archive"
        Label { Layout.fillWidth: true; text: "Archive " + page.api.board + "?"; wrapMode: Text.WordWrap }
        onSubmitted: { busy = true; page.api.mutate("/api/project/archive", {slug: page.api.board}, function() { archiveProject.busy = false; archiveProject.close(); page.api.board = "default"; page.api.refresh("default") }, function(v) { archiveProject.busy = false; archiveProject.error = v.error }) }
    }
    FormDialog { id: saveView; parent: page.host; title: "Save task view"; primaryText: "Save view"
        Field { id: viewName; Layout.fillWidth: true; placeholderText: "View name" }
        onSubmitted: { busy = true; page.api.mutate("/api/views/save", {name: viewName.text, board: page.api.board, query: search.text, assignee: assigneeFilter.currentIndex === 0 ? "all" : assigneeFilter.currentText, status: "all"}, function() { saveView.busy = false; saveView.close() }, function(v) { saveView.busy = false; saveView.error = v.error }) }
    }
}
