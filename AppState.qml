import QtQml

QtObject {
    id: app
    property string endpoint: "http://127.0.0.1:18731"
    property HttpClient http: HttpClient {}
    property var data: ({profiles: [], tasks: [], projects: [], prompts: [], favorites: {models: []}})
    readonly property var profiles: data.profiles || []
    readonly property var tasks: data.tasks || []
    readonly property var projects: data.projects || []
    readonly property var prompts: data.prompts || []
    readonly property var favorites: data.favorites ? data.favorites.models || [] : []
    property var providers: []
    property var connections: [{id: "local", name: "Local Hermes", kind: "local", connected: true}]
    property string connectionId: "local"
    property int epoch: 0
    property var connectionViews: ({})
    property string board: ""
    property string selectedProfile: "default"
    property string page: "Tasks"
    property bool dark: true
    property bool connected: false
    property var operations: ({})
    readonly property int pending: http.pendingCount
    property string error: ""
    property string message: ""

    function profile(slug) { return profiles.filter(function(p) { return p.slug === slug })[0] || ({}) }
    function providerIndex(id) { return Math.max(0, providers.map(function(p) { return p.id }).indexOf(id)) }
    function slug(name) { return name.trim().toLowerCase().replace(/[^a-z0-9]+/g, "-").replace(/^-+|-+$/g, "") }
    function money(value) { return "$" + Number(value || 0).toFixed(2) }
    function rate(model) { return model.price_known === false ? "Price unavailable" : "$" + Number(model.input_rate || 0).toFixed(2) + " input · $" + Number(model.output_rate || 0).toFixed(2) + " output / 1M tokens" }
    function busy(key) { return !!operations[key] }
    function setBusy(key, value) { var copy = Object.assign({}, operations); if (value) copy[key] = true; else delete copy[key]; operations = copy }
    function connection() { return connections.filter(function(c) { return c.id === connectionId })[0] || ({id: "local"}) }
    function request(method, path, payload, done, failed, timeout, key, local) {
        key = key || ""
        if (key && busy(key)) return false
        if (key) setBusy(key, true)
        var requestEpoch = epoch
        function success(value) {
            if (key) setBusy(key, false)
            if (!local && requestEpoch !== app.epoch) return
            if (!local) app.connected = true
            if (done) done(value)
        }
        function failure(value) {
            if (key) setBusy(key, false)
            if (!local && requestEpoch !== app.epoch) return
            if (!local && value.transport_error) app.connected = false
            app.error = value.error || "Request failed. Try again."
            if (failed) failed(value)
        }
        var active = connection()
        if (!local && active.kind === "https") {
            http.send("POST", endpoint + "/api/connections/request", {id: connectionId, method: method, path: path, body: payload, timeout_ms: timeout || 30000}, (timeout || 30000) + 5000, success, failure)
        } else if (!local && active.kind === "ssh") {
            if (!active.connected || !active.url) { failure({error: "SSH connection is closed. Reconnect it in Settings → Connections."}); return false }
            http.send(method, active.url + path, payload, timeout || 30000, success, failure)
        } else http.send(method, endpoint + path, payload, timeout || 30000, success, failure)
        return true
    }
    function refresh(nextBoard) {
        var requested = nextBoard === undefined ? board : nextBoard
        request("GET", "/api/state" + (requested ? "?board=" + encodeURIComponent(requested) : ""), null, function(value) {
            app.data = value; app.board = value.board || "default"; app.dark = value.theme !== "light"
            if (!app.profiles.some(function(p) { return p.slug === app.selectedProfile })) app.selectedProfile = "default"
        }, null, 45000, "refresh")
    }
    function loadProviders() { request("GET", "/api/providers", null, function(value) { app.providers = (value.providers || []).filter(function(p) { return p.id !== "auto" }) }, null, 30000, "providers") }
    function loadConnections() {
        request("GET", "/api/connections", null, function(value) { app.connections = [{id: "local", name: "Local Hermes", kind: "local", connected: true}].concat(value.connections || []) }, null, 30000, "connections", true)
    }
    function activate(id) {
        if (id === connectionId) return true
        if (pending) { error = "Wait for the current request to finish before switching connections."; return false }
        var views = Object.assign({}, connectionViews)
        views[connectionId] = {board: board, profile: selectedProfile, page: page}; connectionViews = views
        var view = views[id] || ({})
        epoch++; connectionId = id; board = view.board || ""; selectedProfile = view.profile || "default"; page = view.page || "Tasks"; data = ({profiles: [], tasks: [], projects: [], prompts: [], favorites: {models: []}})
        connected = false; error = ""; message = ""
        if (connection().kind === "ssh" && !connection().connected) {
            request("POST", "/api/connections/connect", {id: id}, function(value) {
                app.connections = app.connections.map(function(c) { return c.id === id ? value.connection : c })
                app.refresh(app.board); app.loadProviders()
            }, null, 30000, "connect", true)
        } else { refresh(board); loadProviders() }
        return true
    }
    function mutate(path, payload, done, failed, timeout, key) {
        return request("POST", path, payload, function(value) { if (done) done(value); app.refresh() }, failed, timeout || 100000, key || path)
    }
    function toggleFavorite(id) {
        request("POST", "/api/favorite/model", {id: id, favorite: favorites.indexOf(id) < 0}, function(value) { app.data = Object.assign({}, app.data, {favorites: {models: value.favorite_models || []}}) }, null, 30000, "favorite:" + id)
    }
    function initialize() { refresh(""); loadProviders(); loadConnections() }
}
