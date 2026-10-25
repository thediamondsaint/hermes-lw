import QtQuick
import QtQuick.Controls
import QtQuick.Layouts

Pane {
    id: catalog
    required property var api
    property var dialogHost: parent
    property string profileSlug: "default"
    property string providerId: "openrouter"
    property string baseUrl: ""
    property bool textOnly: false
    property bool loading: false
    property string error: ""
    property var models: []
    property var collapsed: ({})
    property int requestId: 0
    property string loadedKey: ""
    property alias searchText: search.text
    signal chosen(string modelId, string providerId, string baseUrl)
    signal askAi(var models, string profileSlug, string providerId)
    padding: 0
    function publisher(m) { return m.id.indexOf("/") >= 0 ? m.id.split("/")[0] : providerId }
    function group(m) {
        if (groupBy.currentIndex === 1) return m.category || "Other"
        if (groupBy.currentIndex === 2) return m.price_known === false ? "Price unavailable" : Number(m.input_rate) === 0 ? "Free input" : Number(m.input_rate) < 1 ? "Input under $1 / 1M" : Number(m.input_rate) < 5 ? "Input $1–5 / 1M" : "Input $5+ / 1M"
        if (groupBy.currentIndex === 3) return "All models"
        return publisher(m)
    }
    property var filtered: {
        var tokens = search.text.trim().toLowerCase().split(/\s+/).filter(function(t) { return t.length })
        var result = models.filter(function(m) {
            if (textOnly && ((m.inputs || []).indexOf("text") < 0 || (m.outputs || []).indexOf("text") < 0)) return false
            if (favoritesOnly.checked && api.favorites.indexOf(m.id) < 0) return false
            if (useFilter.currentIndex > 0 && m.category !== useFilter.currentText) return false
            if (inputCap.text.trim() && (m.price_known === false || Number(m.input_rate) > Number(inputCap.text))) return false
            if (outputCap.text.trim() && (m.price_known === false || Number(m.output_rate) > Number(outputCap.text))) return false
            var haystack = [m.id, m.name, m.description, m.category, (m.inputs || []).join(" "), (m.outputs || []).join(" ")].join(" ").toLowerCase()
            return tokens.every(function(t) { return haystack.indexOf(t) >= 0 })
        }).map(function(m) { return Object.assign({}, m, {group: catalog.group(m)}) })
        result.sort(function(a, b) {
            var grouping = a.group.localeCompare(b.group)
            if (grouping) return grouping
            if (sortBy.currentIndex === 1) return (a.price_known === false ? Infinity : Number(a.input_rate)) - (b.price_known === false ? Infinity : Number(b.input_rate)) || a.id.localeCompare(b.id)
            if (sortBy.currentIndex === 2) return (a.price_known === false ? Infinity : Number(a.output_rate)) - (b.price_known === false ? Infinity : Number(b.output_rate)) || a.id.localeCompare(b.id)
            if (sortBy.currentIndex === 3) return Number(b.context_length || 0) - Number(a.context_length || 0)
            return (a.name || a.id).localeCompare(b.name || b.id)
        })
        return result
    }
    property var displayed: {
        var result = [], seen = {}
        filtered.forEach(function(m) {
            if (!collapsed[m.group]) result.push(m)
            else if (!seen[m.group]) { result.push({group: m.group, placeholder: true, id: ""}); seen[m.group] = true }
        })
        return result
    }
    function collapseAll(value) { var next = {}; if (value) filtered.forEach(function(m) { next[m.group] = true }); collapsed = next }
    function load(force) {
        var key = api.connectionId + ":" + profileSlug + ":" + providerId + ":" + baseUrl
        if (!force && (loading && loadedKey === key || loadedKey === key && models.length)) return
        loadedKey = key; loading = true; error = ""; models = []; collapsed = ({})
        var serial = ++requestId
        api.request("GET", "/api/models?provider=" + encodeURIComponent(providerId) + "&profile=" + encodeURIComponent(profileSlug) + (baseUrl ? "&base_url=" + encodeURIComponent(baseUrl) : "") + (force ? "&refresh=1" : ""), null, function(value) {
            if (serial !== catalog.requestId) return
            catalog.loading = false; catalog.models = value.models || []; catalog.error = value.error || ""
        }, function(value) { if (serial === catalog.requestId) { catalog.loading = false; catalog.error = value.error || "Catalog unavailable" } }, 55000)
    }
    contentItem: ColumnLayout {
        spacing: 8
        RowLayout {
            Layout.fillWidth: true
            Picker { id: provider; Layout.fillWidth: true; model: catalog.api.providers; textRole: "label"; valueRole: "id"; currentIndex: catalog.api.providerIndex(catalog.providerId); onActivated: { catalog.providerId = currentValue; catalog.baseUrl = currentValue === "custom" ? catalog.api.profile(catalog.profileSlug).base_url || "" : ""; catalog.load(false) } Accessible.name: "Model provider" }
            ActionButton { text: catalog.loading ? "Loading…" : "Refresh"; enabled: !catalog.loading; onClicked: catalog.load(true); objectName: "catalogRefresh" }
            ActionButton { text: "Ask AI"; enabled: !catalog.loading && catalog.filtered.length > 0; onClicked: catalog.askAi(catalog.filtered, catalog.profileSlug, catalog.providerId) }
        }
        Field { id: search; Layout.fillWidth: true; placeholderText: "Search names, creators or capabilities…"; selectByMouse: true; objectName: "modelSearch"; Accessible.name: "Search models" }
        RowLayout {
            Layout.fillWidth: true
            Label { Layout.fillWidth: true; text: catalog.loading ? "Loading provider models…" : catalog.filtered.length + " models"; font.pixelSize: 12 }
            ActionButton { text: "Filters & sort"; implicitHeight: 30; onClicked: filterDialog.open() }
            ActionButton { text: "Collapse all"; implicitHeight: 30; onClicked: catalog.collapseAll(true) }
            ActionButton { text: "Expand all"; implicitHeight: 30; onClicked: catalog.collapseAll(false) }
        }
        Label { visible: catalog.error.length > 0; Layout.fillWidth: true; text: catalog.error; wrapMode: Text.WrapAnywhere; color: "#e69385" }
        ListView {
            id: list; objectName: "modelList"; Layout.fillWidth: true; Layout.fillHeight: true; clip: true; spacing: 6; model: catalog.displayed
            section.property: "group"; section.criteria: ViewSection.FullString
            section.delegate: ToolButton {
                required property string section
                width: list.width; height: 34; text: (catalog.collapsed[section] ? "▸ " : "▾ ") + section
                font.bold: true
                onClicked: { var next = Object.assign({}, catalog.collapsed); next[section] = !next[section]; catalog.collapsed = next }
            }
            delegate: Frame {
                id: card; required property var modelData
                width: list.width; height: modelData.placeholder ? 0 : body.implicitHeight + 20; visible: !modelData.placeholder; padding: 10
                ColumnLayout {
                    id: body; width: card.availableWidth; spacing: 5
                    Label { Layout.fillWidth: true; text: card.modelData.name || card.modelData.id; font.bold: true; wrapMode: Text.WrapAnywhere }
                    Label { Layout.fillWidth: true; text: card.modelData.id || ""; font.pixelSize: 12; wrapMode: Text.WrapAnywhere; opacity: 0.8 }
                    Label { Layout.fillWidth: true; text: catalog.api.rate(card.modelData); font.pixelSize: 12; wrapMode: Text.WordWrap }
                    RowLayout {
                        Layout.fillWidth: true
                        Label { Layout.fillWidth: true; text: (card.modelData.category || "") + (card.modelData.context_length ? " · " + Math.round(card.modelData.context_length / 1000) + "K context" : ""); font.pixelSize: 12; wrapMode: Text.WordWrap }
                        ActionButton { text: catalog.api.favorites.indexOf(card.modelData.id) >= 0 ? "★" : "☆"; implicitWidth: 38; Accessible.name: "Favorite " + card.modelData.id; onClicked: catalog.api.toggleFavorite(card.modelData.id) }
                        ActionButton { text: "Select"; primary: true; objectName: "selectModel_" + card.modelData.id; onClicked: catalog.chosen(card.modelData.id, catalog.providerId, catalog.baseUrl) }
                    }
                }
            }
            ScrollBar.vertical: ScrollBar {}
            Label { anchors.centerIn: parent; width: parent.width - 24; horizontalAlignment: Text.AlignHCenter; wrapMode: Text.WordWrap; visible: !catalog.loading && catalog.filtered.length === 0; text: catalog.error ? "Catalog unavailable. Check the provider and credentials, then refresh." : "No models match. Clear search or raise the price filters." }
        }
    }
    FormDialog {
        id: filterDialog; parent: catalog.dialogHost; title: "Model filters & sorting"; showSubmit: false
        Label { Layout.fillWidth: true; text: "Filter locally. This makes no model request. Prices are USD per million tokens."; wrapMode: Text.WordWrap }
        GridLayout {
            Layout.fillWidth: true; columns: width > 450 ? 2 : 1; columnSpacing: 8; rowSpacing: 6
            Picker { id: useFilter; Layout.fillWidth: true; model: ["All uses", "Text & chat", "Coding", "Vision", "Image generation", "Audio", "Video", "Embeddings", "Decision", "Files & documents", "Other"]; Accessible.name: "Filter model use" }
            Picker { id: groupBy; Layout.fillWidth: true; model: ["Group: creator", "Group: use", "Group: input cost", "No groups"]; Accessible.name: "Model grouping" }
            Picker { id: sortBy; Layout.fillWidth: true; model: ["Sort: name", "Sort: input cost", "Sort: output cost", "Sort: context size"]; Accessible.name: "Model sort order" }
            Field { id: inputCap; Layout.fillWidth: true; placeholderText: "Max input $ / 1M"; validator: DoubleValidator { bottom: 0; locale: "C" } Accessible.name: "Maximum input rate" }
            Field { id: outputCap; Layout.fillWidth: true; placeholderText: "Max output $ / 1M"; validator: DoubleValidator { bottom: 0; locale: "C" } Accessible.name: "Maximum output rate" }
            Choice { id: favoritesOnly; text: "Favorites only" }
        }

        ActionButton { text: "Clear filters"; onClicked: { search.text = ""; useFilter.currentIndex = 0; groupBy.currentIndex = 0; sortBy.currentIndex = 0; inputCap.text = ""; outputCap.text = ""; favoritesOnly.checked = false; catalog.collapseAll(false) } }
    }

}
