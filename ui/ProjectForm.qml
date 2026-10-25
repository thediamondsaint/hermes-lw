import QtQuick
import QtQuick.Controls
import QtQuick.Layouts

FormDialog {
    id: form
    required property var api
    property string slug: ""
    title: slug ? "Edit project" : "New project"; primaryText: "Save project"
    function start(p) { slug = p ? p.slug || "" : ""; name.text = p ? p.name || "" : ""; description.text = p ? p.description || "" : ""; budget.text = p ? String(p.budget || 0) : ""; due.text = p ? p.due_date || "" : ""; owner.text = p ? p.owner || "" : ""; open() }
    Field { id: name; Layout.fillWidth: true; placeholderText: "Project name"; objectName: "projectName" }
    Label { Layout.fillWidth: true; text: "Project ID: " + (form.slug || form.api.slug(name.text) || "enter a name"); wrapMode: Text.WrapAnywhere }
    Editor { id: description; Layout.fillWidth: true; Layout.preferredHeight: 100; placeholderText: "Description"; wrapMode: TextEdit.Wrap }
    Field { id: owner; Layout.fillWidth: true; placeholderText: "Owner (optional)" }
    Field { id: budget; Layout.fillWidth: true; placeholderText: "Planning budget in USD"; validator: DoubleValidator { bottom: 0; locale: "C" } }
    Field { id: due; Layout.fillWidth: true; placeholderText: "Due date: YYYY-MM-DD (optional)" }
    onSubmitted: {
        if (!name.text.trim()) { error = "Enter a project name."; return }
        busy = true
        var newSlug = slug || api.slug(name.text)
        api.request("POST", slug ? "/api/project/save" : "/api/project/create", {slug: newSlug, name: name.text, description: description.text, owner: owner.text, budget: Number(budget.text || 0), due_date: due.text, color: "#3584e4"}, function() { form.busy = false; form.close(); form.api.refresh(newSlug); form.api.message = "Project saved" }, function(v) { form.busy = false; form.error = v.error }, 100000, "save-project")
    }
}
