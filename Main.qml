import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import Quickshell

ShellRoot {
  id: root
  property string page: "Overview"
  property var profiles: []
  property var tasks: []
  property var projects: []
  property var projectInfo: ({})
  property string currentBoard: ""
  property var savedViews: []
  property var taskTemplates: []
  property var selectedTaskIds: []
  property var newAllowedProfiles: []
  property var newProfileBudgets: ({})
  property bool aiProfilesEnabled: false
  property var aiProfileSuggestions: []
  property var detailAllowedProfiles: []
  property var detailProfileBudgets: ({})
  property bool backendConnected: false
  property int pendingRequests: 0
  property string statusFilterValue: "all"
  property string assigneeFilterValue: "all"
  property var editingProject: null
  property string selectedProfile: ""
  property var selectedTask: null
  property var selectedTaskDetail: ({})
  property string taskSearch: ""
  property string notice: ""
  property bool showNewTask: false
  property bool showProjectEditor: false
  property bool showHermes: false
  property bool advancedMode: false
  property bool darkMode: false
  property var advancedConfig: ({})
  property var favoriteModels: []
  property var prompts: []
  property string managerProfile: ""
  property bool showCreateProfile: false
  property bool showDeleteProfile: false
  property bool generatingPersonality: false
  property bool showPromptEditor: false
  property var editingPrompt: null
  property bool showModels: false
  property bool showProviderManager: false
  property string providerManagerProfile: ""
  property string selectedManagedProvider: "auto"
  property string managedCredentialName: ""
  property bool modelCatalogLoading: false
  property var modelCatalog: []
  property var modelProviders: []
  property string modelCatalogSource: ""
  property string modelCatalogProvider: ""
  property string modelCatalogProfile: ""
  property string modelCatalogBaseUrl: ""
  property string modelCatalogError: ""
  property int modelCatalogRequestId: 0
  property bool modelCatalogStale: false
  property double modelCatalogFetchedAt: 0
  property string extensionProfile: "default"
  property string extensionTab: "Plugins"
  property string extensionPlatform: "cli"
  property var extensionPlugins: []
  property var extensionTools: []
  property var extensionMcpServers: []
  property var extensionMcpCatalog: []
  property bool extensionLoading: false
  property string extensionSearch: ""
  property string extensionInstallId: ""
  property bool allowPluginToolOverride: false
  property string mcpTransport: "http"
  property string extensionError: ""
  property bool catalogAllCollapsed: false
  property var catalogCollapsedGroups: []
  property var catalogExpandedGroups: []
  property int catalogVisibleLimit: 100
  property int samplePromptTokens: 2000
  property int sampleCompletionTokens: 500
  property var catalogPublishers: {
    var found = {}
    for (var i = 0; i < root.modelCatalog.length; ++i) found[root.modelPublisher(root.modelCatalog[i])] = true
    return ["All publishers"].concat(Object.keys(found).sort())
  }
  property var advisorModels: {
    var use = advisorTaskType.currentText
    var category = use === "Code audit" || use === "Implementation" ? "Coding" : use === "Image work" ? "Vision" : "Text & chat"
    var budget = Number(advisorBudget.text) || 0
    return root.modelCatalog.filter(function(m) {
      if (m.price_known === false || (m.inputs || []).indexOf("text") < 0) return false
      if (use === "Image work" && (m.inputs || []).indexOf("image") < 0) return false
      if (use !== "Image work" && m.category !== category && !(use === "Code audit" && m.category === "Text & chat")) return false
      var estimate = (Number(m.input_rate || 0) * 4000 + Number(m.output_rate || 0) * 1200) / 1000000
      return budget === 0 ? estimate === 0 : budget > 0 && estimate <= budget
    }).sort(function(a,b) {
      var ac = (Number(a.input_rate || 0) * 4000 + Number(a.output_rate || 0) * 1200) / 1000000
      var bc = (Number(b.input_rate || 0) * 4000 + Number(b.output_rate || 0) * 1200) / 1000000
      if (use === "Code audit" || use === "Implementation") return Number(b.context_length || 0) - Number(a.context_length || 0) || ac - bc
      return ac - bc || Number(b.context_length || 0) - Number(a.context_length || 0)
    }).slice(0, 8)
  }
  function advisorPrompt() {
    var task = advisorProblem.text.trim() || "[Describe the problem and desired outcome]"
    var kind = advisorTaskType.currentText
    if (kind === "Code audit") return "You are a meticulous senior software auditor. Review the repository against this request: " + task + "\n\nTrace relevant code paths before drawing conclusions. Prioritize concrete defects, security and data-loss risks, and reproducible evidence. Report findings by severity with file and line references, explain impact, and list any areas you could not verify. Do not modify files unless explicitly asked."
    if (kind === "Implementation") return "You are a senior software engineer. Implement this request: " + task + "\n\nInspect project conventions first, make the smallest complete change, preserve existing behavior outside scope, and summarize files changed and validation performed."
    if (kind === "Research") return "Research this question: " + task + "\n\nUse primary sources where possible, compare evidence, distinguish confirmed facts from inference, and provide dated links and a concise recommendation."
    if (kind === "Writing") return "Help produce this deliverable: " + task + "\n\nClarify the audience and success criteria from context, organize the result for quick reading, and flag assumptions that materially affect the outcome."
    return "Solve this problem: " + task + "\n\nFirst restate the goal and constraints, then provide a practical plan, carry it through where tools allow, and report evidence, risks, and remaining uncertainties."
  }
  function catalogProviderName() {
    var entry = root.providerEntry(root.modelCatalogProvider)
    return entry.label || root.modelCatalogProvider || "Model"
  }
  function modelPublisher(model) {
    var id = String(model.id || "")
    return id.indexOf("/") >= 0 ? id.split("/")[0] : (root.modelCatalogProvider || "Other")
  }
  function catalogContextBand(model) {
    var n = Number(model.context_length || 0)
    if (!n) return "Unknown context"
    if (n < 32000) return "Under 32K"
    if (n < 128000) return "32K–128K"
    if (n < 512000) return "128K–512K"
    if (n < 1000000) return "512K–1M"
    return "1M+"
  }
  function catalogPriceBand(model, key) {
    if (model.price_known === false) return "Price unavailable"
    var rate = Number(model[key] || 0)
    if (rate === 0) return "Free"
    if (rate < 1) return "Under $1 / M"
    if (rate < 5) return "$1–5 / M"
    if (rate < 20) return "$5–20 / M"
    return "$20+ / M"
  }
  function catalogPriceMatches(model, band, key) {
    if (!band) return true
    if (model.price_known === false) return false
    var rate = Number(model[key] || 0)
    if (band === 1) return rate === 0
    if (band === 2) return rate > 0 && rate < 1
    if (band === 3) return rate >= 1 && rate < 5
    if (band === 4) return rate >= 5 && rate < 20
    return rate >= 20
  }
  function catalogGroupLabel(model) {
    switch (catalogGroupBy.currentIndex) {
    case 1: return root.modelPublisher(model)
    case 2: return root.catalogPriceBand(model, "input_rate")
    case 3: return root.catalogPriceBand(model, "output_rate")
    case 4: return root.catalogContextBand(model)
    case 5:
      if ((model.outputs || []).indexOf("image") >= 0) return "Image generation"
      if ((model.inputs || []).indexOf("image") >= 0) return "Vision / image input"
      if ((model.inputs || []).indexOf("audio") >= 0 || (model.outputs || []).indexOf("audio") >= 0) return "Audio"
      if ((model.inputs || []).indexOf("video") >= 0) return "Video"
      return "Text / other"
    default: return model.category || "Other"
    }
  }
  function catalogGroupRank(label) {
    var order = []
    if (catalogGroupBy.currentIndex === 2 || catalogGroupBy.currentIndex === 3) order = ["Free", "Under $1 / M", "$1–5 / M", "$5–20 / M", "$20+ / M", "Price unavailable"]
    else if (catalogGroupBy.currentIndex === 4) order = ["Under 32K", "32K–128K", "128K–512K", "512K–1M", "1M+", "Unknown context"]
    else if (catalogGroupBy.currentIndex === 5) order = ["Text / other", "Vision / image input", "Image generation", "Audio", "Video"]
    var rank = order.indexOf(label)
    return rank < 0 ? 1000 : rank
  }
  function catalogGroupKey(label) { return catalogGroupBy.currentIndex + "::" + label }
  function catalogGroupIsCollapsed(label) {
    var key = root.catalogGroupKey(label)
    return root.catalogAllCollapsed ? root.catalogExpandedGroups.indexOf(key) < 0 : root.catalogCollapsedGroups.indexOf(key) >= 0
  }
  function toggleCatalogGroup(label) {
    var key = root.catalogGroupKey(label)
    var list = (root.catalogAllCollapsed ? root.catalogExpandedGroups : root.catalogCollapsedGroups).slice(0)
    var index = list.indexOf(key)
    if (index >= 0) list.splice(index, 1)
    else list.push(key)
    if (root.catalogAllCollapsed) root.catalogExpandedGroups = list
    else root.catalogCollapsedGroups = list
  }
  function collapseAllCatalogGroups() {
    root.catalogAllCollapsed = true
    root.catalogCollapsedGroups = []
    root.catalogExpandedGroups = []
  }
  function expandAllCatalogGroups() {
    root.catalogAllCollapsed = false
    root.catalogCollapsedGroups = []
    root.catalogExpandedGroups = []
  }
  function estimatedModelCost(model) {
    if (model.price_known === false) return null
    return (Number(model.input_rate || 0) * root.samplePromptTokens + Number(model.output_rate || 0) * root.sampleCompletionTokens) / 1000000
  }
  function recommendProfilesForTask() {
    var text = (newTitle.text + " " + newBody.text).toLowerCase()
    var scored = root.assignableProfiles().map(function(p) {
      var haystack = (p.slug + " " + p.description + " " + p.personality + " " + p.model).toLowerCase()
      var score = 0
      var keywords = text.match(/[a-z0-9+#.-]{3,}/g) || []
      for (var i = 0; i < keywords.length; ++i) if (haystack.indexOf(keywords[i]) >= 0) score += 2
      if (/audit|review|security|inspect|analy[sz]e/.test(text) && /review|audit|security|analys|critic/.test(haystack)) score += 5
      if (/code|implement|build|bug|refactor/.test(text) && /code|develop|engineer|program/.test(haystack)) score += 5
      if (/research|compare|source|find/.test(text) && /research|search|analys/.test(haystack)) score += 4
      if (/write|document|copy|design/.test(text) && /write|document|design|creative/.test(haystack)) score += 4
      return {slug: p.slug, score: score, model: p.model, personality: p.personality || ""}
    })
    scored.sort(function(a,b) { return b.score - a.score || a.slug.localeCompare(b.slug) })
    root.aiProfileSuggestions = scored.slice(0, Math.min(4, scored.length))
  }
  function setNewProfileBudget(slug, value) {
    var budgets = Object.assign({}, root.newProfileBudgets)
    var amount = Number(value)
    if (String(value).trim() && isFinite(amount) && amount >= 0) budgets[slug] = amount
    else delete budgets[slug]
    root.newProfileBudgets = budgets
  }
  function toggleAiProfiles(value) {
    root.aiProfilesEnabled = value
    if (value) root.recommendProfilesForTask()
  }
  function startTaskFromAdvisor() {
    root.aiProfilesEnabled = true
    root.prepareNewTask()
    newTitle.text = advisorTaskType.currentText + " task"
    newBody.text = root.advisorPrompt()
    root.page = "Kanban"
  }
  function modalOpen() {
    return root.showModels || root.showProviderManager || root.showDeleteProfile || root.showCreateProfile || root.showPromptEditor || root.selectedTask !== null || root.showHermes || root.showNewTask || root.showProjectEditor
  }
  property var catalogDisplayItems: {
    var rows = [], items = root.catalogItems.slice(0, root.catalogVisibleLimit), index = 0
    while (index < items.length) {
      var section = items[index].catalog_section
      if (root.catalogGroupIsCollapsed(section)) {
        rows.push({is_placeholder: true, catalog_section: section, name: "", id: "", category: "", inputs: [], outputs: [], supported_parameters: []})
        while (index < items.length && items[index].catalog_section === section) ++index
      } else {
        rows.push(items[index])
        ++index
      }
    }
    return rows
  }
  function resetCatalogFilters() {
    modelSearch.text = ""
    catalogPublisherFilter.currentIndex = 0
    modelUseFilter.currentIndex = 0
    catalogModalityFilter.currentIndex = 0
    catalogPriceFilter.currentIndex = 0
    catalogOutputPriceFilter.currentIndex = 0
    catalogContextFilter.currentIndex = 0
    catalogCapabilityFilter.currentIndex = 0
    catalogGroupBy.currentIndex = 0
    catalogSort.currentIndex = 0
    root.catalogVisibleLimit = 100
    root.expandAllCatalogGroups()
  }
  property var catalogItems: {
    var items = root.modelCatalog.map(function(model, index) {
      var item = {}
      for (var key in model) item[key] = model[key]
      item.catalog_section = root.catalogGroupLabel(model)
      item.catalog_order = index
      return item
    })
    var q = modelSearch.text.trim().toLowerCase().split(/\s+/).filter(function(token) { return token.length > 0 })
    var category = modelUseFilter.currentText
    if (q.length) items = items.filter(function(m) {
      var searchable = [m.name, m.id, m.description, m.category, root.modelPublisher(m), (m.inputs || []).join(" "), (m.outputs || []).join(" "), (m.supported_parameters || []).join(" ")].join(" ").toLowerCase()
      return q.every(function(token) { return searchable.indexOf(token) >= 0 })
    })
    if (category === "Favorites") items = items.filter(function(m) { return root.favoriteModels.indexOf(m.id) >= 0 })
    else if (category !== "All uses") items = items.filter(function(m) { return m.category === category })
    if (catalogPublisherFilter.currentIndex > 0) items = items.filter(function(m) { return root.modelPublisher(m) === catalogPublisherFilter.currentText })
    var modality = catalogModalityFilter.currentIndex
    if (modality) items = items.filter(function(m) {
      var input = m.inputs || [], output = m.outputs || []
      if (modality === 1) return input.indexOf("text") >= 0
      if (modality === 2) return input.indexOf("image") >= 0
      if (modality === 3) return input.indexOf("audio") >= 0
      if (modality === 4) return input.indexOf("video") >= 0
      if (modality === 5) return output.indexOf("image") >= 0
      if (modality === 6) return output.indexOf("audio") >= 0
      return output.indexOf("embeddings") >= 0
    })
    var price = catalogPriceFilter.currentIndex
    if (price) items = items.filter(function(m) { return root.catalogPriceMatches(m, price, "input_rate") })
    var outputPrice = catalogOutputPriceFilter.currentIndex
    if (outputPrice) items = items.filter(function(m) { return root.catalogPriceMatches(m, outputPrice, "output_rate") })
    var context = catalogContextFilter.currentIndex
    if (context) items = items.filter(function(m) { return Number(m.context_length || 0) >= [0, 64000, 128000, 256000, 1000000][context] })
    var capability = catalogCapabilityFilter.currentIndex
    if (capability) items = items.filter(function(m) {
      var params = m.supported_parameters || []
      if (capability === 1) return params.indexOf("tools") >= 0 || params.indexOf("tool_choice") >= 0
      if (capability === 2) return params.indexOf("reasoning") >= 0 || params.indexOf("reasoning_effort") >= 0
      return params.indexOf("structured_outputs") >= 0 || params.indexOf("json_schema") >= 0
    })
    var sort = catalogSort.currentIndex
    items.sort(function(a, b) {
      var groupOrder = catalogGroupBy.currentIndex >= 2 ? root.catalogGroupRank(a.catalog_section) - root.catalogGroupRank(b.catalog_section) : a.catalog_section.localeCompare(b.catalog_section)
      if (groupOrder) return groupOrder
      if (sort === 0) return a.catalog_order - b.catalog_order
      if (sort === 1) return a.name.localeCompare(b.name)
      if (sort === 2) return Number(b.created || 0) - Number(a.created || 0)
      if (sort === 6) return Number(b.context_length || 0) - Number(a.context_length || 0)
      var key = sort === 3 || sort === 7 ? "input_rate" : sort === 4 || sort === 8 ? "output_rate" : "average_rate"
      var av = key === "average_rate" ? (Number(a.input_rate || 0) + Number(a.output_rate || 0)) / 2 : Number(a[key] || 0)
      var bv = key === "average_rate" ? (Number(b.input_rate || 0) + Number(b.output_rate || 0)) / 2 : Number(b[key] || 0)
      if (a.price_known === false && b.price_known !== false) return 1
      if (a.price_known !== false && b.price_known === false) return -1
      var descending = sort === 7 || sort === 8
      return (descending ? bv - av : av - bv) || a.name.localeCompare(b.name)
    })
    return items
  }
  readonly property color bg: darkMode ? "#111a27" : "#ece9d8"
  readonly property color surface: darkMode ? "#1b2838" : "#ffffff"
  readonly property color raised: darkMode ? "#293b50" : "#f4f2e9"
  readonly property color border: darkMode ? "#415c78" : "#7f9db9"
  readonly property color text: darkMode ? "#eaf2fb" : "#111111"
  readonly property color muted: darkMode ? "#a4b6c9" : "#444444"
  readonly property color accent: darkMode ? "#55aaff" : "#0054e3"
  readonly property color blue: darkMode ? "#8dbbff" : "#0a246a"
  readonly property color amber: darkMode ? "#ffc766" : "#bc7700"
  readonly property color red: darkMode ? "#ff8888" : "#b43737"
  readonly property color inputFill: darkMode ? "#111b29" : "#ffffff"
  readonly property color sidebarFill: darkMode ? "#172334" : "#f7f6ef"
  readonly property color selectedFill: darkMode ? "#263d56" : "#316ac5"
  readonly property color laneFill: darkMode ? "#172333" : "#f4f3ed"
  readonly property color hoverFill: darkMode ? "#25384d" : "#e8f0fb"

  function request(method, path, payload, callback, onFailure, timeoutMs) {
    var xhr = new XMLHttpRequest()
    xhr.open(method, "http://127.0.0.1:18731" + path)
    xhr.timeout = timeoutMs || 20000
    xhr.setRequestHeader("Content-Type", "application/json")
    root.pendingRequests += 1
    var settled = false
    function finish() { if (!settled) { settled = true; root.pendingRequests = Math.max(0, root.pendingRequests - 1) } }
    xhr.onreadystatechange = function() {
      if (xhr.readyState === XMLHttpRequest.DONE) {
        finish()
        var value = {}
        try { value = JSON.parse(xhr.responseText) } catch (e) { value = {error: "Invalid response from Hermes LW"} }
        if (xhr.status >= 200 && xhr.status < 300) { root.backendConnected = true; callback(value) }
        else { root.backendConnected = xhr.status !== 0; root.notice = value.error || "Request failed"; if (onFailure) onFailure(value) }
      }
    }
    xhr.onerror = function() { finish(); root.backendConnected = false; root.notice = "Hermes LW backend is unreachable"; if (onFailure) onFailure({error: root.notice}) }
    xhr.ontimeout = function() { finish(); root.notice = "Hermes request timed out"; if (onFailure) onFailure({error: root.notice}) }
    xhr.send(payload ? JSON.stringify(payload) : "{}")
  }
  function refresh(boardSlug) {
    var requestedBoard = boardSlug || root.currentBoard
    request("GET", "/api/state" + (requestedBoard ? "?board=" + encodeURIComponent(requestedBoard) : ""), null, function(data) {
      root.profiles = data.profiles || []
      root.tasks = data.tasks || []
      root.projects = data.projects || []
      root.projectInfo = data.project || ({})
      root.currentBoard = data.board || "default"
      root.savedViews = data.saved_views || []
      root.taskTemplates = data.task_templates || []
      root.favoriteModels = data.favorites ? data.favorites.models || [] : []
      root.prompts = data.prompts || []
      root.managerProfile = data.manager_profile || ""
      root.darkMode = data.theme === "dark"
      if (!root.selectedProfile && root.profiles.length) root.selectedProfile = root.profiles[0].slug
    })
  }
  function openModelCatalog(providerOverride, profileOverride, baseUrlOverride) {
    var profile = profileOverride || (root.showProviderManager ? root.providerManagerProfile : root.selectedProfile) || "default"
    var profileData = root.profileBySlug(profile)
    var provider = providerOverride || (root.showProviderManager ? root.selectedManagedProvider : (providerInput.currentValue || profileData.provider || "auto"))
    var baseUrl = baseUrlOverride || (provider === "custom" ? (root.showProviderManager ? providerManagerBaseUrl.text : baseUrlInput.text) : "")
    var changed = provider !== root.modelCatalogProvider || profile !== root.modelCatalogProfile || baseUrl !== root.modelCatalogBaseUrl
    root.showModels = true
    if (changed || !root.modelCatalog.length) root.loadModelCatalog(false, provider, profile, baseUrl)
  }
  function loadModelCatalog(force, providerOverride, profileOverride, baseUrlOverride) {
    var profile = profileOverride || (root.showProviderManager ? root.providerManagerProfile : root.selectedProfile) || "default"
    var profileData = root.profileBySlug(profile)
    var provider = providerOverride || (root.showProviderManager ? root.selectedManagedProvider : (providerInput.currentValue || profileData.provider || "auto"))
    var baseUrl = baseUrlOverride || (provider === "custom" ? (root.showProviderManager ? providerManagerBaseUrl.text : baseUrlInput.text) : "")
    var providerChanged = root.modelCatalogProvider !== provider || root.modelCatalogProfile !== profile || root.modelCatalogBaseUrl !== baseUrl
    root.modelCatalogLoading = true
    if (providerChanged) root.modelCatalog = []
    root.modelCatalogProvider = provider
    root.modelCatalogProfile = profile
    root.modelCatalogBaseUrl = baseUrl
    root.modelCatalogError = ""
    var requestId = ++root.modelCatalogRequestId
    var query = "?provider=" + encodeURIComponent(provider) + "&profile=" + encodeURIComponent(profile)
    if (force) query += "&refresh=1"
    if (baseUrl) query += "&base_url=" + encodeURIComponent(baseUrl)
    request("GET", "/api/models" + query, null, function(data) {
      if (requestId !== root.modelCatalogRequestId) return
      root.modelCatalog = data.models || []
      root.modelCatalogProvider = data.provider || provider
      root.modelCatalogSource = data.source || "cache"
      root.modelCatalogStale = !!data.stale
      root.modelCatalogFetchedAt = Number(data.fetched_at || 0)
      root.catalogVisibleLimit = 100
      root.modelCatalogLoading = false
      root.modelCatalogError = data.error || ""
      if (!root.modelCatalog.length) root.notice = "No models returned for " + root.catalogProviderName()
    }, function(error) {
      if (requestId !== root.modelCatalogRequestId) return
      root.modelCatalog = []
      root.modelCatalogError = error.error || ("Could not load models for " + root.catalogProviderName())
      root.modelCatalogLoading = false
    }, 45000)
  }
  function loadModelProviders() {
    request("GET", "/api/providers", null, function(data) {
      root.modelProviders = data.providers || []
      var provider = root.currentProfile().provider || "auto"
      providerInput.currentIndex = root.providerIndex(provider)
    })
  }
  function loadExtensions(profile, platform) {
    root.extensionProfile = profile || root.selectedProfile || "default"
    root.extensionPlatform = platform || root.extensionPlatform || "cli"
    root.extensionLoading = true
    request("GET", "/api/extensions?profile=" + encodeURIComponent(root.extensionProfile) + "&platform=" + encodeURIComponent(root.extensionPlatform), null, function(data) {
      root.extensionPlugins = data.plugins || []
      root.extensionTools = data.tools || []
      root.extensionMcpServers = data.mcp_servers || []
      root.extensionMcpCatalog = data.mcp_catalog || []
      root.extensionLoading = false
      root.extensionError = ""
    }, function(error) { root.extensionLoading = false; root.extensionError = error.error || "Could not load Hermes capabilities" }, 45000)
  }
  function extensionAction(kind, action, values) {
    var payload = values || ({})
    payload.profile = root.extensionProfile
    payload.kind = kind
    payload.action = action
    root.extensionLoading = true
    request("POST", "/api/extensions/action", payload, function(data) {
      root.extensionLoading = false
      root.notice = data.message || "Hermes profile updated"
      root.loadExtensions(root.extensionProfile, root.extensionPlatform)
    }, function(error) { root.extensionLoading = false; root.extensionError = error.error || "Hermes action failed" }, 150000)
  }
  function providerIndex(id) {
    for (var i = 0; i < root.modelProviders.length; ++i) if (root.modelProviders[i].id === id) return i
    return root.modelProviders.length ? root.providerIndexFallback(id) : -1
  }
  function providerIndexFallback(id) {
    for (var i = 0; i < root.modelProviders.length; ++i) if (root.modelProviders[i].id === "custom") return i
    return 0
  }
  function credentialProviderId() {
    return root.showProviderManager ? root.selectedManagedProvider : (providerInput.currentValue || "auto")
  }
  function credentialProfileSlug() {
    return root.showProviderManager ? root.providerManagerProfile : root.selectedProfile
  }
  function providerEntry(id) {
    var matches = root.modelProviders.filter(function(provider) { return provider.id === id })
    return matches.length ? matches[0] : ({})
  }
  function providerHasKey(provider) {
    var entry = provider || ({})
    var configured = root.profileBySlug(root.providerManagerProfile).configured_api_keys || []
    return (entry.env_vars || []).some(function(name) {
      var isKey = /(_API_KEY|_TOKEN)$/.test(name) || name === "GH_TOKEN" || name === "GITHUB_TOKEN"
      return isKey && configured.indexOf(name) >= 0
    })
  }
  function providerStatus(provider) {
    if (provider.id === root.profileBySlug(root.providerManagerProfile).provider) return "Active for profile"
    if (provider.id === "auto") return "Automatic routing"
    if (provider.id === "custom") return root.profileBySlug(root.providerManagerProfile).custom_api_key_configured ? "Key saved" : "Custom endpoint"
    if (root.providerHasKey(provider)) return "Key saved"
    var acceptsKey = (provider.env_vars || []).some(function(name) { return /(_API_KEY|_TOKEN)$/.test(name) || name === "GH_TOKEN" || name === "GITHUB_TOKEN" })
    return acceptsKey ? "Needs API key" : "Hermes sign-in"
  }
  function providerManagerMatches(provider) {
    var query = providerManagerSearch.text.trim().toLowerCase()
    var text = [provider.id, provider.label, provider.description, (provider.aliases || []).join(" ")].join(" ").toLowerCase()
    if (query && text.indexOf(query) < 0) return false
    var filter = providerManagerFilter.currentIndex
    var status = root.providerStatus(provider)
    if (filter === 1) return provider.id === root.profileBySlug(root.providerManagerProfile).provider
    if (filter === 2) return status === "Key saved" || status === "Active for profile"
    if (filter === 3) return status === "Needs API key"
    if (filter === 4) return status === "Hermes sign-in"
    if (filter === 5) return provider.id === "custom"
    return true
  }
  function openProviderManager() {
    root.providerManagerProfile = root.selectedProfile || (root.profiles.length ? root.profiles[0].slug : "default")
    root.showProviderManager = true
    root.selectManagedProvider(root.profileBySlug(root.providerManagerProfile).provider || "auto")
  }
  function selectManagedProvider(id) {
    root.selectedManagedProvider = id
    var profile = root.profileBySlug(root.providerManagerProfile)
    var active = profile.provider === id
    providerManagerModel.text = active ? (profile.model || "") : ""
    providerManagerBaseUrl.text = active ? (profile.base_url || "") : ""
    providerManagerKey.text = ""
    var configured = profile.configured_api_keys || []
    var candidates = root.providerCredentialOptions(id)
    root.managedCredentialName = ""
    for (var i = 0; i < candidates.length; ++i) {
      if (configured.indexOf(candidates[i]) >= 0) { root.managedCredentialName = candidates[i]; break }
    }
    if (!root.managedCredentialName && candidates.length) root.managedCredentialName = candidates.filter(function(name) { return name.endsWith("_API_KEY") })[0] || candidates[0]
  }
  function saveManagedProvider() {
    var profile = root.profileBySlug(root.providerManagerProfile)
    var baseUrl = root.selectedManagedProvider === "custom" ? providerManagerBaseUrl.text : ""
    request("POST", "/api/profile/save", {slug: root.providerManagerProfile, provider: root.selectedManagedProvider,
      model: providerManagerModel.text, base_url: baseUrl, reasoning: profile.reasoning || "medium", personality: profile.personality || ""}, function() {
      root.notice = root.selectedManagedProvider + " saved for " + root.providerManagerProfile
      root.refresh()
    })
  }
  function chooseCatalogModel(modelId) {
    if (root.showProviderManager) {
      if (root.selectedManagedProvider !== root.modelCatalogProvider) root.selectManagedProvider(root.modelCatalogProvider)
      providerManagerModel.text = modelId
      if (root.modelCatalogProvider !== "custom") providerManagerBaseUrl.text = ""
      root.showModels = false
      root.notice = "Selected " + modelId + " · save provider settings to use for this profile"
    } else {
      modelInput.text = modelId
      providerInput.currentIndex = root.providerIndex(root.modelCatalogProvider)
      if (root.modelCatalogProvider !== "custom") baseUrlInput.text = ""
      root.showModels = false
      root.notice = "Selected " + modelId + " · save profile to apply"
    }
  }
  function providerCredentialEnv() {
    var id = root.credentialProviderId()
    if (id === "custom") return "CUSTOM_API_KEY"
    var entry = root.modelProviders.filter(function(p) { return p.id === id })[0]
    if (!entry) return ""
    var candidates = root.providerCredentialOptions(id)
    if (root.showProviderManager && candidates.indexOf(root.managedCredentialName) >= 0) return root.managedCredentialName
    var configured = root.profileBySlug(root.credentialProfileSlug()).configured_api_keys || []
    for (var i = 0; i < candidates.length; ++i) if (configured.indexOf(candidates[i]) >= 0) return candidates[i]
    var preferred = candidates.filter(function(name) { return name.endsWith("_API_KEY") })
    return preferred.length ? preferred[0] : (candidates[0] || "")
  }
  function providerCredentialOptions(id) {
    if (id === "custom") return ["CUSTOM_API_KEY"]
    var entry = root.modelProviders.filter(function(p) { return p.id === id })[0]
    return entry ? (entry.env_vars || []).filter(function(name) { return /(_API_KEY|_TOKEN)$/.test(name) || name === "GH_TOKEN" || name === "GITHUB_TOKEN" }) : []
  }
  function providerCredentialConfigured() {
    var name = root.providerCredentialEnv()
    if (!name) return false
    var profile = root.profileBySlug(root.credentialProfileSlug())
    if (root.credentialProviderId() === "custom") return !!profile.custom_api_key_configured
    return (profile.configured_api_keys || []).indexOf(name) >= 0
  }
  function providerDescription() {
    var id = root.credentialProviderId()
    var entry = root.modelProviders.filter(function(p) { return p.id === id })[0]
    if (id === "custom") return "Custom or local OpenAI-compatible endpoint"
    if (id === "auto") return "Let Hermes choose the configured route"
    var keyOptions = entry ? (entry.env_vars || []).filter(function(name) { return /(_API_KEY|_TOKEN)$/.test(name) || name === "GH_TOKEN" || name === "GITHUB_TOKEN" }) : []
    var description = entry && entry.description ? entry.description : (entry ? entry.label : id)
    return keyOptions.length ? description : description + " · Hermes sign-in: hermes model"
  }
  function formatRate(value) {
    var n = Number(value || 0)
    if (n > 0 && n < 0.01) return "$" + n.toFixed(4)
    if (n > 0 && n < 0.1) return "$" + n.toFixed(3)
    return "$" + n.toFixed(2)
  }
  function modelExtraPricing(model) {
    var details = []
    if (Number(model.image_rate) > 0) details.push(formatRate(model.image_rate) + " / image")
    if (Number(model.request_rate) > 0) details.push(formatRate(model.request_rate) + " / request")
    return details.join(" · ")
  }
  function profileBySlug(slug) {
    for (var i = 0; i < profiles.length; ++i) if (profiles[i].slug === slug) return profiles[i]
    return ({})
  }
  function assignableProfileNames() {
    return root.profiles.filter(function(p) { return !p.paused }).map(function(p) { return p.slug })
  }
  function taskAssigneeNames() {
    var names = root.assignableProfiles().filter(function(p) { return root.detailAllowedProfiles.indexOf(p.slug) >= 0 }).map(function(p) { return p.slug })
    if (root.selectedTask && root.selectedTask.assignee && names.indexOf(root.selectedTask.assignee) < 0) names.push(root.selectedTask.assignee)
    return names
  }
  function newTaskAssigneeNames() { return root.assignableProfiles().filter(function(p) { return root.newAllowedProfiles.indexOf(p.slug) >= 0 }).map(function(p) { return p.slug }) }
  function activeProjects() { return root.projects.filter(function(p) { return !p.archived }) }
  function saveProfile() {
    var payload = {slug: root.selectedProfile, model: modelInput.text, provider: providerInput.currentValue,
      base_url: baseUrlInput.text,
      reasoning: reasoningInput.text, personality: soulInput.text}
    if (root.advancedMode) {
      try { payload.advanced = JSON.parse(advancedInput.text) }
      catch (e) { root.notice = "Advanced config must be valid JSON"; return }
    }
    request("POST", "/api/profile/save", payload, function() { root.notice = "Profile settings saved"; root.refresh() })
  }
  function keyEnvName() {
    return root.providerCredentialEnv()
  }
  function saveProfileKey() {
    var name = keyEnvName()
    if (!name) { root.notice = "This provider uses Hermes-managed authentication"; return }
    var secretInput = root.showProviderManager ? providerManagerKey : profileKeyInput
    var profileSlug = root.credentialProfileSlug()
    if (!secretInput.text) { root.notice = "Paste a key first"; return }
    request("POST", "/api/profile/key", {slug: profileSlug, provider: root.credentialProviderId(), key_name: name, key: secretInput.text}, function() {
      secretInput.text = ""; root.notice = name + " saved for " + profileSlug; root.refresh()
    })
  }
  function clearProfileKey() {
    var name = keyEnvName()
    if (!name) return
    var secretInput = root.showProviderManager ? providerManagerKey : profileKeyInput
    request("POST", "/api/profile/key", {slug: root.credentialProfileSlug(), provider: root.credentialProviderId(), key_name: name, clear: true}, function() {
      secretInput.text = ""; root.notice = name + " cleared"; root.refresh()
    })
  }
  function taskMatches(t) {
    var q = root.taskSearch.trim().toLowerCase()
    var found = !q || (String(t.title || "") + " " + String(t.body || "") + " " + String(t.assignee || "") + " " + String(t.id || "") + " " + (t.tags || []).join(" ")).toLowerCase().indexOf(q) >= 0
    return found && (root.statusFilterValue === "all" || t.status === root.statusFilterValue) && (root.assigneeFilterValue === "all" || (t.assignee || "") === root.assigneeFilterValue)
  }
  function currentProfile() {
    var match = root.profiles.filter(function(p) { return p.slug === root.selectedProfile })
    return match.length ? match[0] : ({})
  }
  function assignableProfiles() { return root.profiles.filter(function(p) { return !p.paused }) }
  function toggleProfileIn(listName, slug) {
    var source = listName === "new" ? root.newAllowedProfiles : root.detailAllowedProfiles
    var next = source.slice(0), at = next.indexOf(slug)
    if (at >= 0) next.splice(at, 1); else next.push(slug)
    if (listName === "new") root.newAllowedProfiles = next
    else root.detailAllowedProfiles = next
  }
  function setDetailProfileBudget(slug, value) {
    var budgets = Object.assign({}, root.detailProfileBudgets)
    var amount = Number(value)
    if (String(value).trim() && isFinite(amount) && amount >= 0) budgets[slug] = amount
    else delete budgets[slug]
    root.detailProfileBudgets = budgets
  }
  function prepareNewTask() {
    var useSuggestions = root.aiProfilesEnabled
    newTitle.text = ""; newBody.text = ""; newPriority.text = "0"
    newDue.text = ""; newEffort.text = "0"; newCost.text = ""; newTags.text = ""
    newAssignee.currentIndex = 0; newWorkspace.currentIndex = 0; taskTemplate.currentIndex = 0
    root.newAllowedProfiles = []
    root.newProfileBudgets = ({})
    root.aiProfileSuggestions = []
    root.aiProfilesEnabled = useSuggestions
    if (useSuggestions) root.recommendProfilesForTask()
    root.showNewTask = true
  }
  function laneTasks(statuses) { return root.tasks.filter(function(t) { return statuses.indexOf(t.status) >= 0 && root.taskMatches(t) }) }
  function taskProfileLabel(task) {
    var allowed = task.allowed_profiles || []
    if (task.allow_all_profiles) return "All profiles"
    return allowed.length ? allowed.join(", ") : "None selected"
  }
  function createTask() {
    var payload = {board: root.currentBoard, title: newTitle.text, body: newBody.text,
      assignee: newAssignee.currentText === "Unassigned" ? "" : newAssignee.currentText,
      priority: Math.min(4, Math.max(0, Number(newPriority.text) || 0)), workspace: newWorkspace.currentText,
      due_date: newDue.text, effort_hours: Number(newEffort.text) || 0, tags: newTags.text,
      allowed_profiles: root.newAllowedProfiles, profile_budgets: root.newProfileBudgets}
    if (newCost.text.trim()) payload.cost = Number(newCost.text) || 0
    if (!payload.allowed_profiles.length) { root.notice = "Choose at least one eligible profile"; return }
    for (var i = 0; i < payload.allowed_profiles.length; ++i) {
      if (root.newProfileBudgets[payload.allowed_profiles[i]] === undefined || Number(root.newProfileBudgets[payload.allowed_profiles[i]]) <= 0) { root.notice = "Set a positive budget for every selected profile"; return }
    }
    request("POST", "/api/task/create", payload, function(){root.showNewTask = false; root.notice = "Task created"; root.refresh()})
  }
  function resetBoardFilters() {
    root.statusFilterValue = "all"; root.assigneeFilterValue = "all"; root.taskSearch = ""
    statusFilter.currentIndex = 0; assigneeFilter.currentIndex = 0; taskSearchInput.text = ""
  }
  function selectTask(task) {
    root.selectedTask = task
    root.detailAllowedProfiles = task.allow_all_profiles ? root.assignableProfiles().map(function(p) { return p.slug }) : (task.allowed_profiles || []).slice(0)
    root.detailProfileBudgets = Object.assign({}, task.profile_budgets || {})
    root.selectedTaskDetail = ({})
    request("POST", "/api/task/detail", {id: task.id, board: root.currentBoard}, function(d) { root.selectedTaskDetail = d || ({}) })
  }
  function taskComment() {
    request("POST", "/api/task/comment", {id: root.selectedTask.id, board: root.currentBoard, body: taskCommentInput.text}, function(d) {
      taskCommentInput.text = ""; root.selectedTaskDetail = d || ({}); root.notice = "Comment added"; root.refresh()
    })
  }
  function saveTaskMetadata() {
    var plan = {id: root.selectedTask.id, board: root.currentBoard, due_date: taskDue.text, tags: taskTags.text,
      effort_hours: Number(taskEffort.text) || 0, allowed_profiles: root.detailAllowedProfiles, profile_budgets: root.detailProfileBudgets}
    for (var i = 0; i < plan.allowed_profiles.length; ++i) {
      if (root.detailProfileBudgets[plan.allowed_profiles[i]] === undefined || Number(root.detailProfileBudgets[plan.allowed_profiles[i]]) <= 0) { root.notice = "Set a positive budget for each eligible profile"; return }
    }
    if (taskCost.text.trim()) plan.cost = Number(taskCost.text) || 0
    request("POST", "/api/task/estimate", plan, function() {
      root.notice = "Task planning details saved"; root.refresh()
    })
  }
  function openProject(slug) {
    request("POST", "/api/project/select", {slug: slug}, function() {
      root.currentBoard = slug; root.page = "Kanban"; root.statusFilterValue = "all"; root.assigneeFilterValue = "all"; root.selectedTaskIds = []; root.selectedTask = null; root.refresh(slug)
    })
  }
  function setManagerProfile(slug) {
    var target = slug || root.managerProfile
    if (!target) return
    request("POST", "/api/profile/manage", {slug: target, action: "manager"}, function(data) {
      root.managerProfile = data.manager_profile || ""
      root.notice = root.managerProfile ? "Hermes LW manager: " + root.managerProfile : "Manager profile cleared"
      root.refresh()
    })
  }
  function setStartupBoard(slug) {
    request("POST", "/api/project/select", {slug: slug}, function() {
      root.currentBoard = slug
      root.selectedTask = null
      root.selectedTaskIds = []
      root.refresh(slug)
      root.notice = "Startup board set to " + slug
    })
  }
  function editProject(project) {
    root.editingProject = project || null
    projectName.text = project ? project.name : ""
    projectSlug.text = project ? project.slug : ""
    projectDescription.text = project ? (project.description || "") : ""
    projectOwner.text = project ? (project.owner || "") : ""
    projectBudget.text = project ? String(project.budget || 0) : "0"
    projectDue.text = project ? (project.due_date || "") : ""
    projectColor.text = project ? (project.color || "#3584e4") : "#3584e4"
    root.showProjectEditor = true
  }
  function saveProject() {
    var data = {name: projectName.text, slug: projectSlug.text, description: projectDescription.text,
      owner: projectOwner.text, budget: Number(projectBudget.text) || 0, due_date: projectDue.text, color: projectColor.text}
    var editing = root.editingProject !== null
    request("POST", root.editingProject ? "/api/project/save" : "/api/project/create", data, function() {
      root.showProjectEditor = false; root.notice = editing ? "Project updated" : "Project created"; if (!editing) root.currentBoard = data.slug; root.refresh(editing ? root.currentBoard : data.slug)
    })
  }
  function exportProject(slug) {
    request("POST", "/api/project/export", {slug: slug}, function() { root.notice = "Project export saved in Downloads" })
  }
  function saveCurrentView() {
    if (!viewName.text.trim()) { root.notice = "Name this saved view first"; return }
    request("POST", "/api/views/save", {name: viewName.text, board: root.currentBoard,
      status: statusFilter.currentIndex === 0 ? "all" : statusFilter.currentText.toLowerCase(),
      assignee: assigneeFilter.currentIndex === 0 ? "all" : assigneeFilter.currentText, query: root.taskSearch}, function(d) {
      root.savedViews = d.views || []; viewName.text = ""; root.notice = "Board view saved"
    })
  }
  function applySavedView(name) {
    var matches = root.savedViews.filter(function(v) { return v.name === name && v.board === root.currentBoard })
    if (!matches.length) return
    root.statusFilterValue = matches[0].status || "all"
    root.assigneeFilterValue = matches[0].assignee || "all"
    root.taskSearch = matches[0].query || ""
    taskSearchInput.text = root.taskSearch
    statusFilter.currentIndex = root.statusFilterValue === "all" ? 0 : statusFilter.model.indexOf(root.statusFilterValue.charAt(0).toUpperCase() + root.statusFilterValue.slice(1))
    assigneeFilter.currentIndex = root.assigneeFilterValue === "all" ? 0 : assigneeFilter.model.indexOf(root.assigneeFilterValue)
  }
  function toggleTaskSelection(id) {
    var ids = root.selectedTaskIds.slice(0), at = ids.indexOf(id)
    if (at >= 0) ids.splice(at, 1); else ids.push(id)
    root.selectedTaskIds = ids
  }
  function bulkAction(action) {
    if (!root.selectedTaskIds.length) { root.notice = "Select some task cards first"; return }
    request("POST", "/api/task/bulk", {board: root.currentBoard, ids: root.selectedTaskIds, action: action,
      assignee: bulkAssignee.currentText === "Unassigned" ? "none" : bulkAssignee.currentText}, function(d) {
      root.notice = action + " applied to " + d.count + " tasks"; root.selectedTaskIds = []; root.refresh()
    })
  }
  function applyTaskTemplate(name) {
    var templates = [
      {title: "Bug report", body: "## Problem\n\n## Steps to reproduce\n\n## Expected result\n\n## Acceptance criteria\n- [ ] ", priority: 2, workspace: "scratch"},
      {title: "Research brief", body: "## Question\n\n## Context\n\n## Deliverable\n\n## Sources and acceptance criteria\n- [ ] ", priority: 1, workspace: "scratch"},
      {title: "Implementation task", body: "## Goal\n\n## Constraints\n\n## Acceptance criteria\n- [ ] Tests or checks\n- [ ] Summary of changes", priority: 1, workspace: "worktree"},
      {title: "Code review", body: "## Change to review\n\n## Focus areas\n- Correctness\n- Security\n- Maintainability\n\n## Findings required", priority: 2, workspace: "worktree"}
    ]
    var chosen = templates.filter(function(t) { return t.title === name })[0] || root.taskTemplates.filter(function(t) { return t.title === name })[0]
    if (chosen) { newTitle.text = chosen.title; newBody.text = chosen.body; newPriority.text = String(chosen.priority || 0); newWorkspace.currentIndex = chosen.workspace === "worktree" ? 1 : 0 }
  }
  function saveTaskTemplate() {
    if (!newTitle.text.trim()) { root.notice = "Add a task title before saving a template"; return }
    request("POST", "/api/templates/save", {title: newTitle.text, body: newBody.text, priority: Number(newPriority.text) || 0,
      workspace: newWorkspace.currentText}, function(d) { root.taskTemplates = d.templates || []; root.notice = "Task template saved" })
  }
  function createProfile() {
    var payload = {slug: newProfileSlug.text, description: newProfileRole.text, clone_mode: cloneMode.currentIndex === 0 ? "empty" : cloneMode.currentIndex === 1 ? "clone" : "clone_all",
      source: cloneSource.currentText, copy_api_key: copyApiKey.checked, openrouter_api_key: newProfileKey.text, personality: generatedSoul.text}
    request("POST", "/api/profile/create", payload, function(d) {
      root.showCreateProfile = false
      root.selectedProfile = d.profile
      root.page = "Profiles"
      root.notice = "Profile " + d.profile + " created"
      root.refresh()
    })
  }
  function generatePersonality() {
    if (!newProfileSlug.text.trim()) { root.notice = "Enter a profile name before generating its prompt"; return }
    root.generatingPersonality = true
    root.request("POST", "/api/profile/generate", {name: newProfileSlug.text, role: newProfileRole.text, generator_profile: "default"}, function(d) {
      root.generatingPersonality = false
      generatedSoul.text = d.personality || ""
      root.notice = "Personality prompt generated · review before creating"
    })
  }
  function profileControl(action) {
    request("POST", "/api/profile/manage", {slug: root.selectedProfile, action: action}, function(d) {
      root.refresh()
      root.notice = action === "manager" ? (d.manager_profile ? "Hermes LW manager: " + d.manager_profile : "Manager profile cleared") : (d.paused_profiles.indexOf(root.selectedProfile) >= 0 ? "Paused for new Hermes LW assignments · running work continues" : "Profile resumed")
    })
  }
  function deleteSelectedProfile() {
    request("POST", "/api/profile/delete", {slug: root.selectedProfile}, function() {
      root.showDeleteProfile = false
      root.selectedProfile = "default"
      root.refresh()
      root.notice = "Profile deleted"
    })
  }
  function toggleModelFavorite(modelId) {
    var shouldFavorite = root.favoriteModels.indexOf(modelId) < 0
    request("POST", "/api/favorite/model", {id: modelId, favorite: shouldFavorite}, function(d) { root.favoriteModels = d.favorite_models || []; root.refresh() })
  }
  function savePrompt() {
    var p = root.editingPrompt || ({})
    request("POST", "/api/prompt/save", {id: p.id || "", title: promptTitle.text, body: promptBody.text, favorite: promptFavorite.checked}, function() {
      root.showPromptEditor = false; root.editingPrompt = null; root.refresh(); root.notice = "Prompt saved"
    })
  }
  function editPrompt(prompt) {
    root.editingPrompt = prompt || null
    promptTitle.text = prompt ? prompt.title : ""
    promptBody.text = prompt ? prompt.body : ""
    promptFavorite.checked = prompt ? !!prompt.favorite : true
    root.showPromptEditor = true
  }
  function usePrompt(prompt) {
    root.showHermes = true
    hermesPrompt.text = prompt.body
  }
  function closeTopDialog() {
    if (root.showModels) root.showModels = false
    else if (root.showProviderManager) root.showProviderManager = false
    else if (root.showDeleteProfile) root.showDeleteProfile = false
    else if (root.showCreateProfile) root.showCreateProfile = false
    else if (root.showPromptEditor) root.showPromptEditor = false
    else if (root.selectedTask !== null) root.selectedTask = null
    else if (root.showHermes) root.showHermes = false
    else if (root.showNewTask) root.showNewTask = false
    else if (root.showProjectEditor) root.showProjectEditor = false
  }
  function deleteSavedView(name) {
    var view = root.savedViews.filter(function(v) { return v.name === name && v.board === root.currentBoard })[0]
    if (!view) return
    request("POST", "/api/views/delete", {id: view.id}, function(d) { root.savedViews = d.views || []; root.notice = "Saved view deleted" })
  }
  function toggleTheme() {
    var next = root.darkMode ? "light" : "dark"
    request("POST", "/api/theme", {theme: next}, function(data) { root.darkMode = data.theme === "dark" })
  }
  function togglePromptFavorite(prompt) {
    request("POST", "/api/prompt/save", {id: prompt.id, title: prompt.title, body: prompt.body, favorite: !prompt.favorite}, function() { root.refresh() })
  }
  function act(task, action, data) {
    var payload = data || ({})
    payload.id = task.id; payload.action = action; payload.board = root.currentBoard
    request("POST", "/api/task/action", payload, function() { root.notice = "Task updated"; root.selectedTask = null; root.refresh() })
  }
  function money(value) { return "$" + Number(value || 0).toFixed(2) }
  function statusColor(status) {
    if (status === "running") return root.blue
    if (status === "review") return root.amber
    if (status === "blocked") return root.red
    if (status === "done") return root.accent
    return root.muted
  }

  Shortcut { sequence: "Ctrl+N"; onActivated: root.prepareNewTask() }
  Shortcut { sequence: "Ctrl+Shift+N"; onActivated: { root.showCreateProfile = true; newProfileSlug.text = ""; newProfileRole.text = ""; generatedSoul.text = ""; newProfileKey.text = "" } }
  Shortcut { sequence: "Ctrl+R"; onActivated: root.refresh() }
  Shortcut { sequence: "Ctrl+F"; onActivated: { if (root.showModels) { modelSearch.forceActiveFocus(); modelSearch.selectAll() } else { root.page = "Kanban"; taskSearchInput.forceActiveFocus(); taskSearchInput.selectAll() } } }
  Shortcut { sequence: "Ctrl+1"; onActivated: root.page = "Overview" }
  Shortcut { sequence: "Ctrl+2"; onActivated: root.page = "Projects" }
  Shortcut { sequence: "Ctrl+3"; onActivated: root.page = "Profiles" }
  Shortcut { sequence: "Ctrl+4"; onActivated: root.page = "Kanban" }
  Shortcut { sequence: "Ctrl+5"; onActivated: root.page = "Prompts" }
  Shortcut { sequence: "Ctrl+6"; onActivated: root.page = "Models & Providers" }
  Shortcut { sequence: "Ctrl+7"; onActivated: root.page = "Options" }
  Shortcut { sequence: "Ctrl+8"; onActivated: { root.page = "Plugins & Tools"; root.loadExtensions() } }
  Shortcut { sequence: "Ctrl+9"; onActivated: root.page = "Task Advisor" }
  Shortcut { sequence: "Escape"; enabled: root.showModels || root.showProviderManager || root.showDeleteProfile || root.showCreateProfile || root.showPromptEditor || root.selectedTask !== null || root.showHermes || root.showNewTask || root.showProjectEditor; onActivated: root.closeTopDialog() }
  Timer { interval: 10000; running: root.pendingRequests === 0 && !root.modalOpen(); repeat: true; onTriggered: root.refresh() }
  Component.onCompleted: { root.refresh(); root.loadModelProviders(); if (root.page === "Plugins & Tools") root.loadExtensions(root.selectedProfile, root.extensionPlatform) }
  onSelectedProfileChanged: {
    if (root.page === "Plugins & Tools") root.loadExtensions(root.selectedProfile, root.extensionPlatform)
    var p = root.profileBySlug(root.selectedProfile)
    if (p.slug) {
      modelInput.text = p.model || ""
      providerInput.currentIndex = root.providerIndex(p.provider || "auto")
      baseUrlInput.text = p.base_url || ""
      reasoningInput.text = p.reasoning || "medium"
      soulInput.text = p.personality || ""
      profileKeyInput.text = ""
    }
  }
  onPageChanged: {
    if (page === "Plugins & Tools") root.loadExtensions(root.selectedProfile, root.extensionPlatform)
    if (page === "Task Advisor" && root.modelCatalogProvider && root.modelCatalogProvider !== "auto" && !root.modelCatalog.length) root.loadModelCatalog(false)
  }

  FloatingWindow {
    id: win
    visible: true
    title: "Hermes LW"
    color: root.bg
    implicitWidth: 1500
    implicitHeight: 960
    minimumSize: Qt.size(1150, 720)

    Rectangle {
      anchors.fill: parent
      color: root.bg

      Column {
        id: appFrame
        anchors.fill: parent
        spacing: 0

        // XP-style command toolbar
        Rectangle {
          width: parent.width; height: 40; color: root.bg
          Rectangle { anchors.bottom: parent.bottom; width: parent.width; height: 1; color: root.border }
          Row { anchors.fill: parent; anchors.leftMargin: 8; anchors.rightMargin: 8; spacing: 3
            Repeater { model: ["New project", "New task", "Add profile", "Model catalog", "Refresh", "Options"]
              delegate: Rectangle { required property string modelData; required property int index; width: [88, 78, 88, 96, 66, 72][index]; height: 32; anchors.verticalCenter: parent.verticalCenter; color: toolbarHover.containsMouse ? root.hoverFill : root.raised; border.color: root.border
                Row { anchors.centerIn: parent; spacing: 5
                  Text { text: ["▣", "+", "◉", "⌕", "↻", "⚙"][index]; color: root.accent; font.pixelSize: 12; anchors.verticalCenter: parent.verticalCenter }
                  Text { text: modelData; color: root.text; font.pixelSize: 9; anchors.verticalCenter: parent.verticalCenter }
                }
                MouseArea { id: toolbarHover; anchors.fill: parent; hoverEnabled: true; onClicked: {
                  if (index === 0) root.editProject(null)
                  else if (index === 1) root.prepareNewTask()
                  else if (index === 2) { root.showCreateProfile = true; newProfileSlug.text = ""; newProfileRole.text = ""; generatedSoul.text = ""; newProfileKey.text = "" }
                  else if (index === 3) root.openModelCatalog()
                  else if (index === 4) root.refresh()
                  else root.page = "Options"
                } }
              }
            }
            Rectangle { width: 1; height: 25; color: root.border; anchors.verticalCenter: parent.verticalCenter; anchors.leftMargin: 6 }
            Item { width: Math.max(1, parent.width - 8 - 88 - 78 - 88 - 96 - 66 - 72 - 25 - 152); height: 1 }
            Rectangle { width: 34; height: 30; anchors.verticalCenter: parent.verticalCenter; color: root.raised; border.color: root.border
              Text { anchors.centerIn: parent; text: root.darkMode ? "☼" : "☾"; color: root.accent; font.pixelSize: 15 }
              MouseArea { anchors.fill: parent; onClicked: root.toggleTheme() }
              ToolTip.visible: themeTip.containsMouse; ToolTip.text: root.darkMode ? "Switch to light mode" : "Switch to dark mode"
              MouseArea { id: themeTip; anchors.fill: parent; hoverEnabled: true; acceptedButtons: Qt.NoButton }
            }
            Rectangle { width: 108; height: 30; anchors.verticalCenter: parent.verticalCenter; color: root.raised; border.color: root.border
              Row { anchors.centerIn: parent; spacing: 5; Text { text: "✳"; color: root.accent; font.pixelSize: 12 } Text { text: "Ask Hermes"; color: root.text; font.pixelSize: 9 } }
              MouseArea { anchors.fill: parent; onClicked: root.showHermes = true }
            }
          }
        }

        Row {
          id: workspaceArea
          width: parent.width; height: parent.height - 59; spacing: 0

          // Navigation tree
          Rectangle {
            width: 194; height: parent.height; color: root.sidebarFill
            Rectangle { anchors.right: parent.right; width: 1; height: parent.height; color: root.border }
            Column { anchors.fill: parent; anchors.margins: 8; spacing: 4
              Row { width: parent.width; height: 34; spacing: 8
                Rectangle { width: 23; height: 23; color: "#245ed0"; border.color: "#ffffff"; anchors.verticalCenter: parent.verticalCenter
                  Text { anchors.centerIn: parent; text: "H"; color: "#ffffff"; font.pixelSize: 14; font.bold: true }
                }
                Column { anchors.verticalCenter: parent.verticalCenter; spacing: 1
                  Text { text: "Hermes LW"; color: root.text; font.pixelSize: 11; font.bold: true }
                  Text { text: "WORKSPACE"; color: root.muted; font.pixelSize: 8; font.letterSpacing: 0.7 }
                }
              }
              Rectangle { width: parent.width; height: 1; color: root.border }
              Repeater { model: ["Overview", "Projects", "Models & Providers", "Profiles", "Plugins & Tools", "Kanban", "Prompts", "Task Advisor", "Options"]
                delegate: Rectangle { required property string modelData; width: parent.width; height: 25; color: root.page === modelData ? root.selectedFill : "transparent"; border.color: root.page === modelData ? root.blue : "transparent"
                  Row { anchors.fill: parent; anchors.leftMargin: 8; spacing: 8
                    Text { text: modelData === "Overview" ? "⌂" : modelData === "Projects" ? "▣" : modelData === "Models & Providers" || modelData === "Options" ? "⚙" : modelData === "Profiles" ? "◉" : modelData === "Plugins & Tools" ? "⌘" : modelData === "Kanban" ? "▦" : modelData === "Task Advisor" ? "◎" : "✦"; color: root.page === modelData ? "#ffffff" : root.accent; font.pixelSize: 12; anchors.verticalCenter: parent.verticalCenter }
                    Text { text: modelData; color: root.page === modelData ? "#ffffff" : root.text; font.pixelSize: 10; anchors.verticalCenter: parent.verticalCenter }
                  }
                  MouseArea { anchors.fill: parent; onClicked: root.page = modelData }
                }
              }
              Rectangle { width: parent.width; height: 1; color: root.border }
              Text { text: "PROJECTS · " + root.projects.length + "  ›"; color: root.accent; font.pixelSize: 8; font.bold: true; anchors.leftMargin: 7; height: 17; MouseArea { anchors.fill: parent; onClicked: root.page = "Projects" } }
              Repeater { model: root.projects.slice(0, 6)
                delegate: Rectangle { required property var modelData; width: parent.width; height: 22; color: modelData.slug === root.currentBoard ? root.selectedFill : "transparent"
                  Text { anchors.left: parent.left; anchors.leftMargin: 9; anchors.verticalCenter: parent.verticalCenter; width: parent.width - 14; text: (modelData.icon || "▸") + "  " + (modelData.name || modelData.slug); color: modelData.slug === root.currentBoard ? "#ffffff" : root.text; font.pixelSize: 9; elide: Text.ElideRight }
                  MouseArea { anchors.fill: parent; enabled: !modelData.archived; onClicked: root.openProject(modelData.slug) }
                }
              }
              Rectangle { width: parent.width; height: 1; color: root.border }
              Text { text: (root.page === "Models & Providers" ? "BACKEND PROFILES" : "PROFILES") + "  ·  " + root.profiles.length + "  ›"; color: root.accent; font.pixelSize: 8; font.bold: true; height: 17; MouseArea { anchors.fill: parent; onClicked: root.page = "Profiles" } }
              Repeater { model: root.profiles.slice(0, 7)
                delegate: Rectangle { required property var modelData; width: parent.width; height: 22; color: root.selectedProfile === modelData.slug ? root.selectedFill : "transparent"
                  Row { anchors.fill: parent; anchors.leftMargin: 3; spacing: 7
                  Rectangle { width: 6; height: 6; radius: 2; color: modelData.paused ? root.amber : modelData.active ? root.accent : root.border; anchors.verticalCenter: parent.verticalCenter }
                  Text { text: modelData.slug; color: root.selectedProfile === modelData.slug ? "#ffffff" : root.text; font.pixelSize: 9; elide: Text.ElideRight; width: parent.width - 18; anchors.verticalCenter: parent.verticalCenter }
                  }
                  MouseArea { anchors.fill: parent; onClicked: { root.selectedProfile = modelData.slug; if (root.page !== "Models & Providers") root.page = "Profiles" } }
                }
              }
              Item { width: 1; height: 1; Layout.fillHeight: true }
              Rectangle { width: parent.width; height: 44; color: root.surface; border.color: root.border
                Column { anchors.fill: parent; anchors.margins: 6; spacing: 3
                  Text { text: "Hermes Agent"; color: root.text; font.pixelSize: 9; font.bold: true }
                  Text { text: root.backendConnected ? "● Hermes backend connected" : "○ Waiting for Hermes backend"; color: root.backendConnected ? root.accent : root.amber; font.pixelSize: 8 }
                }
              }
            }
          }

          Column {
            id: mainPane
            width: parent.width - 194; height: parent.height; spacing: 0
            Rectangle {
              width: parent.width; height: 42
              gradient: Gradient { GradientStop { position: 0; color: root.darkMode ? "#405c85" : "#3c83d5" } GradientStop { position: 1; color: root.darkMode ? "#233b60" : "#174d9b" } }
              Rectangle { anchors.bottom: parent.bottom; width: parent.width; height: 1; color: "#0a3683" }
              Row { anchors.fill: parent; anchors.leftMargin: 14; anchors.rightMargin: 12; spacing: 8
                Column { anchors.verticalCenter: parent.verticalCenter; spacing: 2
                  Text { text: root.page === "Overview" ? "Workspace" : root.page === "Projects" ? "Projects" : root.page === "Profiles" ? "Agent profiles" : root.page === "Models & Providers" ? "Models & Providers" : root.page === "Plugins & Tools" ? "Plugins & Tools" : root.page === "Options" ? "Options" : root.page === "Kanban" ? "Task board" : root.page === "Task Advisor" ? "Task Advisor" : root.page === "Prompts" ? "Prompt library" : "Hermes LW"; color: "#ffffff"; font.pixelSize: 14; font.bold: true }
                  Text { text: root.page === "Kanban" ? (root.projectInfo.name || "Default") + "  ·  " + root.tasks.length + " tasks" : root.page === "Models & Providers" ? "Choose a backend, model, and profile credentials" : root.page === "Plugins & Tools" ? "Profile-scoped plugins, tools, and MCP app connections" : root.page === "Task Advisor" ? "Choose a model and build a task prompt within your budget" : root.page === "Options" ? "App-wide Hermes LW settings" : "Hermes LW"; color: "#e5efff"; font.pixelSize: 8 }
                }
                Item { width: Math.max(1, parent.width - 600); height: 1 }
                Text { width: 190; text: root.managerProfile ? "Manager: " + root.managerProfile : "No manager selected"; color: "#ffffff"; font.pixelSize: 9; elide: Text.ElideRight; horizontalAlignment: Text.AlignRight; anchors.verticalCenter: parent.verticalCenter; MouseArea { anchors.fill: parent; onClicked: root.page = "Profiles" } }
                Text { text: root.darkMode ? "Dark" : "Light"; color: "#ffffff"; font.pixelSize: 8; anchors.verticalCenter: parent.verticalCenter }
              }
            }
            Item { width: parent.width; height: parent.height - 42
            // OVERVIEW: compact desktop workspace summary
            Column { anchors.fill: parent; anchors.margins: 12; spacing: 8; visible: root.page === "Overview"
              Row { width: parent.width; height: 25; spacing: 8
                Text { text: "Workspace summary"; color: root.text; font.pixelSize: 13; font.bold: true; anchors.verticalCenter: parent.verticalCenter }
                Item { width: 1; height: 1; Layout.fillWidth: true }
                Text { text: "Project: " + (root.projectInfo.name || "Default"); color: root.muted; font.pixelSize: 9; anchors.verticalCenter: parent.verticalCenter }
              }
              Rectangle { width: parent.width; height: 76; color: root.surface; border.color: root.border
                Row { anchors.fill: parent; anchors.margins: 10; spacing: 0
                  Repeater { model: [
                    {label:"PROFILES", value:root.profiles.length},
                    {label:"ACTIVE TASKS", value:root.tasks.filter(function(t){return t.status !== "done" && t.status !== "archived"}).length},
                    {label:"PROJECTS", value:root.projects.length},
                    {label:"ESTIMATED COST", value:money(root.tasks.reduce(function(a,t){return a + Number(t.estimated_cost || 0)},0))}
                  ]
                    delegate: Item { required property var modelData; required property int index; width: parent.width / 4; height: parent.height
                      Text { anchors.top: parent.top; text: modelData.label; color: root.muted; font.pixelSize: 8; font.bold: true }
                      Text { anchors.bottom: parent.bottom; text: modelData.value; color: root.text; font.pixelSize: 17; font.bold: true }
                      Rectangle { visible: index < 3; anchors.right: parent.right; height: parent.height; width: 1; color: root.border }
                    }
                  }
                }
              }
              Row { width: parent.width; height: 22; spacing: 8
                Text { text: "Recent tasks"; color: root.text; font.pixelSize: 11; font.bold: true; anchors.verticalCenter: parent.verticalCenter }
                Item { width: 1; height: 1; Layout.fillWidth: true }
                Text { text: "Open board →"; color: root.accent; font.pixelSize: 9; anchors.verticalCenter: parent.verticalCenter; MouseArea { anchors.fill: parent; onClicked: root.page = "Kanban" } }
              }
              Rectangle { width: parent.width; height: 22; color: root.raised; border.color: root.border
                Row { anchors.fill: parent; anchors.leftMargin: 8; anchors.rightMargin: 8
                  Text { width: parent.width * .47; text: "TASK"; color: root.muted; font.pixelSize: 8; font.bold: true; anchors.verticalCenter: parent.verticalCenter }
                  Text { width: parent.width * .18; text: "ASSIGNEE"; color: root.muted; font.pixelSize: 8; font.bold: true; anchors.verticalCenter: parent.verticalCenter }
                  Text { width: parent.width * .16; text: "STATUS"; color: root.muted; font.pixelSize: 8; font.bold: true; anchors.verticalCenter: parent.verticalCenter }
                  Text { width: parent.width * .19; text: "ESTIMATE"; color: root.muted; font.pixelSize: 8; font.bold: true; horizontalAlignment: Text.AlignRight; anchors.verticalCenter: parent.verticalCenter }
                }
              }
              Flickable { width: parent.width; height: Math.max(80, parent.height - 205); clip: true; contentHeight: overviewTaskRows.implicitHeight
                Column { id: overviewTaskRows; width: parent.width
                  Repeater { model: root.tasks.slice(0, 30)
                    delegate: Rectangle { required property var modelData; required property int index; width: parent.width; height: 29; color: index % 2 ? root.surface : root.sidebarFill
                      Rectangle { anchors.bottom: parent.bottom; width: parent.width; height: 1; color: root.border; opacity: .5 }
                      Row { anchors.fill: parent; anchors.leftMargin: 8; anchors.rightMargin: 8
                        Text { width: parent.width * .47; text: modelData.title; color: root.text; font.pixelSize: 9; elide: Text.ElideRight; anchors.verticalCenter: parent.verticalCenter }
                        Text { width: parent.width * .18; text: modelData.assignee || "Unassigned"; color: root.muted; font.pixelSize: 9; elide: Text.ElideRight; anchors.verticalCenter: parent.verticalCenter }
                        Text { width: parent.width * .16; text: modelData.status; color: root.statusColor(modelData.status); font.pixelSize: 9; anchors.verticalCenter: parent.verticalCenter }
                        Text { width: parent.width * .19; text: modelData.has_estimate ? money(modelData.estimated_cost) : "—"; color: root.text; font.pixelSize: 9; horizontalAlignment: Text.AlignRight; anchors.verticalCenter: parent.verticalCenter }
                      }
                      MouseArea { anchors.fill: parent; onClicked: { root.selectTask(modelData); root.page = "Kanban" } }
                    }
                  }
                  Text { visible: root.tasks.length === 0; text: "No tasks yet. Create a task from the toolbar or open Kanban."; color: root.muted; font.pixelSize: 10; padding: 12 }
                }
              }
              Rectangle { width: parent.width; height: 20; color: root.sidebarFill; border.color: root.border
                Text { anchors.left: parent.left; anchors.leftMargin: 7; anchors.verticalCenter: parent.verticalCenter; text: "Agent profiles: " + root.profiles.map(function(p){return p.slug + (p.paused ? " (paused)" : "")}).join("   ·   "); color: root.muted; font.pixelSize: 8; elide: Text.ElideRight; width: parent.width - 14 }
              }
            }

            // PROJECT PORTFOLIO: Windows-style details list
            Column { anchors.fill: parent; anchors.margins: 12; spacing: 8; visible: root.page === "Projects"
              Row { width: parent.width; height: 30; spacing: 8
                Text { text: "Project portfolio"; color: root.text; font.pixelSize: 13; font.bold: true; anchors.verticalCenter: parent.verticalCenter }
                Text { text: root.projects.length + " projects"; color: root.muted; font.pixelSize: 9; anchors.verticalCenter: parent.verticalCenter }
                Item { width: 1; height: 1; Layout.fillWidth: true }
                Rectangle { width: 85; height: 25; color: root.raised; border.color: root.border
                  Text { anchors.centerIn: parent; text: "Export JSON"; color: root.text; font.pixelSize: 8 }
                  MouseArea { anchors.fill: parent; onClicked: root.exportProject(root.currentBoard || "default") }
                }
                Rectangle { width: 94; height: 25; color: root.selectedFill; border.color: root.blue
                  Text { anchors.centerIn: parent; text: "+ New project"; color: "#ffffff"; font.pixelSize: 8; font.bold: true }
                  MouseArea { anchors.fill: parent; onClicked: root.editProject(null) }
                }
              }
              Rectangle { width: parent.width; height: 24; color: root.raised; border.color: root.border
                Row { anchors.fill: parent; anchors.leftMargin: 7; anchors.rightMargin: 7
                  Text { width: parent.width * .23; text: "NAME"; color: root.muted; font.pixelSize: 8; font.bold: true; anchors.verticalCenter: parent.verticalCenter }
                  Text { width: parent.width * .12; text: "OWNER"; color: root.muted; font.pixelSize: 8; font.bold: true; anchors.verticalCenter: parent.verticalCenter }
                  Text { width: parent.width * .12; text: "DUE DATE"; color: root.muted; font.pixelSize: 8; font.bold: true; anchors.verticalCenter: parent.verticalCenter }
                  Text { width: parent.width * .12; text: "TASKS"; color: root.muted; font.pixelSize: 8; font.bold: true; anchors.verticalCenter: parent.verticalCenter }
                  Text { width: parent.width * .15; text: "EST. COST / BUDGET"; color: root.muted; font.pixelSize: 8; font.bold: true; anchors.verticalCenter: parent.verticalCenter }
                  Text { width: parent.width * .10; text: "STATE"; color: root.muted; font.pixelSize: 8; font.bold: true; anchors.verticalCenter: parent.verticalCenter }
                  Text { width: parent.width * .16; text: "ACTIONS"; color: root.muted; font.pixelSize: 8; font.bold: true; anchors.verticalCenter: parent.verticalCenter }
                }
              }
              Flickable { width: parent.width; height: parent.height - 70; clip: true; contentHeight: projectRows.implicitHeight
                Column { id: projectRows; width: parent.width
                  Repeater { model: root.projects
                    delegate: Rectangle { id: projectRow; required property var modelData; required property int index; width: parent.width; height: 38; color: index % 2 ? root.surface : root.sidebarFill
                      Rectangle { anchors.bottom: parent.bottom; width: parent.width; height: 1; color: root.border; opacity: .55 }
                      Row { anchors.fill: parent; anchors.leftMargin: 7; anchors.rightMargin: 7; spacing: 0
                        Text { width: parent.width * .23; text: (modelData.icon || "▣") + "  " + (modelData.name || modelData.slug); color: root.text; font.pixelSize: 9; font.bold: true; elide: Text.ElideRight; anchors.verticalCenter: parent.verticalCenter }
                        Text { width: parent.width * .12; text: modelData.owner || "Unassigned"; color: root.muted; font.pixelSize: 9; elide: Text.ElideRight; anchors.verticalCenter: parent.verticalCenter }
                        Text { width: parent.width * .12; text: modelData.due_date || "—"; color: root.muted; font.pixelSize: 9; anchors.verticalCenter: parent.verticalCenter }
                        Text { width: parent.width * .12; text: (modelData.counts && modelData.counts.done || 0) + " / " + (modelData.total || 0); color: root.text; font.pixelSize: 9; anchors.verticalCenter: parent.verticalCenter }
                        Text { width: parent.width * .15; text: money(modelData.estimated_cost) + (Number(modelData.budget || 0) > 0 ? " / " + money(modelData.budget) : ""); color: Number(modelData.budget || 0) > 0 && Number(modelData.estimated_cost || 0) > Number(modelData.budget) ? root.red : root.text; font.pixelSize: 9; elide: Text.ElideRight; anchors.verticalCenter: parent.verticalCenter }
                        Text { width: parent.width * .10; text: modelData.archived ? "Archived" : modelData.slug === root.currentBoard ? "Open" : "Active"; color: modelData.archived ? root.muted : root.accent; font.pixelSize: 9; anchors.verticalCenter: parent.verticalCenter }
                        Row { width: parent.width * .16; anchors.verticalCenter: parent.verticalCenter; spacing: 4
                          Repeater { model: ["Open", "Edit", "Export"]
                            delegate: Rectangle { required property string modelData; width: 43; height: 22; color: root.raised; border.color: root.border
                              Text { anchors.centerIn: parent; text: modelData; color: root.text; font.pixelSize: 8 }
                              MouseArea { anchors.fill: parent; enabled: !(modelData === "Open" && projectRow.modelData.archived); onClicked: { if (modelData === "Open") root.openProject(projectRow.modelData.slug); else if (modelData === "Edit") root.editProject(projectRow.modelData); else root.exportProject(projectRow.modelData.slug) } }
                            }
                          }
                        }
                      }
                    }
                  }
                  Text { visible: root.projects.length === 0; text: "No projects. Choose New project to create one."; color: root.muted; font.pixelSize: 10; padding: 12 }
                }
              }
            }

            // PROFILES
            Row {
              anchors.fill: parent; anchors.margins: 24; spacing: 16; visible: root.page === "Profiles" || root.page === "Models & Providers"
              Rectangle { width: 260; height: parent.height; radius: 2; color: root.surface; border.color: root.border
                Column { anchors.fill: parent; anchors.margins: 14; spacing: 10
                  Row { width: parent.width; spacing: 8
                    Text { text: "ALL PROFILES"; color: root.muted; font.pixelSize: 9; font.bold: true; font.letterSpacing: 1.1 }
                    Item { width: 1; height: 1; Layout.fillWidth: true }
                    Text { text: root.profiles.length; color: root.accent; font.pixelSize: 10 }
                    Rectangle { width: 22; height: 22; radius: 2; color: root.selectedFill
                      Text { anchors.centerIn: parent; text: "+"; color: root.accent; font.pixelSize: 16 }
                      MouseArea { anchors.fill: parent; onClicked: { root.showCreateProfile = true; newProfileSlug.text = ""; newProfileRole.text = ""; generatedSoul.text = ""; newProfileKey.text = "" } }
                    }
                  }
                  TextField { leftPadding: 9; rightPadding: 9; id: profileSearchInput; width: parent.width; height: 30; placeholderText: "Find a profile…"; placeholderTextColor: root.muted; color: root.text; font.pixelSize: 9; background: Rectangle { radius: 2; color: root.inputFill; border.color: root.border } }
                  Repeater { model: root.profiles.filter(function(p) { return !profileSearchInput.text || p.slug.toLowerCase().indexOf(profileSearchInput.text.toLowerCase()) >= 0 })
                    delegate: Rectangle { required property var modelData; required property int index; width: parent.width; height: 58; radius: 2; color: root.selectedProfile === modelData.slug ? root.selectedFill : "transparent"; border.color: root.selectedProfile === modelData.slug ? "#7598bd" : "transparent"
                      Row { anchors.fill: parent; anchors.margins: 9; spacing: 10
                        Rectangle { width: 34; height: 34; radius: 2; color: root.raised; anchors.verticalCenter: parent.verticalCenter; Text { anchors.centerIn: parent; text: modelData.slug.charAt(0).toUpperCase(); color: index % 2 ? root.blue : root.accent; font.bold: true; font.pixelSize: 14 } }
                        Column { anchors.verticalCenter: parent.verticalCenter; spacing: 4; width: parent.width - 50
                          Text { text: modelData.slug; color: root.text; font.pixelSize: 11; font.bold: true; elide: Text.ElideRight; width: parent.width }
                          Text { text: modelData.paused ? "Paused" : modelData.manager ? "Manager" : modelData.active ? "Active profile" : modelData.provider + " · " + modelData.reasoning; color: modelData.paused ? root.amber : modelData.manager ? root.accent : modelData.active ? root.accent : root.muted; font.pixelSize: 9; elide: Text.ElideRight; width: parent.width }
                        }
                      }
                      MouseArea { anchors.fill: parent; onClicked: { root.selectedProfile = modelData.slug; root.advancedMode = false } }
                    }
                  }
                }
              }
              Rectangle { width: parent.width - 276; height: parent.height; radius: 2; color: root.surface; border.color: root.border
                Column {
                  anchors.fill: parent; anchors.margins: 20; spacing: 13
                  property var current: root.profileBySlug(root.selectedProfile)
                  Row { width: parent.width; spacing: 8
                    Column { id: profileTitleColumn; spacing: 5
                      Text { text: parent.parent.parent.current.slug || "Choose a profile"; color: root.text; font.pixelSize: 17; font.bold: true }
                  Text { text: root.page === "Models & Providers" ? "BACKEND, MODEL & CREDENTIALS" : "PROFILE SETTINGS"; color: root.muted; font.pixelSize: 9; font.letterSpacing: 1.3 }
                    }
                    Item { width: Math.max(0, parent.width - profileTitleColumn.implicitWidth - 297 - 16); height: 1 }
                    Row { spacing: 7
                      Rectangle { width: 100; height: 34; radius: 2; color: root.selectedFill; border.color: root.border
                        Text { anchors.centerIn: parent; text: "Use this profile"; color: "#ffffff"; font.pixelSize: 9; font.bold: true }
                        MouseArea { anchors.fill: parent; onClicked: root.request("POST", "/api/profile/use", {profile: root.selectedProfile}, function(){root.notice = "Default profile changed"; root.refresh()}) }
                      }
                      Rectangle { width: 101; height: 34; radius: 2; color: root.selectedFill; border.color: root.border
                        Text { anchors.centerIn: parent; text: root.selectedProfile === root.managerProfile ? "★ Manager" : "Set manager"; color: "#ffffff"; font.pixelSize: 9; font.bold: true }
                        MouseArea { anchors.fill: parent; onClicked: root.profileControl("manager") }
                      }
                      Rectangle { width: 82; height: 34; radius: 2; color: root.raised; border.color: root.border
                        Text { anchors.centerIn: parent; text: root.profileBySlug(root.selectedProfile).paused ? "Resume (local)" : "Pause (local)"; color: root.amber; font.pixelSize: 9; font.bold: true }
                        MouseArea { anchors.fill: parent; onClicked: root.profileControl("pause") }
                      }
                    }
                  }
                  Rectangle { width: parent.width; height: 1; color: root.border }
                  Row { width: parent.width; height: 64; spacing: 12
                    Column { width: parent.width * 0.53; spacing: 6
                      Text { text: "DEFAULT MODEL"; color: root.muted; font.pixelSize: 9; font.bold: true; font.letterSpacing: 0.7 }
                      Row { width: parent.width; spacing: 7
                        TextField { leftPadding: 9; rightPadding: 9; id: modelInput; width: parent.width - 91; height: 38; text: parent.parent.parent.parent.current.model || ""; color: root.text; font.pixelSize: 11; placeholderText: providerInput.currentValue === "openrouter" ? "provider/model-name" : "Model ID for selected provider"; placeholderTextColor: root.muted; background: Rectangle { radius: 2; color: root.inputFill; border.color: root.border } }
                        Rectangle { width: 84; height: 38; radius: 2; color: root.accent; border.color: root.border
                          Text { anchors.centerIn: parent; text: "Browse models"; color: "#ffffff"; font.pixelSize: 9; font.bold: true }
                          MouseArea { anchors.fill: parent; onClicked: root.openModelCatalog(providerInput.currentValue, root.selectedProfile, baseUrlInput.text) }
                        }
                      }
                    }
                    Column { width: parent.width * 0.27; spacing: 6
                      Text { text: "PROVIDER"; color: root.muted; font.pixelSize: 9; font.bold: true; font.letterSpacing: 0.7 }
                      ComboBox { id: providerInput; width: parent.width; height: 38; model: root.modelProviders; textRole: "label"; valueRole: "id"; currentIndex: root.providerIndex(parent.parent.parent.current.provider || "auto"); contentItem: Text { text: providerInput.displayText; color: root.text; font.pixelSize: 9; elide: Text.ElideRight; verticalAlignment: Text.AlignVCenter; leftPadding: 9; rightPadding: 18 } background: Rectangle { radius: 2; color: root.inputFill; border.color: root.border } }
                    }
                    Column { width: parent.width * 0.20 - 24; spacing: 6
                      Text { text: "REASONING"; color: root.muted; font.pixelSize: 9; font.bold: true; font.letterSpacing: 0.7 }
                      TextField { leftPadding: 9; rightPadding: 9; id: reasoningInput; width: parent.width; height: 38; text: parent.parent.parent.current.reasoning || "medium"; color: root.text; font.pixelSize: 11; placeholderText: "low / medium / high"; placeholderTextColor: root.muted; background: Rectangle { radius: 2; color: root.inputFill; border.color: root.border } }
                    }
                  }
                  Row { width: parent.width; height: providerInput.currentValue === "custom" ? 38 : 0; visible: providerInput.currentValue === "custom"; spacing: 10
                    Text { text: "CUSTOM / LOCAL BASE URL"; color: root.muted; font.pixelSize: 8; font.bold: true; width: 150; anchors.verticalCenter: parent.verticalCenter }
                    TextField { leftPadding: 9; rightPadding: 9; id: baseUrlInput; width: parent.width - 160; height: 34; placeholderText: "http://localhost:11434/v1"; placeholderTextColor: root.muted; color: root.text; font.pixelSize: 9; background: Rectangle { radius: 2; color: root.inputFill; border.color: root.border } }
                  }
                  Column { width: parent.width; spacing: 7
                    Row { width: parent.width; height: 30; spacing: 10
                      Text { id: credentialName; width: 210; text: root.keyEnvName() ? (providerInput.currentValue === "custom" ? "CUSTOM ENDPOINT KEY" : root.keyEnvName()) : "HERMES SIGN-IN"; color: root.muted; font.pixelSize: 9; font.bold: true; font.letterSpacing: 0.5; elide: Text.ElideRight; anchors.verticalCenter: parent.verticalCenter }
                      Text { width: parent.width - credentialName.width - 10; text: root.keyEnvName() ? (root.providerCredentialConfigured() ? "Saved privately for this profile" : "No key saved for this provider") : root.providerDescription(); color: root.providerCredentialConfigured() ? root.accent : root.muted; font.pixelSize: 8; elide: Text.ElideRight; anchors.verticalCenter: parent.verticalCenter }
                    }
                    Row { width: parent.width; height: root.keyEnvName() ? 38 : 0; visible: !!root.keyEnvName(); spacing: 8
                      TextField { leftPadding: 9; rightPadding: 9; id: profileKeyInput; width: parent.width - 176; height: 36; echoMode: TextInput.Password; color: root.text; font.pixelSize: 10; placeholderText: providerInput.currentValue === "custom" ? "Stored privately with this profile’s model config" : "Paste or replace this profile’s provider key"; placeholderTextColor: root.muted; background: Rectangle { radius: 2; color: root.inputFill; border.color: root.border } }
                      Rectangle { width: 84; height: 34; radius: 2; color: root.accent; anchors.verticalCenter: parent.verticalCenter
                        Text { anchors.centerIn: parent; text: "Save key"; color: "#ffffff"; font.pixelSize: 9; font.bold: true }
                        MouseArea { anchors.fill: parent; onClicked: root.saveProfileKey() }
                      }
                      Rectangle { width: 76; height: 34; radius: 2; color: root.raised; border.color: root.border; anchors.verticalCenter: parent.verticalCenter
                        Text { anchors.centerIn: parent; text: "Clear"; color: root.red; font.pixelSize: 9 }
                        MouseArea { anchors.fill: parent; onClicked: root.clearProfileKey() }
                      }
                    }
                    Text { visible: !root.keyEnvName(); width: parent.width; height: 28; text: providerInput.currentValue === "auto" ? "Hermes will use an authenticated provider from your local credential pool." : "Use Hermes authentication for this backend. Run `hermes model` in a terminal to connect it."; color: root.muted; font.pixelSize: 8; wrapMode: Text.WordWrap }
                  }
                  Item { width: parent.width; height: 18
                    Text { anchors.left: parent.left; anchors.verticalCenter: parent.verticalCenter; text: "PERSONALITY & SYSTEM VOICE"; color: root.muted; font.pixelSize: 9; font.bold: true; font.letterSpacing: 0.8 }
                    Text { anchors.right: parent.right; anchors.verticalCenter: parent.verticalCenter; text: "Edit the complete SOUL.md"; color: root.muted; font.pixelSize: 9 }
                  }
                  TextArea { leftPadding: 10; rightPadding: 10; topPadding: 8; bottomPadding: 8; id: soulInput; width: parent.width; height: root.advancedMode ? parent.height * 0.36 : parent.height - 356; text: parent.current.personality || ""; color: root.text; font.pixelSize: 11; wrapMode: TextEdit.Wrap; selectByMouse: true; placeholderText: "Describe how this profile should think, speak, and work…"; placeholderTextColor: root.muted; background: Rectangle { radius: 2; color: root.inputFill; border.color: root.border } }
                  Row { width: parent.width; spacing: 10
                    Rectangle { width: 125; height: 34; radius: 2; color: root.accent
                      Text { anchors.centerIn: parent; text: "Save profile"; color: "#ffffff"; font.pixelSize: 10; font.bold: true }
                      MouseArea { anchors.fill: parent; onClicked: root.saveProfile() }
                    }
                    Rectangle { width: 132; height: 34; radius: 2; color: root.raised; border.color: root.border
                      Text { anchors.centerIn: parent; text: root.advancedMode ? "Hide advanced" : "Advanced config"; color: root.text; font.pixelSize: 10 }
                      MouseArea { anchors.fill: parent; onClicked: {
                        if (!root.advancedMode) root.request("GET", "/api/profile/" + root.selectedProfile, null, function(d) { root.advancedConfig = d.config || {}; advancedInput.text = JSON.stringify(d.config || {}, null, 2); root.advancedMode = true })
                        else root.advancedMode = false
                      } }
                    }
                    Rectangle { width: 106; height: 34; radius: 2; color: root.darkMode ? "#47282d" : "#f7dddd"; border.color: root.red
                      Text { anchors.centerIn: parent; text: "Delete profile"; color: root.red; font.pixelSize: 9; font.bold: true }
                      MouseArea { anchors.fill: parent; enabled: root.selectedProfile !== "default"; onClicked: root.showDeleteProfile = true }
                    }
                    Text { text: "Key values are never displayed"; color: root.muted; font.pixelSize: 9; anchors.verticalCenter: parent.verticalCenter }
                  }
                  TextArea { leftPadding: 10; rightPadding: 10; topPadding: 8; bottomPadding: 8; id: advancedInput; width: parent.width; height: root.advancedMode ? parent.height * 0.40 : 0; visible: root.advancedMode; color: root.text; font.family: "monospace"; font.pixelSize: 9; wrapMode: TextEdit.NoWrap; selectByMouse: true; background: Rectangle { radius: 2; color: root.inputFill; border.color: root.border } }
                }
              }
            }

            // OPTIONS: app-wide settings, separate from per-profile configuration
            Column { anchors.fill: parent; anchors.margins: 22; spacing: 12; visible: root.page === "Options"
              Row { width: parent.width; height: 48; spacing: 10
                Column { spacing: 4
                  Text { text: "Application options"; color: root.text; font.pixelSize: 17; font.bold: true }
                  Text { text: "Global Hermes LW preferences and connection status"; color: root.muted; font.pixelSize: 9 }
                }
              }
              Row { width: parent.width; height: 168; spacing: 12
                Rectangle { width: (parent.width - 12) / 2; height: parent.height; color: root.surface; border.color: root.border
                  Column { anchors.fill: parent; anchors.margins: 14; spacing: 10
                    Text { text: "HERMES CONNECTION"; color: root.blue; font.pixelSize: 9; font.bold: true; font.letterSpacing: 0.8 }
                    Text { text: root.backendConnected ? "Connected to local Hermes LW service" : "Hermes LW service is disconnected"; color: root.backendConnected ? root.accent : root.red; font.pixelSize: 12; font.bold: true }
                    Text { text: "http://127.0.0.1:18731  ·  local-only control API"; color: root.muted; font.pixelSize: 9 }
                    Text { text: "Provider credentials and model selection are managed separately for each profile."; color: root.muted; font.pixelSize: 9; wrapMode: Text.WordWrap; width: parent.width }
                    Item { width: 1; height: 1; Layout.fillHeight: true }
                    Row { spacing: 8
                      Rectangle { width: 180; height: 34; color: root.raised; border.color: root.border
                        Text { anchors.centerIn: parent; text: "Models & Providers"; color: root.accent; font.pixelSize: 9; font.bold: true }
                        MouseArea { anchors.fill: parent; onClicked: root.page = "Models & Providers" }
                      }
                      Rectangle { width: 194; height: 34; color: root.selectedFill; border.color: root.border
                        Text { anchors.centerIn: parent; text: "Manage provider connections"; color: "#ffffff"; font.pixelSize: 9; font.bold: true }
                        MouseArea { anchors.fill: parent; onClicked: root.openProviderManager() }
                      }
                    }
                  }
                }
                Rectangle { width: (parent.width - 12) / 2; height: parent.height; color: root.surface; border.color: root.border
                  Column { anchors.fill: parent; anchors.margins: 14; spacing: 10
                    Text { text: "WORKSPACE DEFAULTS"; color: root.blue; font.pixelSize: 9; font.bold: true; font.letterSpacing: 0.8 }
                    Text { text: "Startup board"; color: root.muted; font.pixelSize: 9 }
                    ComboBox { id: optionsBoardInput; width: parent.width; height: 34; model: root.activeProjects().map(function(p) { return p.name || p.slug }); currentIndex: Math.max(0, root.activeProjects().map(function(p) { return p.slug }).indexOf(root.currentBoard)); onActivated: if (root.activeProjects()[currentIndex]) root.setStartupBoard(root.activeProjects()[currentIndex].slug); contentItem: Text { text: optionsBoardInput.displayText; color: root.text; font.pixelSize: 9; elide: Text.ElideRight; verticalAlignment: Text.AlignVCenter; leftPadding: 9; rightPadding: 18 } background: Rectangle { radius: 2; color: root.inputFill; border.color: root.border } }
                    Text { text: "Manager profile"; color: root.muted; font.pixelSize: 9 }
                    ComboBox { id: optionsManagerInput; width: parent.width; height: 34; model: ["No manager"].concat(root.profiles.map(function(p) { return p.slug })); currentIndex: root.managerProfile ? Math.max(0, root.profiles.map(function(p) { return p.slug }).indexOf(root.managerProfile)) + 1 : 0; onActivated: root.setManagerProfile(currentIndex === 0 ? "" : root.profiles[currentIndex - 1].slug); contentItem: Text { text: optionsManagerInput.displayText; color: root.text; font.pixelSize: 9; elide: Text.ElideRight; verticalAlignment: Text.AlignVCenter; leftPadding: 9; rightPadding: 18 } background: Rectangle { radius: 2; color: root.inputFill; border.color: root.border } }
                  }
                }
              }
              Row { width: parent.width; height: 120; spacing: 12
                Rectangle { width: (parent.width - 12) / 2; height: parent.height; color: root.surface; border.color: root.border
                  Column { anchors.fill: parent; anchors.margins: 14; spacing: 9
                    Text { text: "APPEARANCE & CATALOG"; color: root.blue; font.pixelSize: 9; font.bold: true; font.letterSpacing: 0.8 }
                    Row { width: parent.width; spacing: 10
                      Rectangle { width: 150; height: 34; color: root.raised; border.color: root.border
                        Text { anchors.centerIn: parent; text: "Switch to " + (root.darkMode ? "light" : "dark") + " mode"; color: root.text; font.pixelSize: 9 }
                        MouseArea { anchors.fill: parent; onClicked: root.toggleTheme() }
                      }
                      Rectangle { width: 150; height: 34; color: root.raised; border.color: root.border
                        Text { anchors.centerIn: parent; text: root.modelCatalogLoading ? "Refreshing models…" : "Refresh model catalog"; color: root.accent; font.pixelSize: 9 }
                        MouseArea { anchors.fill: parent; enabled: !root.modelCatalogLoading; onClicked: root.loadModelCatalog(true) }
                      }
                    }
                    Text { text: root.modelCatalogFetchedAt ? "Catalog updated " + new Date(root.modelCatalogFetchedAt * 1000).toLocaleString() : "Catalog has not been loaded yet"; color: root.muted; font.pixelSize: 8 }
                  }
                }
                Rectangle { width: (parent.width - 12) / 2; height: parent.height; color: root.surface; border.color: root.border
                  Column { anchors.fill: parent; anchors.margins: 14; spacing: 8
                    Text { text: "KEYBOARD SHORTCUTS"; color: root.blue; font.pixelSize: 9; font.bold: true; font.letterSpacing: 0.8 }
                    Text { text: "Ctrl+1–8  ·  Switch app pages\nCtrl+N  ·  New task\nCtrl+F  ·  Search current board or model catalog\nCtrl+R  ·  Refresh Hermes state"; color: root.text; font.pixelSize: 9; lineHeight: 1.15 }
                  }
                }
              }
              Text { text: "Profile-level provider, model, reasoning, API key, and personality settings are in Models & Providers. Theme, manager, and startup board are app-wide."; color: root.muted; font.pixelSize: 9; wrapMode: Text.WordWrap; width: parent.width }
            }

            // PROFILE-SCOPED HERMES PLUGINS, TOOLSETS, AND MCP APP CONNECTIONS
            Column { anchors.fill: parent; anchors.margins: 22; spacing: 12; visible: root.page === "Task Advisor"
              Row { width: parent.width; height: 48; spacing: 10
                Column { spacing: 4
                  Text { text: "Model & prompt advisor"; color: root.text; font.pixelSize: 18; font.bold: true }
                  Text { text: "Rank models from the selected provider catalog using your task type and budget."; color: root.muted; font.pixelSize: 9 }
                }
                Item { width: 1; height: 1; Layout.fillWidth: true }
                Rectangle { width: 112; height: 32; color: root.raised; border.color: root.border
                  Text { anchors.centerIn: parent; text: "Refresh catalog"; color: root.accent; font.pixelSize: 9 }
                  MouseArea { anchors.fill: parent; onClicked: root.loadModelCatalog(true) }
                }
              }
              Row { width: parent.width; height: 40; spacing: 8
                ComboBox { id: advisorProvider; width: 170; height: 36; model: root.modelProviders; textRole: "label"; valueRole: "id"; currentIndex: Math.max(0, root.providerIndex(root.modelCatalogProvider || root.profileBySlug(root.selectedProfile).provider || "auto")); onActivated: root.loadModelCatalog(false, currentValue, root.selectedProfile, ""); contentItem: Text { text: advisorProvider.displayText || "Choose provider"; color: root.text; font.pixelSize: 9; verticalAlignment: Text.AlignVCenter; leftPadding: 9; rightPadding: 18 } background: Rectangle { color: root.inputFill; border.color: root.border } }
                ComboBox { id: advisorTaskType; width: 190; height: 36; model: ["Code audit", "Implementation", "Research", "Writing", "General problem solving"]; contentItem: Text { text: advisorTaskType.displayText; color: root.text; font.pixelSize: 9; verticalAlignment: Text.AlignVCenter; leftPadding: 9; rightPadding: 18 } background: Rectangle { color: root.inputFill; border.color: root.border } }
                Text { text: "MAX ESTIMATED COST · USD"; color: root.muted; font.pixelSize: 8; anchors.verticalCenter: parent.verticalCenter }
                TextField { id: advisorBudget; width: 100; height: 36; text: "0.25"; color: root.text; font.pixelSize: 10; inputMethodHints: Qt.ImhFormattedNumbersOnly; background: Rectangle { color: root.inputFill; border.color: root.border } }
                Text { text: "for 4K input + 1.2K output tokens"; color: root.muted; font.pixelSize: 8; anchors.verticalCenter: parent.verticalCenter }
              }
              TextArea { id: advisorProblem; width: parent.width; height: 90; leftPadding: 10; rightPadding: 10; topPadding: 8; bottomPadding: 8; color: root.text; font.pixelSize: 10; wrapMode: TextEdit.Wrap; placeholderText: "Describe the problem. Example: Audit this GitHub repository for security issues, broken flows, and high-impact bugs."; background: Rectangle { color: root.inputFill; border.color: root.border } }
              Row { width: parent.width; height: 22; spacing: 8
                Text { text: "Recommended models · " + root.catalogProviderName(); color: root.text; font.pixelSize: 12; font.bold: true }
                Item { width: 1; height: 1; Layout.fillWidth: true }
                Text { text: root.modelCatalogLoading ? "Loading…" : root.modelCatalog.length + " available"; color: root.muted; font.pixelSize: 9 }
              }
              Flickable { width: parent.width; height: 194; clip: true; contentHeight: advisorModelList.implicitHeight
                Column { id: advisorModelList; width: parent.width; spacing: 5
                  Repeater { model: root.advisorModels
                    delegate: Rectangle { required property var modelData; width: advisorModelList.width; height: 48; color: root.surface; border.color: root.border
                      Row { anchors.fill: parent; anchors.margins: 9; spacing: 8
                        Column { width: parent.width - 130; spacing: 4
                          Text { text: modelData.name; color: root.text; font.pixelSize: 10; font.bold: true; elide: Text.ElideRight; width: parent.width }
                          Text { text: modelData.id + " · " + modelData.category + " · " + Number(modelData.context_length || 0).toLocaleString() + " context"; color: root.muted; font.pixelSize: 8; elide: Text.ElideRight; width: parent.width }
                        }
                        Item { width: 1; height: 1; Layout.fillWidth: true }
                        Text { text: "$" + ((Number(modelData.input_rate || 0) * 4000 + Number(modelData.output_rate || 0) * 1200) / 1000000).toFixed(4) + " / sample"; color: root.accent; font.pixelSize: 9; anchors.verticalCenter: parent.verticalCenter }
                        Rectangle { width: 70; height: 28; color: root.raised; border.color: root.border; Text { anchors.centerIn: parent; text: "Use model"; color: root.accent; font.pixelSize: 8 } MouseArea { anchors.fill: parent; onClicked: { if (!root.selectedProfile && root.profiles.length) root.selectedProfile = root.profiles[0].slug; root.page = "Models & Providers"; root.openModelCatalog(root.modelCatalogProvider, root.selectedProfile, "") } } }
                      }
                    }
                  }
                  Text { visible: root.advisorModels.length === 0; text: "No priced models match this budget and use. Choose a provider in Models & Providers, refresh its catalog, or raise the budget."; color: root.muted; font.pixelSize: 9; width: parent.width; wrapMode: Text.WordWrap; padding: 12 }
                }
              }
              Row { width: parent.width; height: 34
                Text { text: "Prompt draft"; color: root.text; font.pixelSize: 12; font.bold: true; anchors.verticalCenter: parent.verticalCenter }
                Item { width: 1; height: 1; Layout.fillWidth: true }
                Rectangle { width: 116; height: 30; color: root.raised; border.color: root.border; Text { anchors.centerIn: parent; text: "Save prompt"; color: root.accent; font.pixelSize: 9 } MouseArea { anchors.fill: parent; onClicked: root.request("POST", "/api/prompt/save", {title: advisorTaskType.currentText + " task prompt", body: root.advisorPrompt(), favorite: false}, function(){root.notice = "Prompt saved to your library"; root.refresh()}) } }
                Rectangle { width: 144; height: 30; color: root.accent; Text { anchors.centerIn: parent; text: "Use in new task"; color: "#ffffff"; font.pixelSize: 9; font.bold: true } MouseArea { anchors.fill: parent; onClicked: root.startTaskFromAdvisor() } }
              }
              TextArea { width: parent.width; height: 172; readOnly: true; selectByMouse: true; leftPadding: 10; rightPadding: 10; topPadding: 8; bottomPadding: 8; text: root.advisorPrompt(); color: root.text; font.pixelSize: 9; wrapMode: TextEdit.Wrap; background: Rectangle { color: root.inputFill; border.color: root.border } }
              Text { width: parent.width; wrapMode: Text.WordWrap; text: "Cost values are catalog-based estimates for the sample token counts, not provider billing guarantees. This advisor does not send your task to a model."; color: root.muted; font.pixelSize: 8 }
            }

            Column { anchors.fill: parent; anchors.margins: 14; spacing: 10; visible: root.page === "Plugins & Tools"
              Row { width: parent.width; height: 36; spacing: 8
                Text { text: "Profile"; color: root.muted; font.pixelSize: 9; anchors.verticalCenter: parent.verticalCenter }
                ComboBox { id: extensionProfilePicker; width: 172; height: 30; model: root.profiles; textRole: "slug"; valueRole: "slug"; currentIndex: Math.max(0, root.profiles.findIndex(function(p){return p.slug === root.extensionProfile})); onActivated: root.loadExtensions(currentValue, root.extensionPlatform); contentItem: Text { text: extensionProfilePicker.displayText; color: root.text; font.pixelSize: 9; elide: Text.ElideRight; verticalAlignment: Text.AlignVCenter; leftPadding: 8 } background: Rectangle { color: root.inputFill; border.color: root.border } }
                Rectangle { width: 86; height: 30; color: root.raised; border.color: root.border
                  Text { anchors.centerIn: parent; text: root.extensionLoading ? "Loading…" : "↻ Refresh"; color: root.accent; font.pixelSize: 9 }
                  MouseArea { anchors.fill: parent; enabled: !root.extensionLoading; onClicked: root.loadExtensions(root.extensionProfile, root.extensionPlatform) }
                }
                Item { width: 1; height: 1; Layout.fillWidth: true }
                Text { text: root.extensionPlugins.filter(function(p){return p.enabled}).length + " enabled plugins  ·  " + root.extensionTools.filter(function(t){return t.enabled}).length + " active toolsets  ·  " + root.extensionMcpServers.length + " MCP apps"; color: root.muted; font.pixelSize: 9; anchors.verticalCenter: parent.verticalCenter }
              }
              Row { width: parent.width; height: 32; spacing: 5
                Repeater { model: ["Plugins", "Tools", "MCP Apps"]
                  delegate: Rectangle { required property string modelData; width: 94; height: 29; color: root.extensionTab === modelData ? root.selectedFill : root.raised; border.color: root.border
                    Text { anchors.centerIn: parent; text: modelData; color: root.extensionTab === modelData ? "#ffffff" : root.text; font.pixelSize: 9; font.bold: root.extensionTab === modelData }
                    MouseArea { anchors.fill: parent; onClicked: root.extensionTab = modelData }
                  }
                }
                Item { width: 1; height: 1; Layout.fillWidth: true }
                CheckBox { visible: root.extensionTab === "Plugins"; text: "Allow plugins to override built-in tools"; checked: root.allowPluginToolOverride; onToggled: root.allowPluginToolOverride = checked; font.pixelSize: 9 }
              }
              Text { visible: !!root.extensionError; width: parent.width; height: 24; text: root.extensionError; color: root.red; font.pixelSize: 9; wrapMode: Text.WordWrap }
              Flickable { width: parent.width; height: parent.height - 90; clip: true; contentWidth: width; contentHeight: extensionContent.implicitHeight; boundsBehavior: Flickable.StopAtBounds
                ScrollBar.vertical: ScrollBar { policy: ScrollBar.AsNeeded }
                Column { id: extensionContent; width: parent.width; spacing: 8
                  Row { visible: root.extensionTab === "Plugins"; width: parent.width; height: 36; spacing: 7
                    TextField { id: pluginSearchEntry; width: Math.max(170, parent.width * .28); height: 32; leftPadding: 8; rightPadding: 8; placeholderText: "Filter installed plugins…"; placeholderTextColor: root.muted; color: root.text; font.pixelSize: 9; onTextChanged: root.extensionSearch = text; background: Rectangle { color: root.inputFill; border.color: root.border } }
                    TextField { id: pluginInstallEntry; width: Math.max(230, parent.width * .38); height: 32; leftPadding: 8; rightPadding: 8; placeholderText: "Install from GitHub owner/repository or URL"; placeholderTextColor: root.muted; color: root.text; font.pixelSize: 9; background: Rectangle { color: root.inputFill; border.color: root.border } }
                    Rectangle { width: 102; height: 32; color: root.accent
                      Text { anchors.centerIn: parent; text: "Install (off)"; color: "#ffffff"; font.pixelSize: 9; font.bold: true }
                      MouseArea { anchors.fill: parent; enabled: !!pluginInstallEntry.text && !root.extensionLoading; onClicked: { root.extensionAction("plugin", "install", {identifier: pluginInstallEntry.text}); pluginInstallEntry.clear() } }
                    }
                  }
                  Text { visible: root.extensionTab === "Plugins"; width: parent.width; height: 25; text: "Plugins run with the selected Hermes profile’s permissions. Review their source before enabling."; color: root.amber; font.pixelSize: 8; verticalAlignment: Text.AlignVCenter; leftPadding: 4; elide: Text.ElideRight }
                  Row { visible: root.extensionTab === "Tools"; width: parent.width; height: 36; spacing: 8
                    Text { text: "Hermes platform"; color: root.muted; font.pixelSize: 9; anchors.verticalCenter: parent.verticalCenter }
                    ComboBox { id: extensionPlatformPicker; width: 160; height: 32; model: ["cli", "telegram", "discord", "slack", "whatsapp", "whatsapp_cloud", "signal", "bluebubbles", "email", "homeassistant", "mattermost", "matrix", "dingtalk", "feishu", "wecom", "wecom_callback", "weixin", "qqbot", "yuanbao", "webhook", "api_server", "cron"]; currentIndex: Math.max(0, model.indexOf(root.extensionPlatform)); onActivated: { root.extensionPlatform = currentText; root.loadExtensions(root.extensionProfile, currentText) }
                      contentItem: Text { text: extensionPlatformPicker.displayText; color: root.text; font.pixelSize: 9; verticalAlignment: Text.AlignVCenter; leftPadding: 8 }
                      background: Rectangle { color: root.inputFill; border.color: root.border }
                    }
                    Text { text: "Hermes toolsets are managed separately for each profile and platform."; color: root.muted; font.pixelSize: 9; anchors.verticalCenter: parent.verticalCenter }
                  }
                  Row { visible: root.extensionTab === "MCP Apps"; width: parent.width; height: 36; spacing: 7
                    ComboBox { id: mcpTransportPicker; width: 95; height: 32; model: ["http", "stdio"]; currentIndex: 0; onActivated: root.mcpTransport = currentText; contentItem: Text { text: mcpTransportPicker.displayText === "http" ? "HTTP app" : "Local app"; color: root.text; font.pixelSize: 9; verticalAlignment: Text.AlignVCenter; leftPadding: 8 } background: Rectangle { color: root.inputFill; border.color: root.border } }
                    TextField { id: mcpNameEntry; width: 130; height: 32; leftPadding: 8; placeholderText: "App name"; placeholderTextColor: root.muted; color: root.text; font.pixelSize: 9; background: Rectangle { color: root.inputFill; border.color: root.border } }
                    ComboBox { id: mcpAuthPicker; visible: root.mcpTransport === "http"; width: 88; height: 32; model: ["none", "oauth", "header"]; contentItem: Text { text: mcpAuthPicker.displayText === "none" ? "No auth" : mcpAuthPicker.displayText; color: root.text; font.pixelSize: 9; verticalAlignment: Text.AlignVCenter; leftPadding: 7 } background: Rectangle { color: root.inputFill; border.color: root.border } }
                    TextField { id: mcpEndpointEntry; visible: root.mcpTransport === "http"; width: Math.max(220, parent.width * (mcpAuthPicker.currentText === "header" ? .28 : .34)); height: 32; leftPadding: 8; placeholderText: "https://… MCP endpoint"; placeholderTextColor: root.muted; color: root.text; font.pixelSize: 9; background: Rectangle { color: root.inputFill; border.color: root.border } }
                    TextField { id: mcpHttpKeyEntry; visible: root.mcpTransport === "http" && mcpAuthPicker.currentText === "header"; width: Math.max(160, parent.width * .2); height: 32; leftPadding: 8; echoMode: TextInput.Password; placeholderText: "Bearer token"; placeholderTextColor: root.muted; color: root.text; font.pixelSize: 9; background: Rectangle { color: root.inputFill; border.color: root.border } }
                    TextField { id: mcpCommandEntry; visible: root.mcpTransport === "stdio"; width: Math.max(140, parent.width * .2); height: 32; leftPadding: 8; placeholderText: "Command"; placeholderTextColor: root.muted; color: root.text; font.pixelSize: 9; background: Rectangle { color: root.inputFill; border.color: root.border } }
                    TextField { id: mcpArgsEntry; visible: root.mcpTransport === "stdio"; width: Math.max(140, parent.width * .2); height: 32; leftPadding: 8; placeholderText: "Arguments"; placeholderTextColor: root.muted; color: root.text; font.pixelSize: 9; background: Rectangle { color: root.inputFill; border.color: root.border } }
                    TextField { id: mcpEnvEntry; visible: root.mcpTransport === "stdio"; width: Math.max(140, parent.width * .2); height: 32; leftPadding: 8; echoMode: TextInput.Password; placeholderText: "ENV_KEY=secret (optional)"; placeholderTextColor: root.muted; color: root.text; font.pixelSize: 9; background: Rectangle { color: root.inputFill; border.color: root.border } }
                    Rectangle { width: 70; height: 32; color: root.accent
                      Text { anchors.centerIn: parent; text: "Add app"; color: "#ffffff"; font.pixelSize: 9; font.bold: true }
                      MouseArea { anchors.fill: parent; enabled: !!mcpNameEntry.text && !root.extensionLoading; onClicked: { var d = {name:mcpNameEntry.text, transport:root.mcpTransport}; if (root.mcpTransport === "http") { d.url = mcpEndpointEntry.text; if (mcpAuthPicker.currentText !== "none") d.auth = mcpAuthPicker.currentText; if (mcpAuthPicker.currentText === "header") d.api_key = mcpHttpKeyEntry.text } else { d.command = mcpCommandEntry.text; d.args = mcpArgsEntry.text; var raw = mcpEnvEntry.text; var eq = raw.indexOf("="); if (eq > 0) { var env = {}; env[raw.slice(0,eq).trim()] = raw.slice(eq+1); d.env = env } }; root.extensionAction("mcp", "add", d); mcpNameEntry.clear(); mcpEndpointEntry.clear(); mcpHttpKeyEntry.clear(); mcpCommandEntry.clear(); mcpArgsEntry.clear(); mcpEnvEntry.clear() } }
                    }
                  }
                  Repeater { model: root.extensionTab === "Plugins" ? root.extensionPlugins.filter(function(p){var q=root.extensionSearch.toLowerCase();return !q || String(p.name+" "+(p.description||"")).toLowerCase().indexOf(q)>=0}) : []
                    delegate: Rectangle { required property var modelData; width: extensionContent.width; height: 72; color: root.surface; border.color: root.border
                      Column { anchors.left: parent.left; anchors.right: pluginActions.left; anchors.verticalCenter: parent.verticalCenter; anchors.leftMargin: 10; anchors.rightMargin: 8; spacing: 4
                        Row { spacing: 8; Text { text: modelData.name; color: root.text; font.pixelSize: 10; font.bold: true } Text { text: (modelData.source || "bundled") + (modelData.version ? " · " + modelData.version : ""); color: root.muted; font.pixelSize: 8; anchors.verticalCenter: parent.verticalCenter } }
                        Text { width: parent.width; text: modelData.description || modelData.summary || "Hermes profile plugin"; color: root.muted; font.pixelSize: 9; elide: Text.ElideRight }
                      }
                      Row { id: pluginActions; anchors.right: parent.right; anchors.rightMargin: 8; anchors.verticalCenter: parent.verticalCenter; spacing: 5
                        Rectangle { width: 72; height: 27; color: modelData.enabled ? root.selectedFill : root.raised; border.color: root.border
                          Text { anchors.centerIn: parent; text: modelData.enabled ? "Enabled" : "Enable"; color: modelData.enabled ? "#fff" : root.text; font.pixelSize: 8 }
                          MouseArea { anchors.fill: parent; onClicked: root.extensionAction("plugin", "toggle", {name:modelData.name, enabled:!modelData.enabled, allow_tool_override:root.allowPluginToolOverride}) }
                        }
                        Rectangle { width: 52; height: 27; visible: modelData.source === "git" || modelData.source === "user"; color: root.raised; border.color: root.border
                          Text { anchors.centerIn: parent; text: "Update"; color: root.text; font.pixelSize: 8 }
                          MouseArea { anchors.fill: parent; onClicked: root.extensionAction("plugin", "update", {name:modelData.name}) }
                        }
                        Rectangle { width: 56; height: 27; visible: modelData.source === "git" || modelData.source === "user"; color: root.raised; border.color: root.border
                          Text { anchors.centerIn: parent; text: "Remove"; color: root.red; font.pixelSize: 8 }
                          MouseArea { anchors.fill: parent; onClicked: root.extensionAction("plugin", "remove", {name:modelData.name}) }
                        }
                      }
                    }
                  }
                  Repeater { model: root.extensionTab === "Tools" ? root.extensionTools : []
                    delegate: Rectangle { required property var modelData; width: extensionContent.width; height: 48; color: root.surface; border.color: root.border
                      Column { anchors.left: parent.left; anchors.leftMargin: 10; anchors.right: toolAction.left; anchors.rightMargin: 8; anchors.verticalCenter: parent.verticalCenter; spacing: 3
                        Text { text: modelData.name; color: root.text; font.pixelSize: 10; font.bold: true }
                        Text { text: modelData.description; color: root.muted; font.pixelSize: 8; elide: Text.ElideRight; width: parent.width }
                      }
                      Rectangle { id: toolAction; anchors.right: parent.right; anchors.rightMargin: 8; anchors.verticalCenter: parent.verticalCenter; width: 76; height: 27; color: modelData.enabled ? root.selectedFill : root.raised; border.color: root.border
                        Text { anchors.centerIn: parent; text: modelData.enabled ? "Disable" : "Enable"; color: modelData.enabled ? "#fff" : root.text; font.pixelSize: 8 }
                        MouseArea { anchors.fill: parent; onClicked: root.extensionAction("tool", "toggle", {name:modelData.name, enabled:!modelData.enabled, platform:root.extensionPlatform}) }
                      }
                    }
                  }
                  Row { visible: root.extensionTab === "MCP Apps"; width: parent.width; height: 24; spacing: 8
                    Text { text: "CONFIGURED APPS"; color: root.muted; font.pixelSize: 8; font.bold: true; anchors.verticalCenter: parent.verticalCenter }
                    Item { width: 1; height: 1; Layout.fillWidth: true }
                    Text { text: "Install from Hermes catalog:"; color: root.muted; font.pixelSize: 8; anchors.verticalCenter: parent.verticalCenter }
                    ComboBox { id: mcpCatalogPicker; width: 190; height: 24; model: root.extensionMcpCatalog.map(function(e){return e.name}); contentItem: Text { text: mcpCatalogPicker.displayText; color: root.text; font.pixelSize: 8; verticalAlignment: Text.AlignVCenter; leftPadding: 6 } background: Rectangle { color: root.inputFill; border.color: root.border } }
                    Rectangle { width: 66; height: 24; color: root.raised; border.color: root.border
                      Text { anchors.centerIn: parent; text: "Install"; color: root.accent; font.pixelSize: 8 }
                      MouseArea { anchors.fill: parent; enabled: mcpCatalogPicker.currentIndex >= 0 && mcpCatalogPicker.count > 0; onClicked: root.extensionAction("mcp", "catalog", {name:mcpCatalogPicker.currentText}) }
                    }
                  }
                  Repeater { model: root.extensionTab === "MCP Apps" ? root.extensionMcpServers : []
                    delegate: Rectangle { required property var modelData; width: extensionContent.width; height: 60; color: root.surface; border.color: root.border
                      Column { anchors.left: parent.left; anchors.leftMargin: 10; anchors.right: mcpActions.left; anchors.rightMargin: 8; anchors.verticalCenter: parent.verticalCenter; spacing: 4
                        Text { text: modelData.name + " · " + modelData.transport; color: root.text; font.pixelSize: 10; font.bold: true }
                        Text { text: modelData.transport === "http" ? ((modelData.endpoint_host || "remote endpoint") + " · credential names: " + ((modelData.env_names || []).concat(modelData.header_names || []).join(", ") || "none")) : (modelData.command + " · " + modelData.args_count + " arguments · environment: " + ((modelData.env_names || []).join(", ") || "none")); color: root.muted; font.pixelSize: 8; elide: Text.ElideRight; width: parent.width }
                      }
                      Row { id: mcpActions; anchors.right: parent.right; anchors.rightMargin: 8; anchors.verticalCenter: parent.verticalCenter; spacing: 5
                        Rectangle { width: 48; height: 26; color: root.raised; border.color: root.border
                          Text { anchors.centerIn: parent; text: "Test"; color: root.accent; font.pixelSize: 8 }
                          MouseArea { anchors.fill: parent; onClicked: root.extensionAction("mcp", "test", {name:modelData.name}) }
                        }
                        Rectangle { width: 55; height: 26; color: root.raised; border.color: root.border
                          Text { anchors.centerIn: parent; text: "Remove"; color: root.red; font.pixelSize: 8 }
                          MouseArea { anchors.fill: parent; onClicked: root.extensionAction("mcp", "remove", {name:modelData.name}) }
                        }
                      }
                    }
                  }
                  Text { visible: !root.extensionLoading && ((root.extensionTab === "Plugins" && root.extensionPlugins.length === 0) || (root.extensionTab === "Tools" && root.extensionTools.length === 0) || (root.extensionTab === "MCP Apps" && root.extensionMcpServers.length === 0)); width: parent.width; height: 50; text: root.extensionTab === "Plugins" ? "No plugins are available for this profile." : root.extensionTab === "Tools" ? "Hermes did not return toolsets for this platform." : "No MCP apps configured yet. Add one above or install from the catalog."; color: root.muted; font.pixelSize: 10; horizontalAlignment: Text.AlignHCenter; verticalAlignment: Text.AlignVCenter }
                }
              }
            }

            // KANBAN: six readable lanes with compact task summaries
            Column { anchors.fill: parent; anchors.margins: 14; spacing: 8; visible: root.page === "Kanban"
              Row { width: parent.width; height: 34; spacing: 8
                ComboBox { id: projectSwitch; width: 154; height: 30; model: root.activeProjects().map(function(p){return p.name || p.slug}); currentIndex: Math.max(0, root.activeProjects().map(function(p){return p.slug}).indexOf(root.currentBoard)); onActivated: root.openProject(root.activeProjects()[currentIndex].slug); contentItem: Text { text: projectSwitch.displayText; color: root.text; font.pixelSize: 10; elide: Text.ElideRight; verticalAlignment: Text.AlignVCenter; leftPadding: 8 } background: Rectangle { radius: 2; color: root.inputFill; border.color: root.border } }
                Text { text: root.tasks.length + " cards"; color: root.muted; font.pixelSize: 9; anchors.verticalCenter: parent.verticalCenter }
                TextField { leftPadding: 9; rightPadding: 9; id: taskSearchInput; width: Math.min(280, parent.width * 0.28); height: 30; placeholderText: "Search title, profile, tag, ID…"; placeholderTextColor: root.muted; color: root.text; font.pixelSize: 9; onTextChanged: root.taskSearch = text; background: Rectangle { radius: 2; color: root.inputFill; border.color: root.border } }
                Item { width: Math.max(1, parent.width - 154 - 48 - taskSearchInput.width - 94 - 116 - 40); height: 1 }
                CheckBox { id: aiProfilesBoardToggle; text: "AI/Profiles"; width: 94; height: 30; checked: root.aiProfilesEnabled; onToggled: root.aiProfilesEnabled = checked
                  contentItem: Text { text: "AI/Profiles"; color: root.text; font.pixelSize: 8; leftPadding: 22; verticalAlignment: Text.AlignVCenter }
                }
                Rectangle { width: 116; height: 30; color: root.accent; border.color: root.border
                  Text { anchors.centerIn: parent; text: "+  New task"; color: "#ffffff"; font.pixelSize: 9; font.bold: true }
                  MouseArea { anchors.fill: parent; onClicked: { root.prepareNewTask(); if (root.aiProfilesEnabled) root.recommendProfilesForTask() } }
                }
              }
              Row { width: parent.width; height: 34; spacing: 8
                ComboBox { id: statusFilter; width: 120; height: 30; model: ["All statuses", "Triage", "Todo", "Ready", "Running", "Review", "Blocked", "Scheduled", "Done"]; currentIndex: 0; onActivated: root.statusFilterValue = currentIndex === 0 ? "all" : currentText.toLowerCase(); contentItem: Text { text: statusFilter.displayText; color: root.text; font.pixelSize: 9; elide: Text.ElideRight; verticalAlignment: Text.AlignVCenter; leftPadding: 9; rightPadding: 8 } background: Rectangle { radius: 2; color: root.inputFill; border.color: root.border } }
                ComboBox { id: assigneeFilter; width: 132; height: 30; model: ["All profiles"].concat(root.profiles.map(function(p){return p.slug})); currentIndex: 0; onActivated: root.assigneeFilterValue = currentIndex === 0 ? "all" : currentText; contentItem: Text { text: assigneeFilter.displayText; color: root.text; font.pixelSize: 9; elide: Text.ElideRight; verticalAlignment: Text.AlignVCenter; leftPadding: 9; rightPadding: 8 } background: Rectangle { radius: 2; color: root.inputFill; border.color: root.border } }
                ComboBox { id: savedViewPicker; width: 150; height: 30; model: ["Saved views"].concat(root.savedViews.filter(function(v){return v.board === root.currentBoard}).map(function(v){return v.name})); onActivated: if (currentIndex > 0) root.applySavedView(currentText); contentItem: Text { text: savedViewPicker.displayText; color: root.text; font.pixelSize: 9; elide: Text.ElideRight; verticalAlignment: Text.AlignVCenter; leftPadding: 9; rightPadding: 8 } background: Rectangle { radius: 2; color: root.inputFill; border.color: root.border } }
                Rectangle { width: 30; height: 30; color: root.raised; border.color: root.border; visible: savedViewPicker.currentIndex > 0
                  Text { anchors.centerIn: parent; text: "−"; color: root.red; font.pixelSize: 14 }
                  MouseArea { anchors.fill: parent; onClicked: root.deleteSavedView(savedViewPicker.currentText) }
                }
                Rectangle { width: 1; height: 22; color: root.border; anchors.verticalCenter: parent.verticalCenter }
                Text { text: root.selectedTaskIds.length ? root.selectedTaskIds.length + " selected" : "Select cards for bulk actions"; color: root.muted; font.pixelSize: 9; anchors.verticalCenter: parent.verticalCenter }
                ComboBox { id: bulkAssignee; width: 128; height: 30; model: ["Assign to…"].concat(root.assignableProfiles().map(function(p){return p.slug})); currentIndex: 0; contentItem: Text { text: bulkAssignee.displayText; color: root.text; font.pixelSize: 9; elide: Text.ElideRight; verticalAlignment: Text.AlignVCenter; leftPadding: 9; rightPadding: 8 } background: Rectangle { radius: 2; color: root.inputFill; border.color: root.border } }
                Rectangle { width: 64; height: 30; color: root.selectedTaskIds.length > 0 && bulkAssignee.currentIndex > 0 ? root.selectedFill : root.raised; border.color: root.border; Text { anchors.centerIn: parent; text: "Assign"; color: root.text; font.pixelSize: 9 } MouseArea { anchors.fill: parent; enabled: root.selectedTaskIds.length > 0 && bulkAssignee.currentIndex > 0; onClicked: root.bulkAction("assign") } }
                Rectangle { width: 72; height: 30; color: root.selectedTaskIds.length > 0 ? root.selectedFill : root.raised; border.color: root.border; Text { anchors.centerIn: parent; text: "Complete"; color: root.text; font.pixelSize: 9 } MouseArea { anchors.fill: parent; enabled: root.selectedTaskIds.length > 0; onClicked: root.bulkAction("complete") } }
              }
              Row { width: parent.width; height: 19; spacing: 10
                Text { text: "FILTERS"; color: root.muted; font.pixelSize: 8; font.bold: true; anchors.verticalCenter: parent.verticalCenter }
                Text { visible: root.statusFilterValue !== "all"; text: "Status · " + root.statusFilterValue; color: root.accent; font.pixelSize: 8; anchors.verticalCenter: parent.verticalCenter }
                Text { visible: root.assigneeFilterValue !== "all"; text: "Profile · " + root.assigneeFilterValue; color: root.accent; font.pixelSize: 8; anchors.verticalCenter: parent.verticalCenter }
                Text { visible: root.taskSearch.length > 0; text: "Search · “" + root.taskSearch + "”"; color: root.accent; font.pixelSize: 8; anchors.verticalCenter: parent.verticalCenter; elide: Text.ElideRight; width: 180 }
                Item { width: 1; height: 1; Layout.fillWidth: true }
                Text { text: root.tasks.filter(function(t){return t.status === "blocked"}).length + " blocked"; color: root.red; font.pixelSize: 8; anchors.verticalCenter: parent.verticalCenter }
                Text { text: root.tasks.filter(function(t){return t.status !== "done" && t.due_date && t.due_date < new Date().toISOString().slice(0,10)}).length + " overdue"; color: root.amber; font.pixelSize: 8; anchors.verticalCenter: parent.verticalCenter }
                Rectangle { visible: root.statusFilterValue !== "all" || root.assigneeFilterValue !== "all" || root.taskSearch.length > 0; width: 76; height: 20; color: root.raised; border.color: root.border
                  Text { anchors.centerIn: parent; text: "Clear filters"; color: root.text; font.pixelSize: 8 }
                  MouseArea { anchors.fill: parent; onClicked: root.resetBoardFilters() }
                }
              }
              Flickable { id: boardViewport; width: parent.width; height: parent.height - 101; clip: true; contentWidth: boardColumns.implicitWidth; contentHeight: height; flickableDirection: Flickable.HorizontalFlick; boundsBehavior: Flickable.StopAtBounds
                ScrollBar.horizontal: ScrollBar { policy: ScrollBar.AsNeeded }
                Row { id: boardColumns; height: boardViewport.height; spacing: 8
                  Repeater { model: [
                    {title:"INTAKE", statuses:["triage","todo"], color:root.blue},
                    {title:"READY", statuses:["ready"], color:root.accent},
                    {title:"IN PROGRESS", statuses:["running","scheduled"], color:root.blue},
                    {title:"REVIEW", statuses:["review"], color:root.amber},
                    {title:"BLOCKED", statuses:["blocked"], color:root.red},
                    {title:"DONE", statuses:["done"], color:root.accent}
                  ]
                    delegate: Rectangle { id: lane; required property var modelData; width: Math.max(216, (boardViewport.width - 40) / 4); height: boardColumns.height; color: root.laneFill; border.color: root.border
                      Column { anchors.fill: parent; anchors.margins: 7; spacing: 6
                        Rectangle { width: parent.width; height: 30; color: root.raised; border.color: root.border
                          Row { anchors.fill: parent; anchors.leftMargin: 7; anchors.rightMargin: 6; spacing: 6
                            Rectangle { width: 7; height: 7; color: lane.modelData.color; anchors.verticalCenter: parent.verticalCenter }
                            Text { text: lane.modelData.title; color: root.text; font.pixelSize: 9; font.bold: true; anchors.verticalCenter: parent.verticalCenter }
                            Item { width: 1; height: 1; Layout.fillWidth: true }
                            Text { text: root.laneTasks(lane.modelData.statuses).length; color: root.muted; font.pixelSize: 9; anchors.verticalCenter: parent.verticalCenter }
                          }
                        }
                        Flickable { width: parent.width; height: parent.height - 36; contentHeight: laneCards.implicitHeight; clip: true; boundsBehavior: Flickable.StopAtBounds
                          Column { id: laneCards; width: parent.width; spacing: 6
                            Repeater { model: root.laneTasks(lane.modelData.statuses)
                              delegate: Rectangle { id: taskCard; required property var modelData; width: laneCards.width; height: 127; focus: true; activeFocusOnTab: true; color: cardHover.containsMouse || activeFocus ? root.hoverFill : root.surface; border.color: activeFocus || root.selectedTaskIds.indexOf(modelData.id) >= 0 ? root.accent : root.border
                              Accessible.role: Accessible.ListItem
                              Accessible.name: modelData.title + ", " + modelData.status + (modelData.assignee ? ", assigned to " + modelData.assignee : ", unassigned")
                              Keys.onReturnPressed: root.selectTask(modelData)
                              Keys.onEnterPressed: root.selectTask(modelData)
                              Keys.onSpacePressed: root.toggleTaskSelection(modelData.id)
                              MouseArea { id: cardHover; anchors.fill: parent; hoverEnabled: true; acceptedButtons: Qt.LeftButton; onClicked: root.selectTask(taskCard.modelData) }
                                Column { anchors.fill: parent; anchors.margins: 8; spacing: 4
                                  Row { width: parent.width; height: 18; spacing: 6
                                    Rectangle { width: 16; height: 16; color: root.raised; border.color: root.border
                                      Text { anchors.centerIn: parent; text: root.selectedTaskIds.indexOf(taskCard.modelData.id) >= 0 ? "✓" : ""; color: root.accent; font.pixelSize: 10; font.bold: true }
                                      MouseArea { anchors.fill: parent; onClicked: root.toggleTaskSelection(taskCard.modelData.id) }
                                    }
                                    Text { id: cardIdLabel; text: "#" + modelData.id.replace("t_", ""); color: root.muted; font.family: "monospace"; font.pixelSize: 9; anchors.verticalCenter: parent.verticalCenter }
                                    Rectangle { id: cardStatusPill; width: cardStatusText.implicitWidth + 12; height: 17; color: root.selectedFill; anchors.verticalCenter: parent.verticalCenter
                                      Text { id: cardStatusText; anchors.centerIn: parent; text: modelData.status; color: "#ffffff"; font.pixelSize: 8 }
                                    }
                                    Item { width: Math.max(0, parent.width - 16 - cardIdLabel.implicitWidth - cardStatusPill.width - cardPriorityLabel.implicitWidth - 18); height: 1 }
                                    Text { id: cardPriorityLabel; text: "P" + (Number(modelData.priority || 0) + 1); color: Number(modelData.priority || 0) > 0 ? root.amber : root.muted; font.pixelSize: 9; anchors.verticalCenter: parent.verticalCenter }
                                  }
                                  Text { text: modelData.title; color: root.text; font.pixelSize: 11; font.bold: true; wrapMode: Text.WordWrap; maximumLineCount: 3; elide: Text.ElideRight; width: parent.width; height: 43 }
                                  Text { text: modelData.assignee ? "Assigned: " + modelData.assignee : "Unassigned"; color: root.blue; font.pixelSize: 9; elide: Text.ElideRight; width: parent.width }
                                  Text { text: "Can work: " + root.taskProfileLabel(modelData); color: root.muted; font.pixelSize: 9; elide: Text.ElideRight; width: parent.width }
                                  Row { width: parent.width; spacing: 6
                                    Text { text: (modelData.tags || []).slice(0,2).join(" · ") || "No tags"; color: root.muted; font.pixelSize: 9; elide: Text.ElideRight; width: parent.width * .60; anchors.verticalCenter: parent.verticalCenter }
                                    Item { width: 1; height: 1; Layout.fillWidth: true }
                                    Text { text: modelData.has_estimate ? money(modelData.estimated_cost) : "—"; color: modelData.has_estimate ? root.accent : root.muted; font.pixelSize: 8; anchors.verticalCenter: parent.verticalCenter }
                                  }
                                }
                              }
                            }
                            Text { visible: root.laneTasks(lane.modelData.statuses).length === 0; text: root.taskSearch ? "No matches" : "No tasks"; color: root.muted; font.pixelSize: 9; horizontalAlignment: Text.AlignHCenter; width: parent.width; topPadding: 14 }
                          }
                        }
                      }
                    }
                  }
                }
              }
            }

            // PROMPT LIBRARY
            Column { anchors.fill: parent; anchors.margins: 24; spacing: 16; visible: root.page === "Prompts"
              Row { width: parent.width; height: 44
                Column { spacing: 4; Text { text: "Saved prompts"; color: root.text; font.pixelSize: 15; font.bold: true } Text { text: root.prompts.length + " reusable prompts · " + root.prompts.filter(function(p){return p.favorite}).length + " favorites"; color: root.muted; font.pixelSize: 9 } }
                TextField { leftPadding: 9; rightPadding: 9; id: promptSearchInput; width: 220; height: 30; placeholderText: "Search prompts…"; placeholderTextColor: root.muted; color: root.text; font.pixelSize: 9; anchors.verticalCenter: parent.verticalCenter; background: Rectangle { radius: 2; color: root.inputFill; border.color: root.border } }
                Rectangle { width: 120; height: 36; radius: 2; color: root.accent
                  Row { anchors.centerIn: parent; spacing: 6; Text { text: "+"; color: "#ffffff"; font.pixelSize: 16 } Text { text: "Add prompt"; color: "#ffffff"; font.pixelSize: 10; font.bold: true } }
                  MouseArea { anchors.fill: parent; onClicked: root.editPrompt(null) }
                }
              }
              Flickable { width: parent.width; height: parent.height - 60; clip: true; contentHeight: promptList.implicitHeight
                Column { id: promptList; width: parent.width; spacing: 10
                  Repeater { model: root.prompts.filter(function(p) { return !promptSearchInput.text || (p.title + " " + p.body).toLowerCase().indexOf(promptSearchInput.text.toLowerCase()) >= 0 })
                    delegate: Rectangle { required property var modelData; width: promptList.width; height: 132; radius: 2; color: root.surface; border.color: root.border
                      Column { anchors.fill: parent; anchors.margins: 14; spacing: 9
                        Row { width: parent.width; spacing: 9
                          Text { text: modelData.title; color: root.text; font.pixelSize: 12; font.bold: true; width: parent.width - 250; elide: Text.ElideRight }
                          Item { width: 1; height: 1; Layout.fillWidth: true }
                          Rectangle { width: 28; height: 26; radius: 2; color: root.raised
                            Text { anchors.centerIn: parent; text: modelData.favorite ? "★" : "☆"; color: modelData.favorite ? root.amber : root.muted; font.pixelSize: 15 }
                            MouseArea { anchors.fill: parent; onClicked: root.togglePromptFavorite(modelData) }
                          }
                          Rectangle { width: 72; height: 26; radius: 2; color: root.accent; Text { anchors.centerIn: parent; text: "Use prompt"; color: "#ffffff"; font.pixelSize: 8; font.bold: true } MouseArea { anchors.fill: parent; onClicked: root.usePrompt(modelData) } }
                          Rectangle { width: 58; height: 26; radius: 2; color: root.raised; border.color: root.border; Text { anchors.centerIn: parent; text: "Edit"; color: root.text; font.pixelSize: 8 } MouseArea { anchors.fill: parent; onClicked: root.editPrompt(modelData) } }
                        }
                        Text { width: parent.width; height: 52; text: modelData.body; color: root.muted; font.pixelSize: 9; wrapMode: Text.WordWrap; maximumLineCount: 4; elide: Text.ElideRight }
                        Text { text: modelData.favorite ? "FAVORITE" : "PROMPT"; color: modelData.favorite ? root.amber : root.muted; font.pixelSize: 8; font.bold: true; font.letterSpacing: 0.8 }
                      }
                    }
                  }
                  Text { visible: root.prompts.length === 0; text: "Your favorite prompts will appear here. Add one to reuse it with your manager profile."; color: root.muted; font.pixelSize: 11; width: parent.width; horizontalAlignment: Text.AlignHCenter; topPadding: 40 }
                }
              }
            }

            // notification toast
            Rectangle { visible: root.notice.length > 0; anchors.horizontalCenter: parent.horizontalCenter; anchors.bottom: parent.bottom; anchors.bottomMargin: 20; width: Math.min(420, toastText.implicitWidth + 44); height: 42; radius: 2; color: root.darkMode ? "#243e2a" : "#dcefdc"; border.color: root.darkMode ? "#567e56" : "#78a278"; z: 20
              Text { id: toastText; anchors.centerIn: parent; text: root.notice; color: root.darkMode ? "#d2f0ce" : "#32532f"; font.pixelSize: 10 }
              Timer { running: root.notice.length > 0; interval: 3600; onTriggered: root.notice = "" }
            }
          }
        }

        Rectangle { width: parent.width; height: 19; color: root.raised; border.color: root.border
          Row { anchors.fill: parent; anchors.leftMargin: 7; spacing: 14
            Text { text: root.pendingRequests ? "Working…" : root.backendConnected ? "Ready" : "Disconnected"; color: root.backendConnected ? root.text : root.red; font.pixelSize: 8; anchors.verticalCenter: parent.verticalCenter }
            Rectangle { width: 1; height: 11; color: root.border; anchors.verticalCenter: parent.verticalCenter }
            Text { text: (root.currentBoard || "default") + "  ·  " + root.tasks.length + " tasks"; color: root.muted; font.pixelSize: 8; anchors.verticalCenter: parent.verticalCenter }
            Item { width: Math.max(1, parent.width - 300); height: 1 }
            Text { text: "Hermes LW  |  Quickshell"; color: root.muted; font.pixelSize: 8; anchors.verticalCenter: parent.verticalCenter }
          }
        }
      }
      }

      // Project editor
      Rectangle { anchors.fill: parent; visible: root.showProjectEditor; color: "#99070b10"; z: 29; MouseArea { anchors.fill: parent; onClicked: {} }
        Rectangle { width: 560; height: Math.min(700, parent.height - 24); radius: 2; color: root.surface; border.color: "#7f9db9"; anchors.centerIn: parent; MouseArea { anchors.fill: parent }
          XpTitleBar { z: 2; anchors.top: parent.top; width: parent.width; caption: "Create / Edit Project"; darkMode: root.darkMode; onCloseRequested: root.showProjectEditor = false }
          Column { anchors.fill: parent; anchors.margins: 22; anchors.topMargin: 50; spacing: 10
            Row { width: parent.width; height: 40
              Column { spacing: 4; Text { text: root.editingProject ? "Project settings" : "Create a project"; color: root.text; font.pixelSize: 17; font.bold: true } Text { text: "A project is an isolated Hermes board with its own queue."; color: root.muted; font.pixelSize: 9 } }
              Item { width: 1; height: 1; Layout.fillWidth: true }
              Item { width: 24; height: 20 }
            }
            Text { text: "PROJECT NAME"; color: root.muted; font.pixelSize: 8; font.bold: true }
            TextField { leftPadding: 9; rightPadding: 9; id: projectName; width: parent.width; height: 36; placeholderText: "e.g. Desktop refresh"; color: root.text; font.pixelSize: 10; background: Rectangle { radius: 2; color: root.inputFill; border.color: root.border } }
            Text { text: "PROJECT ID"; color: root.muted; font.pixelSize: 8; font.bold: true }
            TextField { leftPadding: 9; rightPadding: 9; id: projectSlug; width: parent.width; height: 36; placeholderText: "e.g. desktop-refresh"; enabled: !root.editingProject; color: root.text; font.pixelSize: 10; background: Rectangle { radius: 2; color: root.inputFill; border.color: root.border } }
            Text { text: "DESCRIPTION"; color: root.muted; font.pixelSize: 8; font.bold: true }
            TextArea { leftPadding: 10; rightPadding: 10; topPadding: 8; bottomPadding: 8; id: projectDescription; width: parent.width; height: 75; placeholderText: "What is this project trying to achieve?"; color: root.text; font.pixelSize: 9; wrapMode: TextEdit.Wrap; background: Rectangle { radius: 2; color: root.inputFill; border.color: root.border } }
            Row { width: parent.width; spacing: 10
              Column { width: parent.width * .5 - 5; spacing: 5; Text { text: "OWNER"; color: root.muted; font.pixelSize: 8; font.bold: true } TextField { leftPadding: 9; rightPadding: 9; id: projectOwner; width: parent.width; height: 36; placeholderText: "Person or profile"; color: root.text; font.pixelSize: 9; background: Rectangle { radius: 2; color: root.inputFill; border.color: root.border } } }
              Column { width: parent.width * .5 - 5; spacing: 5; Text { text: "PROJECT DUE DATE"; color: root.muted; font.pixelSize: 8; font.bold: true } TextField { leftPadding: 9; rightPadding: 9; id: projectDue; width: parent.width; height: 36; placeholderText: "YYYY-MM-DD"; color: root.text; font.pixelSize: 9; background: Rectangle { radius: 2; color: root.inputFill; border.color: root.border } } }
            }
            Row { width: parent.width; spacing: 10
              Column { width: parent.width * .5 - 5; spacing: 5; Text { text: "BUDGET · USD"; color: root.muted; font.pixelSize: 8; font.bold: true } TextField { leftPadding: 9; rightPadding: 9; id: projectBudget; width: parent.width; height: 36; text: "0"; color: root.text; font.pixelSize: 9; inputMethodHints: Qt.ImhFormattedNumbersOnly; background: Rectangle { radius: 2; color: root.inputFill; border.color: root.border } } }
              Column { width: parent.width * .5 - 5; spacing: 5; Text { text: "COLOR · HEX"; color: root.muted; font.pixelSize: 8; font.bold: true } TextField { leftPadding: 9; rightPadding: 9; id: projectColor; width: parent.width; height: 36; text: "#3584e4"; color: root.text; font.pixelSize: 9; background: Rectangle { radius: 2; color: root.inputFill; border.color: root.border } } }
            }
            Row { spacing: 9
              Rectangle { width: 118; height: 36; radius: 2; color: root.accent; Text { anchors.centerIn: parent; text: root.editingProject ? "Save project" : "Create project"; color: "#ffffff"; font.pixelSize: 9; font.bold: true } MouseArea { anchors.fill: parent; onClicked: root.saveProject() } }
              Rectangle { width: 86; height: 36; radius: 2; color: root.raised; border.color: root.border; Text { anchors.centerIn: parent; text: "Cancel"; color: root.muted; font.pixelSize: 9 } MouseArea { anchors.fill: parent; onClicked: root.showProjectEditor = false } }
            }
          }
        }
      }

      // New task modal
      Rectangle { anchors.fill: parent; visible: root.showNewTask; color: "#99070b10"; z: 30
        MouseArea { anchors.fill: parent; onClicked: {} }
        Rectangle { width: 540; height: Math.min(700, parent.height - 24); radius: 2; color: root.surface; border.color: "#7f9db9"; anchors.centerIn: parent
          XpTitleBar { z: 2; anchors.top: parent.top; width: parent.width; caption: "New Task"; darkMode: root.darkMode; onCloseRequested: root.showNewTask = false }
          Flickable { anchors.fill: parent; anchors.margins: 20; anchors.topMargin: 48; clip: true; contentHeight: newTaskForm.implicitHeight
            ScrollBar.vertical: ScrollBar { policy: ScrollBar.AsNeeded }
            Column { id: newTaskForm; width: parent.width; spacing: 9
            Row { width: parent.width
              Column { spacing: 5; Text { text: "Create a task"; color: root.text; font.pixelSize: 18; font.bold: true } Text { text: "Add a card to " + (root.projectInfo.name || "this project"); color: root.muted; font.pixelSize: 10 } }
              Item { width: 1; height: 1; Layout.fillWidth: true }
              Item { width: 24; height: 20 }
            }
            Row { width: parent.width; spacing: 8
              ComboBox { id: taskTemplate; width: parent.width - 92; height: 32; model: ["Blank task", "Bug report", "Research brief", "Implementation task", "Code review"].concat(root.taskTemplates.map(function(t){return t.title})); onActivated: root.applyTaskTemplate(currentText); contentItem: Text { text: taskTemplate.displayText; color: root.text; font.pixelSize: 9; verticalAlignment: Text.AlignVCenter; leftPadding: 8 } background: Rectangle { radius: 2; color: root.inputFill; border.color: root.border } }
              Rectangle { width: 84; height: 32; radius: 2; color: root.raised; border.color: root.border; Text { anchors.centerIn: parent; text: "Save template"; color: root.text; font.pixelSize: 8 } MouseArea { anchors.fill: parent; onClicked: root.saveTaskTemplate() } }
            }
            Text { text: "TITLE"; color: root.muted; font.pixelSize: 9; font.bold: true }
            TextField { leftPadding: 9; rightPadding: 9; id: newTitle; width: parent.width; height: 40; color: root.text; font.pixelSize: 11; placeholderText: "What needs to get done?"; onTextChanged: if (root.aiProfilesEnabled) root.recommendProfilesForTask(); background: Rectangle { radius: 2; color: root.inputFill; border.color: root.border } }
            Text { text: "DESCRIPTION"; color: root.muted; font.pixelSize: 9; font.bold: true }
            TextArea { leftPadding: 10; rightPadding: 10; topPadding: 8; bottomPadding: 8; id: newBody; width: parent.width; height: 82; color: root.text; font.pixelSize: 10; wrapMode: TextEdit.Wrap; placeholderText: "Context, acceptance criteria, useful links…"; onTextChanged: if (root.aiProfilesEnabled) root.recommendProfilesForTask(); background: Rectangle { radius: 2; color: root.inputFill; border.color: root.border } }
            Row { width: parent.width; spacing: 12
              Column { width: parent.width * 0.5 - 6; spacing: 6; Text { text: "ASSIGNEE"; color: root.muted; font.pixelSize: 9; font.bold: true }
                ComboBox { id: newAssignee; width: parent.width; height: 38; model: ["Unassigned"].concat(root.newTaskAssigneeNames()); currentIndex: 0 }
              }
              Column { width: parent.width * 0.5 - 6; spacing: 6; Text { text: "PRIORITY  ·  0–4"; color: root.muted; font.pixelSize: 9; font.bold: true }
                TextField { leftPadding: 9; rightPadding: 9; id: newPriority; width: parent.width; height: 38; text: "0"; color: root.text; inputMethodHints: Qt.ImhDigitsOnly; background: Rectangle { radius: 2; color: root.inputFill; border.color: root.border } }
              }
            }
            Row { width: parent.width; spacing: 12
              Column { width: parent.width * 0.5 - 6; spacing: 6; Text { text: "WORKSPACE"; color: root.muted; font.pixelSize: 9; font.bold: true } ComboBox { id: newWorkspace; width: parent.width; height: 38; model: ["scratch", "worktree"] } }
              Column { width: parent.width * 0.5 - 6; spacing: 6; Text { text: "COST ESTIMATE · USD"; color: root.muted; font.pixelSize: 9; font.bold: true } TextField { leftPadding: 9; rightPadding: 9; id: newCost; width: parent.width; height: 38; placeholderText: "Planning estimate"; color: root.text; inputMethodHints: Qt.ImhFormattedNumbersOnly; background: Rectangle { radius: 2; color: root.inputFill; border.color: root.border } } }
            }
            Row { width: parent.width; spacing: 8
              Column { width: parent.width * .30 - 6; spacing: 4; Text { text: "DUE DATE"; color: root.muted; font.pixelSize: 8; font.bold: true } TextField { leftPadding: 9; rightPadding: 9; id: newDue; width: parent.width; height: 34; placeholderText: "YYYY-MM-DD"; color: root.text; font.pixelSize: 9; background: Rectangle { radius: 2; color: root.inputFill; border.color: root.border } } }
              Column { width: parent.width * .25 - 6; spacing: 4; Text { text: "EFFORT · HOURS"; color: root.muted; font.pixelSize: 8; font.bold: true } TextField { leftPadding: 9; rightPadding: 9; id: newEffort; width: parent.width; height: 34; text: "0"; color: root.text; font.pixelSize: 9; inputMethodHints: Qt.ImhFormattedNumbersOnly; background: Rectangle { radius: 2; color: root.inputFill; border.color: root.border } } }
              Column { width: parent.width * .45 - 6; spacing: 4; Text { text: "TAGS · comma separated"; color: root.muted; font.pixelSize: 8; font.bold: true } TextField { leftPadding: 9; rightPadding: 9; id: newTags; width: parent.width; height: 34; placeholderText: "bug, launch, docs"; color: root.text; font.pixelSize: 9; background: Rectangle { radius: 2; color: root.inputFill; border.color: root.border } } }
            }
            Row { width: parent.width; spacing: 8
              CheckBox { id: aiProfilesModalToggle; text: "AI/Profiles"; checked: root.aiProfilesEnabled; onToggled: root.toggleAiProfiles(checked); contentItem: Text { text: "AI/Profiles"; color: root.text; font.pixelSize: 9; leftPadding: 22; verticalAlignment: Text.AlignVCenter } }
              Text { text: "Suggest eligible profiles from this task. Suggestions never enable a profile automatically."; color: root.muted; font.pixelSize: 8; anchors.verticalCenter: parent.verticalCenter; width: parent.width - 145; wrapMode: Text.WordWrap }
            }
            Text { visible: root.aiProfilesEnabled && root.aiProfileSuggestions.length > 0; width: parent.width; text: "Suggestions (not selected): " + root.aiProfileSuggestions.map(function(p){return p.slug + (p.model && p.model !== "not set" ? " · " + p.model : "") + (p.personality ? " · " + p.personality.replace(/\s+/g, " ").slice(0, 76) : "")}).join("  |  "); color: root.accent; font.pixelSize: 8; wrapMode: Text.WordWrap }
            Column { width: parent.width; spacing: 4
              Text { text: "WHO CAN WORK ON THIS TASK"; color: root.muted; font.pixelSize: 9; font.bold: true }
              Text { text: "Select each eligible profile and enter its budget. Saved limits are task metadata; Hermes task execution does not currently enforce dollar caps."; color: root.muted; font.pixelSize: 8; wrapMode: Text.WordWrap; width: parent.width }
              Flow { width: parent.width; height: 80; spacing: 4
                Repeater { model: root.assignableProfiles()
                  delegate: Rectangle { required property var modelData; width: Math.min(155, parent.width / 3); height: 36; color: root.raised; border.color: root.newAllowedProfiles.indexOf(modelData.slug) >= 0 ? root.accent : root.border
                    Row { anchors.fill: parent; anchors.margins: 2; spacing: 1
                      CheckBox { width: parent.width - 58; height: parent.height; checked: root.newAllowedProfiles.indexOf(modelData.slug) >= 0; onToggled: root.toggleProfileIn("new", modelData.slug)
                        contentItem: Text { text: modelData.slug; color: root.text; font.pixelSize: 8; leftPadding: 20; verticalAlignment: Text.AlignVCenter; elide: Text.ElideRight }
                      }
                      Text { text: "$"; color: root.muted; font.pixelSize: 8; anchors.verticalCenter: parent.verticalCenter }
                      TextField { width: 48; height: 27; text: root.newProfileBudgets[modelData.slug] === undefined ? "" : String(root.newProfileBudgets[modelData.slug]); placeholderText: "cap"; color: root.text; font.pixelSize: 8; inputMethodHints: Qt.ImhFormattedNumbersOnly; onTextChanged: root.setNewProfileBudget(modelData.slug, text); background: Rectangle { color: root.inputFill; border.color: root.border } }
                    }
                  }
                }
              }
            }
            Row { width: parent.width; spacing: 10
              Rectangle { width: 128; height: 38; radius: 2; color: root.accent
                Text { anchors.centerIn: parent; text: "Create task"; color: "#ffffff"; font.pixelSize: 10; font.bold: true }
                MouseArea { anchors.fill: parent; onClicked: root.createTask() }
              }
              Rectangle { width: 92; height: 38; radius: 2; color: root.raised; border.color: root.border; Text { anchors.centerIn: parent; text: "Cancel"; color: root.muted; font.pixelSize: 10 } MouseArea { anchors.fill: parent; onClicked: root.showNewTask = false } }
            }
            }
          }
        }
      }

      // Ask Hermes modal
      Rectangle { anchors.fill: parent; visible: root.showHermes; color: "#99070b10"; z: 31; MouseArea { anchors.fill: parent; onClicked: {} }
        Rectangle { width: 500; height: 300; radius: 2; color: root.surface; border.color: "#7f9db9"; anchors.centerIn: parent; MouseArea { anchors.fill: parent }
          XpTitleBar { z: 2; anchors.top: parent.top; width: parent.width; caption: "Start Hermes"; darkMode: root.darkMode; onCloseRequested: root.showHermes = false }
          Column { anchors.fill: parent; anchors.margins: 24; anchors.topMargin: 50; spacing: 14
            Row { width: parent.width; Text { text: "Start with Hermes"; color: root.text; font.pixelSize: 18; font.bold: true } Item { width: 1; height: 1; Layout.fillWidth: true } Item { width: 24; height: 20 } }
            Text { text: root.managerProfile ? "This prompt will run with manager profile “" + root.managerProfile + "”." : "No manager selected · using the active default profile."; color: root.muted; font.pixelSize: 10 }
            TextArea { leftPadding: 10; rightPadding: 10; topPadding: 8; bottomPadding: 8; id: hermesPrompt; width: parent.width; height: 105; color: root.text; font.pixelSize: 11; wrapMode: TextEdit.Wrap; placeholderText: "What would you like Hermes to do?"; background: Rectangle { radius: 2; color: root.inputFill; border.color: root.border } }
            Rectangle { width: 128; height: 38; radius: 2; color: root.accent
              Text { anchors.centerIn: parent; text: "Launch prompt"; color: "#ffffff"; font.pixelSize: 10; font.bold: true }
              MouseArea { anchors.fill: parent; onClicked: root.request("POST", "/api/hermes", {prompt: hermesPrompt.text}, function(d){root.showHermes = false; root.notice = d.message || "Hermes started"}) }
            }
          }
        }
      }

      // Task detail / controls
      Rectangle { anchors.fill: parent; visible: root.selectedTask !== null; color: "#99070b10"; z: 32; MouseArea { anchors.fill: parent; onClicked: {} }
        Rectangle { width: 620; height: Math.min(730, parent.height - 24); radius: 2; color: root.surface; border.color: "#7f9db9"; anchors.centerIn: parent; MouseArea { anchors.fill: parent }
          XpTitleBar { z: 2; anchors.top: parent.top; width: parent.width; caption: "Task Details"; darkMode: root.darkMode; onCloseRequested: root.selectedTask = null }
          Flickable { anchors.fill: parent; anchors.leftMargin: 16; anchors.rightMargin: 16; anchors.topMargin: 34; anchors.bottomMargin: 12; clip: true; contentHeight: taskDetailContent.implicitHeight
            ScrollBar.vertical: ScrollBar { policy: ScrollBar.AsNeeded }
            Column { id: taskDetailContent; width: parent.width; spacing: 9
            Row { width: parent.width; Column { spacing: 5; Text { text: "Task details"; color: root.text; font.pixelSize: 18; font.bold: true } Text { text: root.selectedTask ? root.selectedTask.id : ""; color: root.muted; font.family: "monospace"; font.pixelSize: 9 } } Item { width: 1; height: 1; Layout.fillWidth: true } Item { width: 24; height: 20 } }
            Text { width: parent.width; text: root.selectedTask ? root.selectedTask.title : ""; color: root.text; font.pixelSize: 14; font.bold: true; wrapMode: Text.WordWrap }
            Text { width: parent.width; height: 78; text: root.selectedTask ? (root.selectedTask.body || "No description added.") : ""; color: root.text; font.pixelSize: 10; wrapMode: Text.WordWrap; elide: Text.ElideRight }
            Rectangle { width: parent.width; height: 1; color: root.border }
            Row { width: parent.width; spacing: 16
              Column { width: parent.width * .40 - 10; spacing: 6; Text { text: "ASSIGNEE"; color: root.muted; font.pixelSize: 9; font.bold: true } ComboBox { id: taskAssignee; width: parent.width; height: 38; model: ["Unassigned"].concat(root.taskAssigneeNames()); currentIndex: root.selectedTask ? Math.max(0, model.indexOf(root.selectedTask.assignee || "Unassigned")) : 0 } }
              Column { width: parent.width * .20 - 10; spacing: 6; Text { text: "PRIORITY"; color: root.muted; font.pixelSize: 9; font.bold: true } TextField { leftPadding: 9; rightPadding: 9; id: taskPriority; width: parent.width; height: 38; text: root.selectedTask ? String(root.selectedTask.priority || 0) : "0"; color: root.text; inputMethodHints: Qt.ImhDigitsOnly; background: Rectangle { radius: 2; color: root.inputFill; border.color: root.border } } }
              Column { width: parent.width * .40 - 10; spacing: 6; Text { text: "ESTIMATED COST · USD"; color: root.muted; font.pixelSize: 9; font.bold: true } TextField { leftPadding: 9; rightPadding: 9; id: taskCost; width: parent.width; height: 38; text: root.selectedTask && root.selectedTask.has_estimate ? String(root.selectedTask.estimated_cost) : ""; placeholderText: "No estimate"; color: root.text; inputMethodHints: Qt.ImhFormattedNumbersOnly; background: Rectangle { radius: 2; color: root.inputFill; border.color: root.border } } }
            }
            Row { width: parent.width; spacing: 8
              TextField { leftPadding: 9; rightPadding: 9; id: taskDue; width: 120; height: 32; text: root.selectedTask ? (root.selectedTask.due_date || "") : ""; placeholderText: "Due YYYY-MM-DD"; color: root.text; font.pixelSize: 8; background: Rectangle { radius: 2; color: root.inputFill; border.color: root.border } }
              TextField { leftPadding: 9; rightPadding: 9; id: taskEffort; width: 85; height: 32; text: root.selectedTask ? String(root.selectedTask.effort_hours || 0) : "0"; placeholderText: "Hours"; color: root.text; font.pixelSize: 8; inputMethodHints: Qt.ImhFormattedNumbersOnly; background: Rectangle { radius: 2; color: root.inputFill; border.color: root.border } }
              TextField { leftPadding: 9; rightPadding: 9; id: taskTags; width: parent.width - 221; height: 32; text: root.selectedTask ? (root.selectedTask.tags || []).join(", ") : ""; placeholderText: "Tags: bug, docs, launch"; color: root.text; font.pixelSize: 8; background: Rectangle { radius: 2; color: root.inputFill; border.color: root.border } }
            }
            Column { width: parent.width; spacing: 3
              Text { text: "ELIGIBLE PROFILES"; color: root.muted; font.pixelSize: 9; font.bold: true }
              Text { text: "Explicit allowlist and per-profile planning budget. Hermes itself does not currently enforce spend caps."; color: root.muted; font.pixelSize: 8; wrapMode: Text.WordWrap; width: parent.width }
              Flow { width: parent.width; height: 78; spacing: 4
                Repeater { model: root.assignableProfiles()
                  delegate: Rectangle { required property var modelData; width: Math.min(155, parent.width / 3); height: 36; color: root.raised; border.color: root.detailAllowedProfiles.indexOf(modelData.slug) >= 0 ? root.accent : root.border
                    Row { anchors.fill: parent; anchors.margins: 2; spacing: 1
                      CheckBox { width: parent.width - 58; height: parent.height; checked: root.detailAllowedProfiles.indexOf(modelData.slug) >= 0; onToggled: root.toggleProfileIn("detail", modelData.slug)
                        contentItem: Text { text: modelData.slug; color: root.text; font.pixelSize: 8; leftPadding: 20; verticalAlignment: Text.AlignVCenter; elide: Text.ElideRight }
                      }
                      Text { text: "$"; color: root.muted; font.pixelSize: 8; anchors.verticalCenter: parent.verticalCenter }
                      TextField { width: 48; height: 27; text: root.detailProfileBudgets[modelData.slug] === undefined ? "" : String(root.detailProfileBudgets[modelData.slug]); placeholderText: "cap"; color: root.text; font.pixelSize: 8; inputMethodHints: Qt.ImhFormattedNumbersOnly; onTextChanged: root.setDetailProfileBudget(modelData.slug, text); background: Rectangle { color: root.inputFill; border.color: root.border } }
                    }
                  }
                }
              }
            }
            Row { width: parent.width; spacing: 12
              Rectangle { width: 136; height: 36; radius: 2; color: root.raised; border.color: root.border; Text { anchors.centerIn: parent; text: "Save assignment"; color: root.text; font.pixelSize: 9 } MouseArea { anchors.fill: parent; onClicked: root.act(root.selectedTask, "assign", {assignee: taskAssignee.currentText === "Unassigned" ? "none" : taskAssignee.currentText}) } }
              Rectangle { width: 112; height: 36; radius: 2; color: root.raised; border.color: root.border; Text { anchors.centerIn: parent; text: "Save priority"; color: root.text; font.pixelSize: 9 } MouseArea { anchors.fill: parent; onClicked: root.act(root.selectedTask, "priority", {priority: Math.min(4, Math.max(0, Number(taskPriority.text) || 0))}) } }
              Rectangle { width: 116; height: 36; radius: 2; color: root.raised; border.color: root.border; Text { anchors.centerIn: parent; text: "Save plan"; color: root.text; font.pixelSize: 9 } MouseArea { anchors.fill: parent; onClicked: root.saveTaskMetadata() } }
            }
            Text { text: "MOVE / CONTROL"; color: root.muted; font.pixelSize: 9; font.bold: true; font.letterSpacing: 1 }
            Flow { width: parent.width; spacing: 8
              Repeater { model: [
                {label:"Promote to ready", action:"promote"}, {label:"Mark blocked", action:"block"}, {label:"Unblock", action:"unblock"},
                {label:"Schedule", action:"schedule"}, {label:"Complete", action:"complete"}, {label:"Archive", action:"archive"}
              ]
                delegate: Rectangle { required property var modelData; width: actionText.implicitWidth + 24; height: 33; radius: 2; color: modelData.action === "complete" ? root.accent : root.raised; border.color: root.border
                  Text { id: actionText; anchors.centerIn: parent; text: modelData.label; color: modelData.action === "complete" ? "#ffffff" : root.text; font.pixelSize: 9 }
                  MouseArea { anchors.fill: parent; onClicked: root.act(root.selectedTask, modelData.action, {}) }
                }
              }
            }
            Row { width: parent.width; height: 28; spacing: 8
              Text { id: dependenciesLabel; text: "DEPENDENCIES"; color: root.muted; font.pixelSize: 9; font.bold: true; anchors.verticalCenter: parent.verticalCenter }
              Text { id: blockedCount; text: root.selectedTaskDetail.parents ? "Blocked by " + root.selectedTaskDetail.parents.length : ""; color: root.amber; font.pixelSize: 8; anchors.verticalCenter: parent.verticalCenter }
              Text { id: unlockCount; text: root.selectedTaskDetail.children ? "unlocks " + root.selectedTaskDetail.children.length : ""; color: root.blue; font.pixelSize: 8; anchors.verticalCenter: parent.verticalCenter }
              Item { width: Math.max(0, parent.width - 200 - 58 - 40 - dependenciesLabel.implicitWidth - blockedCount.implicitWidth - unlockCount.implicitWidth); height: 1 }
              ComboBox { id: dependencyTask; width: 200; height: 28; model: root.tasks.filter(function(t){return t.id !== (root.selectedTask ? root.selectedTask.id : "")}).map(function(t){return t.id + " · " + t.title}); contentItem: Text { text: dependencyTask.displayText; color: root.text; font.pixelSize: 8; elide: Text.ElideRight; verticalAlignment: Text.AlignVCenter; leftPadding: 7 } background: Rectangle { radius: 2; color: root.inputFill; border.color: root.border } }
              Rectangle { width: 58; height: 28; radius: 2; color: root.raised; border.color: root.border; Text { anchors.centerIn: parent; text: "Link"; color: root.text; font.pixelSize: 8 } MouseArea { anchors.fill: parent; onClicked: { var selected = dependencyTask.currentText.split(" · ")[0]; root.request("POST", "/api/task/link", {board: root.currentBoard, parent_id: root.selectedTask.id, child_id: selected}, function(){root.notice="Dependency linked"; root.selectTask(root.selectedTask); root.refresh()}) } } }
            }
            Text { text: "ACTIVITY & COMMENTS"; color: root.muted; font.pixelSize: 9; font.bold: true; font.letterSpacing: 0.7 }
            ListView { width: parent.width; height: 104; clip: true; spacing: 4; model: root.selectedTaskDetail.comments || []
              delegate: Rectangle { required property var modelData; width: parent.width; height: Math.max(34, commentBody.implicitHeight + 16); radius: 2; color: root.raised
                Column { anchors.fill: parent; anchors.margins: 7; spacing: 3
                  Text { text: modelData.author + " · " + new Date(Number(modelData.created_at || 0) * 1000).toLocaleString(); color: root.blue; font.pixelSize: 8 }
                  Text { id: commentBody; text: modelData.body; color: root.text; font.pixelSize: 8; wrapMode: Text.WordWrap; width: parent.width }
                }
              }
            }
            Row { width: parent.width; height: 36; spacing: 8
              TextField { leftPadding: 9; rightPadding: 9; id: taskCommentInput; width: parent.width - 94; height: 34; color: root.text; font.pixelSize: 9; placeholderText: "Add a progress note or handoff…"; placeholderTextColor: root.muted; background: Rectangle { radius: 2; color: root.inputFill; border.color: root.border } }
              Rectangle { width: 86; height: 34; radius: 2; color: root.accent; Text { anchors.centerIn: parent; text: "Comment"; color: "#ffffff"; font.pixelSize: 8; font.bold: true } MouseArea { anchors.fill: parent; onClicked: root.taskComment() } }
            }
            Text { text: "Cost is a planning estimate saved by this app. Actual provider spend depends on model rates and token use."; color: root.muted; font.pixelSize: 9; wrapMode: Text.WordWrap; width: parent.width }
            }
          }
        }
      }

      // Create or clone a profile
      Rectangle { anchors.fill: parent; visible: root.showCreateProfile; color: "#99070b10"; z: 34; MouseArea { anchors.fill: parent; onClicked: {} }
        Rectangle { width: 660; height: Math.min(730, parent.height - 24); radius: 2; color: root.surface; border.color: "#7f9db9"; anchors.centerIn: parent; MouseArea { anchors.fill: parent }
          XpTitleBar { z: 2; anchors.top: parent.top; width: parent.width; caption: "Create / Clone Profile"; darkMode: root.darkMode; onCloseRequested: root.showCreateProfile = false }
          Column { anchors.fill: parent; anchors.margins: 22; anchors.topMargin: 50; spacing: 9
            Row { width: parent.width; height: 42
              Column { spacing: 4; Text { text: "Create a profile"; color: root.text; font.pixelSize: 18; font.bold: true } Text { text: "Start fresh or clone another Hermes profile."; color: root.muted; font.pixelSize: 9 } }
              Item { width: 1; height: 1; Layout.fillWidth: true }
              Item { width: 24; height: 20 }
            }
            Text { text: "PROFILE ID"; color: root.muted; font.pixelSize: 8; font.bold: true; font.letterSpacing: 0.8 }
            TextField { leftPadding: 9; rightPadding: 9; id: newProfileSlug; width: parent.width; height: 36; color: root.text; font.pixelSize: 10; placeholderText: "e.g. ux-reviewer"; placeholderTextColor: root.muted; background: Rectangle { radius: 2; color: root.inputFill; border.color: root.border } }
            Text { text: "ROLE / DESCRIPTION"; color: root.muted; font.pixelSize: 8; font.bold: true; font.letterSpacing: 0.8 }
            TextField { leftPadding: 9; rightPadding: 9; id: newProfileRole; width: parent.width; height: 36; color: root.text; font.pixelSize: 10; placeholderText: "What should this profile be good at?"; placeholderTextColor: root.muted; background: Rectangle { radius: 2; color: root.inputFill; border.color: root.border } }
            Text { text: "CLONE STRATEGY"; color: root.muted; font.pixelSize: 8; font.bold: true; font.letterSpacing: 0.8 }
            ComboBox { id: cloneMode; width: parent.width; height: 36; model: ["Start empty", "Clone config, personality & skills", "Full clone including workspace state"]; contentItem: Text { text: cloneMode.displayText; color: root.text; font.pixelSize: 10; verticalAlignment: Text.AlignVCenter; leftPadding: 10 } background: Rectangle { radius: 2; color: root.inputFill; border.color: root.border } }
            Row { width: parent.width; height: 34; spacing: 10
              Text { text: "CLONE FROM"; color: root.muted; font.pixelSize: 8; font.bold: true; anchors.verticalCenter: parent.verticalCenter }
              ComboBox { id: cloneSource; width: parent.width - 110; height: 34; model: root.profiles.map(function(p){return p.slug}); currentIndex: 0; contentItem: Text { text: cloneSource.displayText; color: root.text; font.pixelSize: 9; verticalAlignment: Text.AlignVCenter; leftPadding: 10 } background: Rectangle { radius: 2; color: root.inputFill; border.color: root.border } }
            }
            CheckBox { id: copyApiKey; text: "Copy source OpenRouter key"; checked: false; enabled: cloneMode.currentIndex > 0; contentItem: Text { text: copyApiKey.text; color: root.muted; font.pixelSize: 9; leftPadding: 26; verticalAlignment: Text.AlignVCenter } }
            Text { text: "NEW OPENROUTER API KEY · optional"; color: root.muted; font.pixelSize: 8; font.bold: true; font.letterSpacing: 0.8 }
            TextField { leftPadding: 9; rightPadding: 9; id: newProfileKey; width: parent.width; height: 36; echoMode: TextInput.Password; color: root.text; font.pixelSize: 10; placeholderText: "Stored privately in this profile’s .env"; placeholderTextColor: root.muted; background: Rectangle { radius: 2; color: root.inputFill; border.color: root.border } }
            Row { width: parent.width; height: 32; spacing: 8
              Text { id: generatedSoulLabel; text: "GENERATED SOUL.md"; color: root.muted; font.pixelSize: 8; font.bold: true; font.letterSpacing: 0.8; anchors.verticalCenter: parent.verticalCenter }
              Item { width: Math.max(0, parent.width - generatedSoulLabel.implicitWidth - 145 - 16); height: 1 }
              Rectangle { width: 145; height: 30; radius: 2; color: root.selectedFill; border.color: root.border
                Text { anchors.centerIn: parent; text: root.generatingPersonality ? "Generating…" : "✦ Generate from name"; color: root.blue; font.pixelSize: 8; font.bold: true }
                MouseArea { anchors.fill: parent; enabled: !root.generatingPersonality; onClicked: root.generatePersonality() }
              }
            }
            TextArea { leftPadding: 10; rightPadding: 10; topPadding: 8; bottomPadding: 8; id: generatedSoul; width: parent.width; height: 180; color: root.text; font.pixelSize: 9; wrapMode: TextEdit.Wrap; selectByMouse: true; placeholderText: "Generate a profile personality from its ID and role, or write one here…"; placeholderTextColor: root.muted; background: Rectangle { radius: 2; color: root.inputFill; border.color: root.border } }
            Row { width: parent.width; height: 36; spacing: 9
              Rectangle { width: 120; height: 36; radius: 2; color: root.accent
                Text { anchors.centerIn: parent; text: "Create profile"; color: "#ffffff"; font.pixelSize: 9; font.bold: true }
                MouseArea { anchors.fill: parent; onClicked: root.createProfile() }
              }
              Rectangle { width: 88; height: 36; radius: 2; color: root.raised; border.color: root.border; Text { anchors.centerIn: parent; text: "Cancel"; color: root.muted; font.pixelSize: 9 } MouseArea { anchors.fill: parent; onClicked: root.showCreateProfile = false } }
              Text { text: "Copied OpenRouter keys are removed unless you opt in; a new key overrides the copied key."; color: root.muted; font.pixelSize: 8; anchors.verticalCenter: parent.verticalCenter; width: parent.width - 225; wrapMode: Text.WordWrap }
            }
          }
        }
      }

      // Delete profile confirmation
      Rectangle { anchors.fill: parent; visible: root.showDeleteProfile; color: "#99070b10"; z: 35; MouseArea { anchors.fill: parent; onClicked: {} }
        Rectangle { width: 440; height: 250; radius: 2; color: root.surface; border.color: root.red; anchors.centerIn: parent; MouseArea { anchors.fill: parent }
          XpTitleBar { z: 2; anchors.top: parent.top; width: parent.width; caption: "Delete Profile"; darkMode: root.darkMode; onCloseRequested: root.showDeleteProfile = false }
          Column { anchors.fill: parent; anchors.margins: 24; anchors.topMargin: 50; spacing: 14
            Text { text: "Delete “" + root.selectedProfile + "”?"; color: root.text; font.pixelSize: 17; font.bold: true }
            Text { text: "Hermes will remove this profile and its local data. Existing Kanban cards may still refer to its name."; color: root.muted; font.pixelSize: 10; wrapMode: Text.WordWrap; width: parent.width }
            Row { spacing: 10
              Rectangle { width: 110; height: 36; radius: 2; color: root.red; Text { anchors.centerIn: parent; text: "Delete profile"; color: "#ffffff"; font.pixelSize: 9; font.bold: true } MouseArea { anchors.fill: parent; onClicked: root.deleteSelectedProfile() } }
              Rectangle { width: 88; height: 36; radius: 2; color: root.raised; border.color: root.border; Text { anchors.centerIn: parent; text: "Cancel"; color: root.muted; font.pixelSize: 9 } MouseArea { anchors.fill: parent; onClicked: root.showDeleteProfile = false } }
            }
          }
        }
      }

      // Prompt editor
      Rectangle { anchors.fill: parent; visible: root.showPromptEditor; color: "#99070b10"; z: 36; MouseArea { anchors.fill: parent; onClicked: {} }
        Rectangle { width: 610; height: 560; radius: 2; color: root.surface; border.color: "#7f9db9"; anchors.centerIn: parent; MouseArea { anchors.fill: parent }
          XpTitleBar { z: 2; anchors.top: parent.top; width: parent.width; caption: "Prompt Editor"; darkMode: root.darkMode; onCloseRequested: root.showPromptEditor = false }
          Column { anchors.fill: parent; anchors.margins: 24; anchors.topMargin: 50; spacing: 12
            Row { width: parent.width
              Column { spacing: 4; Text { text: root.editingPrompt ? "Edit saved prompt" : "Save a prompt"; color: root.text; font.pixelSize: 17; font.bold: true } Text { text: "Keep a reusable prompt in your local library."; color: root.muted; font.pixelSize: 9 } }
              Item { width: 1; height: 1; Layout.fillWidth: true }
              Item { width: 24; height: 20 }
            }
            Text { text: "PROMPT NAME"; color: root.muted; font.pixelSize: 8; font.bold: true }
            TextField { leftPadding: 9; rightPadding: 9; id: promptTitle; width: parent.width; height: 38; color: root.text; font.pixelSize: 10; placeholderText: "e.g. Review a pull request"; background: Rectangle { radius: 2; color: root.inputFill; border.color: root.border } }
            Text { text: "PROMPT TEXT"; color: root.muted; font.pixelSize: 8; font.bold: true }
            TextArea { leftPadding: 10; rightPadding: 10; topPadding: 8; bottomPadding: 8; id: promptBody; width: parent.width; height: 275; color: root.text; font.pixelSize: 10; wrapMode: TextEdit.Wrap; selectByMouse: true; placeholderText: "Write the prompt to reuse…"; background: Rectangle { radius: 2; color: root.inputFill; border.color: root.border } }
            Row { width: parent.width; spacing: 12
              CheckBox { id: promptFavorite; checked: true; text: "Favorite"; contentItem: Text { text: promptFavorite.text; color: root.amber; font.pixelSize: 9; leftPadding: 25; verticalAlignment: Text.AlignVCenter } }
              Item { width: Math.max(0, parent.width - promptFavorite.implicitWidth - 106 - 82 - 36); height: 1 }
              Rectangle { width: 106; height: 36; radius: 2; color: root.accent; Text { anchors.centerIn: parent; text: "Save prompt"; color: "#ffffff"; font.pixelSize: 9; font.bold: true } MouseArea { anchors.fill: parent; onClicked: root.savePrompt() } }
              Rectangle { width: 82; height: 36; radius: 2; color: root.raised; border.color: root.border; Text { anchors.centerIn: parent; text: "Cancel"; color: root.muted; font.pixelSize: 9 } MouseArea { anchors.fill: parent; onClicked: root.showPromptEditor = false } }
            }
          }
        }
      }

      // Provider manager window
      Rectangle { anchors.fill: parent; visible: root.showProviderManager; color: "#99070b10"; z: 39
        MouseArea { anchors.fill: parent; onClicked: {} }
        Rectangle { width: Math.min(1160, parent.width - 24); height: Math.min(790, parent.height - 24); radius: 2; color: root.surface; border.color: "#7f9db9"; anchors.centerIn: parent; MouseArea { anchors.fill: parent }
          XpTitleBar { z: 2; anchors.top: parent.top; width: parent.width; caption: "Provider Connections"; darkMode: root.darkMode; onCloseRequested: root.showProviderManager = false }
          Row { anchors.fill: parent; anchors.margins: 18; anchors.topMargin: 52; anchors.bottomMargin: 16; spacing: 14
            Rectangle { width: 286; height: parent.height; color: root.raised; border.color: root.border
              Column { anchors.fill: parent; anchors.margins: 12; spacing: 8
                Row { width: parent.width; height: 24
                  Text { text: "PROVIDERS"; color: root.blue; font.pixelSize: 9; font.bold: true; font.letterSpacing: 1 }
                  Item { width: Math.max(0, parent.width - 120); height: 1 }
                  Text { text: root.modelProviders.length + " installed"; color: root.muted; font.pixelSize: 8; anchors.verticalCenter: parent.verticalCenter }
                }
                Text { text: "Configure for profile"; color: root.muted; font.pixelSize: 8; font.bold: true }
                ComboBox { id: providerManagerProfileInput; width: parent.width; height: 34; model: root.profiles.map(function(p) { return p.slug }); currentIndex: Math.max(0, root.profiles.map(function(p) { return p.slug }).indexOf(root.providerManagerProfile)); onActivated: { root.providerManagerProfile = currentText; root.selectManagedProvider(root.profileBySlug(currentText).provider || "auto") } contentItem: Text { text: providerManagerProfileInput.displayText; color: root.text; font.pixelSize: 9; elide: Text.ElideRight; verticalAlignment: Text.AlignVCenter; leftPadding: 9; rightPadding: 18 } background: Rectangle { radius: 2; color: root.inputFill; border.color: root.border } }
                TextField { id: providerManagerSearch; width: parent.width; height: 34; leftPadding: 9; rightPadding: 9; placeholderText: "Find provider by name or ID…"; placeholderTextColor: root.muted; color: root.text; font.pixelSize: 9; background: Rectangle { radius: 2; color: root.inputFill; border.color: root.border } }
                ComboBox { id: providerManagerFilter; width: parent.width; height: 32; model: ["All providers", "Active for profile", "Configured", "Needs API key", "Hermes sign-in", "Custom endpoint"]; contentItem: Text { text: providerManagerFilter.displayText; color: root.text; font.pixelSize: 9; elide: Text.ElideRight; verticalAlignment: Text.AlignVCenter; leftPadding: 9; rightPadding: 18 } background: Rectangle { radius: 2; color: root.inputFill; border.color: root.border } }
                ListView { id: providerManagerList; width: parent.width; height: parent.height - 190; clip: true; spacing: 4; model: root.modelProviders.filter(function(provider) { return root.providerManagerMatches(provider) })
                  ScrollBar.vertical: ScrollBar { policy: ScrollBar.AsNeeded }
                  delegate: Rectangle { required property var modelData; width: providerManagerList.width; height: 48; radius: 2; color: root.selectedManagedProvider === modelData.id ? root.selectedFill : root.surface; border.color: root.selectedManagedProvider === modelData.id ? root.accent : root.border
                    Column { anchors.fill: parent; anchors.leftMargin: 9; anchors.rightMargin: 9; anchors.verticalCenter: parent.verticalCenter; spacing: 3
                      Text { text: modelData.label; color: root.selectedManagedProvider === modelData.id ? "#ffffff" : root.text; font.pixelSize: 9; font.bold: true; elide: Text.ElideRight; width: parent.width }
                      Text { text: modelData.id + "  ·  " + root.providerStatus(modelData); color: root.selectedManagedProvider === modelData.id ? "#d8e8ff" : root.muted; font.pixelSize: 8; elide: Text.ElideRight; width: parent.width }
                    }
                    MouseArea { anchors.fill: parent; onClicked: root.selectManagedProvider(modelData.id) }
                  }
                }
                Row { width: parent.width; height: 30; spacing: 7
                  Text { text: "Provider list comes from this Hermes install."; color: root.muted; font.pixelSize: 8; anchors.verticalCenter: parent.verticalCenter; elide: Text.ElideRight; width: parent.width - 40 }
                  Rectangle { width: 28; height: 28; color: root.surface; border.color: root.border
                    Text { anchors.centerIn: parent; text: "↻"; color: root.accent; font.pixelSize: 13 }
                    MouseArea { anchors.fill: parent; onClicked: root.loadModelProviders() }
                  }
                }
              }
            }
            Rectangle { width: parent.width - 300; height: parent.height; color: root.surface; border.color: root.border
              Column { anchors.fill: parent; anchors.margins: 20; spacing: 12
                Row { width: parent.width; height: 40; spacing: 8
                  Column { spacing: 3
                    Text { text: root.providerEntry(root.selectedManagedProvider).label || "Choose a provider"; color: root.text; font.pixelSize: 17; font.bold: true }
                    Text { text: root.selectedManagedProvider + "  ·  " + root.providerStatus(root.providerEntry(root.selectedManagedProvider)); color: root.accent; font.pixelSize: 9 }
                  }
                  Item { width: Math.max(0, parent.width - 280); height: 1 }
                  Rectangle { width: 116; height: 34; radius: 2; color: root.accent
                    Text { anchors.centerIn: parent; text: "Browse models"; color: "#ffffff"; font.pixelSize: 9; font.bold: true }
                    MouseArea { anchors.fill: parent; onClicked: root.openModelCatalog(root.selectedManagedProvider, root.providerManagerProfile, root.selectedManagedProvider === "custom" ? providerManagerBaseUrl.text : "") }
                  }
                }
                Text { text: root.providerEntry(root.selectedManagedProvider).description || root.providerDescription(); color: root.muted; font.pixelSize: 9; wrapMode: Text.WordWrap; width: parent.width; height: 34 }
                Rectangle { width: parent.width; height: 1; color: root.border }
                Row { width: parent.width; height: 20
                  Text { width: Math.max(120, parent.width - profileApplyLabel.implicitWidth - 12); text: "MODEL & ROUTING"; color: root.blue; font.pixelSize: 9; font.bold: true; font.letterSpacing: 0.8 }
                  Item { width: 12; height: 1 }
                  Text { id: profileApplyLabel; text: "Applies to " + root.providerManagerProfile; color: root.muted; font.pixelSize: 8 }
                }
                Text { text: "Default model ID"; color: root.muted; font.pixelSize: 8; font.bold: true }
                TextField { id: providerManagerModel; width: parent.width; height: 38; leftPadding: 10; rightPadding: 10; color: root.text; font.pixelSize: 10; placeholderText: root.selectedManagedProvider === "openrouter" ? "provider/model-name" : "Model ID for this provider"; placeholderTextColor: root.muted; background: Rectangle { radius: 2; color: root.inputFill; border.color: root.border } }
                Text { visible: root.selectedManagedProvider === "custom"; text: "OPENAI-COMPATIBLE ENDPOINT URL"; color: root.muted; font.pixelSize: 8; font.bold: true }
                TextField { id: providerManagerBaseUrl; visible: root.selectedManagedProvider === "custom"; width: parent.width; height: 36; leftPadding: 10; rightPadding: 10; color: root.text; font.pixelSize: 9; placeholderText: "http://localhost:11434/v1"; placeholderTextColor: root.muted; background: Rectangle { radius: 2; color: root.inputFill; border.color: root.border } }
                Rectangle { width: parent.width; height: 1; color: root.border }
                Row { width: parent.width; height: 22
                  Text { id: credentialLabel; width: Math.max(120, parent.width - credentialStatus.implicitWidth - 12); text: root.keyEnvName() ? (root.selectedManagedProvider === "custom" ? "CUSTOM ENDPOINT API KEY" : root.keyEnvName()) : "HERMES-MANAGED AUTHENTICATION"; color: root.blue; font.pixelSize: 9; font.bold: true; font.letterSpacing: 0.5; elide: Text.ElideRight; anchors.verticalCenter: parent.verticalCenter }
                  Item { width: 12; height: 1 }
                  Text { id: credentialStatus; text: !root.keyEnvName() ? (root.selectedManagedProvider === "auto" ? "No key required" : "Use Hermes CLI") : (root.providerCredentialConfigured() ? "Configured · value hidden" : "Not configured"); color: root.keyEnvName() ? (root.providerCredentialConfigured() ? root.accent : root.amber) : root.muted; font.pixelSize: 8; anchors.verticalCenter: parent.verticalCenter }
                }
                ComboBox { id: providerManagerCredentialInput; visible: root.providerCredentialOptions(root.selectedManagedProvider).length > 1; width: Math.min(320, parent.width); height: 32; model: root.providerCredentialOptions(root.selectedManagedProvider); currentIndex: Math.max(0, root.providerCredentialOptions(root.selectedManagedProvider).indexOf(root.managedCredentialName)); onActivated: root.managedCredentialName = currentText; contentItem: Text { text: providerManagerCredentialInput.displayText; color: root.text; font.pixelSize: 9; elide: Text.ElideRight; verticalAlignment: Text.AlignVCenter; leftPadding: 9; rightPadding: 18 } background: Rectangle { radius: 2; color: root.inputFill; border.color: root.border } }
                TextField { id: providerManagerKey; visible: !!root.keyEnvName(); width: parent.width; height: 38; leftPadding: 10; rightPadding: 10; echoMode: TextInput.Password; color: root.text; font.pixelSize: 10; placeholderText: "Paste or replace the key for this profile"; placeholderTextColor: root.muted; background: Rectangle { radius: 2; color: root.inputFill; border.color: root.border } }
                Row { visible: !!root.keyEnvName(); width: parent.width; spacing: 8
                  Rectangle { width: 116; height: 34; radius: 2; color: root.accent
                    Text { anchors.centerIn: parent; text: "Save API key"; color: "#ffffff"; font.pixelSize: 9; font.bold: true }
                    MouseArea { anchors.fill: parent; enabled: root.selectedManagedProvider !== "custom" || root.profileBySlug(root.providerManagerProfile).provider === "custom"; onClicked: root.saveProfileKey() }
                  }
                  Rectangle { width: 90; height: 34; radius: 2; color: root.raised; border.color: root.border
                    Text { anchors.centerIn: parent; text: "Clear key"; color: root.red; font.pixelSize: 9 }
                    MouseArea { anchors.fill: parent; enabled: root.providerCredentialConfigured(); onClicked: root.clearProfileKey() }
                  }
                  Text { visible: root.selectedManagedProvider === "custom" && root.profileBySlug(root.providerManagerProfile).provider !== "custom"; text: "Set Custom as the profile provider before saving its key."; color: root.amber; font.pixelSize: 8; anchors.verticalCenter: parent.verticalCenter }
                }
                Text { visible: !root.keyEnvName(); text: root.providerDescription() + ". Use the Hermes CLI: hermes model. Hermes-managed credentials stay in its own secure store."; color: root.muted; font.pixelSize: 9; wrapMode: Text.WordWrap; width: parent.width }
                Text { text: (root.providerEntry(root.selectedManagedProvider).env_vars || []).length ? "Credential variables: " + root.providerEntry(root.selectedManagedProvider).env_vars.join(", ") : "This provider does not declare API-key environment variables."; color: root.muted; font.pixelSize: 8; wrapMode: Text.WordWrap; width: parent.width }
                Item { width: 1; height: 1; Layout.fillHeight: true }
                Row { width: parent.width; spacing: 8
                  Rectangle { width: 166; height: 38; radius: 2; color: root.selectedFill; border.color: root.border
                    Text { anchors.centerIn: parent; text: "Use provider for profile"; color: "#ffffff"; font.pixelSize: 9; font.bold: true }
                    MouseArea { anchors.fill: parent; onClicked: root.saveManagedProvider() }
                  }
                  Text { text: "Provider selection, model, and credentials are saved for the chosen profile only."; color: root.muted; font.pixelSize: 8; anchors.verticalCenter: parent.verticalCenter; wrapMode: Text.WordWrap; width: parent.width - 180 }
                }
              }
            }
          }
        }
      }

      // Provider-aware model catalog
      Rectangle { anchors.fill: parent; visible: root.showModels; color: "#99070b10"; z: 40
        MouseArea { anchors.fill: parent; onClicked: {} }
        Rectangle { width: Math.min(1120, parent.width - 24); height: Math.min(790, parent.height - 24); radius: 2; color: root.surface; border.color: "#7f9db9"; anchors.centerIn: parent
          XpTitleBar { z: 2; anchors.top: parent.top; width: parent.width; caption: root.catalogProviderName() + " Model Catalog"; darkMode: root.darkMode; onCloseRequested: root.showModels = false }
          MouseArea { anchors.fill: parent }
          Column { anchors.fill: parent; anchors.margins: 22; anchors.topMargin: 50; spacing: 8
            Row { width: parent.width; height: 44
              Column { id: catalogHeading; spacing: 4
                Text { text: root.catalogProviderName() + " model catalog"; color: root.text; font.pixelSize: 18; font.bold: true }
                Text { text: root.modelCatalogLoading ? "Loading " + root.catalogProviderName() + " models…" : root.modelCatalog.length + " models · " + (root.modelCatalogStale ? "cached, refresh failed" : root.modelCatalogSource === "live" ? "live catalog" : root.modelCatalogSource === "cache" ? "cached catalog" : root.modelCatalogSource) + (root.modelCatalogFetchedAt ? " · updated " + new Date(root.modelCatalogFetchedAt * 1000).toLocaleString() : ""); color: root.muted; font.pixelSize: 9 }
              }
              Item { width: Math.max(0, parent.width - catalogHeading.implicitWidth - 88 - 24); height: 1 }
              Rectangle { width: 88; height: 34; radius: 2; color: root.raised; border.color: root.border
                Text { anchors.centerIn: parent; text: root.modelCatalogLoading ? "Loading…" : "↻ Refresh"; color: root.accent; font.pixelSize: 9; font.bold: true }
                MouseArea { anchors.fill: parent; enabled: !root.modelCatalogLoading; onClicked: root.loadModelCatalog(true) }
              }
              Item { width: 24; height: 20 }
            }
            Row { width: parent.width; height: 38; spacing: 8
              ComboBox { id: catalogProviderInput; width: 170; height: 36; model: root.modelProviders; textRole: "label"; valueRole: "id"; currentIndex: Math.max(0, root.providerIndex(root.modelCatalogProvider)); onActivated: root.loadModelCatalog(false, currentValue, root.modelCatalogProfile, currentValue === "custom" ? root.modelCatalogBaseUrl : ""); contentItem: Text { text: catalogProviderInput.displayText; color: root.text; font.pixelSize: 9; elide: Text.ElideRight; verticalAlignment: Text.AlignVCenter; leftPadding: 9; rightPadding: 18 } background: Rectangle { radius: 2; color: root.inputFill; border.color: root.border } }
              TextField { leftPadding: 10; rightPadding: 10; id: modelSearch; width: 290; height: 36; color: root.text; font.pixelSize: 10; placeholderText: "Search model, creator, capability…"; placeholderTextColor: root.muted; onTextChanged: root.catalogVisibleLimit = 100; background: Rectangle { radius: 2; color: root.inputFill; border.color: root.border } }
              ComboBox { id: catalogPublisherFilter; width: 135; height: 36; model: root.catalogPublishers; contentItem: Text { text: catalogPublisherFilter.displayText; color: root.text; font.pixelSize: 9; elide: Text.ElideRight; verticalAlignment: Text.AlignVCenter; leftPadding: 9; rightPadding: 18 } background: Rectangle { radius: 2; color: root.inputFill; border.color: root.border } }
              ComboBox { id: modelUseFilter; width: 135; height: 36; model: ["All uses", "Favorites", "Text & chat", "Coding", "Vision", "Image generation", "Audio", "Video", "Embeddings", "Reranking", "Decision", "Files & documents", "Other"]; contentItem: Text { text: modelUseFilter.displayText; color: root.text; font.pixelSize: 9; elide: Text.ElideRight; verticalAlignment: Text.AlignVCenter; leftPadding: 9; rightPadding: 18 } background: Rectangle { radius: 2; color: root.inputFill; border.color: root.border } }
            }
            Row { width: parent.width; height: 36; spacing: 8
              ComboBox { id: catalogGroupBy; width: 150; height: 34; model: ["Group: use", "Group: creator", "Group: input cost", "Group: output cost", "Group: context", "Group: modality"]; contentItem: Text { text: catalogGroupBy.displayText; color: root.text; font.pixelSize: 9; elide: Text.ElideRight; verticalAlignment: Text.AlignVCenter; leftPadding: 9; rightPadding: 18 } background: Rectangle { radius: 2; color: root.inputFill; border.color: root.border } }
              ComboBox { id: catalogSort; width: 205; height: 34; model: ["Provider order", "Name · A to Z", "Newest first", "Input · low to high", "Output · low to high", "Average cost · low to high", "Context · high to low", "Input · high to low", "Output · high to low"]; contentItem: Text { text: catalogSort.displayText; color: root.text; font.pixelSize: 9; elide: Text.ElideRight; verticalAlignment: Text.AlignVCenter; leftPadding: 9; rightPadding: 18 } background: Rectangle { radius: 2; color: root.inputFill; border.color: root.border } }
              ComboBox { id: catalogModalityFilter; width: 145; height: 34; model: ["Any modality", "Text input", "Image input", "Audio input", "Video input", "Image output", "Audio output", "Embeddings"]; contentItem: Text { text: catalogModalityFilter.displayText; color: root.text; font.pixelSize: 9; elide: Text.ElideRight; verticalAlignment: Text.AlignVCenter; leftPadding: 9; rightPadding: 18 } background: Rectangle { radius: 2; color: root.inputFill; border.color: root.border } }
            }
            Row { width: parent.width; height: 36; spacing: 8
              ComboBox { id: catalogPriceFilter; width: 135; height: 34; model: ["Any input price", "Free", "Under $1 / M", "$1–5 / M", "$5–20 / M", "$20+ / M"]; contentItem: Text { text: catalogPriceFilter.displayText; color: root.text; font.pixelSize: 9; elide: Text.ElideRight; verticalAlignment: Text.AlignVCenter; leftPadding: 9; rightPadding: 18 } background: Rectangle { radius: 2; color: root.inputFill; border.color: root.border } }
              ComboBox { id: catalogOutputPriceFilter; width: 140; height: 34; model: ["Any output price", "Free", "Under $1 / M", "$1–5 / M", "$5–20 / M", "$20+ / M"]; contentItem: Text { text: catalogOutputPriceFilter.displayText; color: root.text; font.pixelSize: 9; elide: Text.ElideRight; verticalAlignment: Text.AlignVCenter; leftPadding: 9; rightPadding: 18 } background: Rectangle { radius: 2; color: root.inputFill; border.color: root.border } }
              ComboBox { id: catalogContextFilter; width: 115; height: 34; model: ["Any context", "64K+", "128K+", "256K+", "1M+"]; contentItem: Text { text: catalogContextFilter.displayText; color: root.text; font.pixelSize: 9; elide: Text.ElideRight; verticalAlignment: Text.AlignVCenter; leftPadding: 9; rightPadding: 18 } background: Rectangle { radius: 2; color: root.inputFill; border.color: root.border } }
              ComboBox { id: catalogCapabilityFilter; width: 130; height: 34; model: ["Any capability", "Tool calling", "Reasoning", "Structured output"]; contentItem: Text { text: catalogCapabilityFilter.displayText; color: root.text; font.pixelSize: 9; elide: Text.ElideRight; verticalAlignment: Text.AlignVCenter; leftPadding: 9; rightPadding: 18 } background: Rectangle { radius: 2; color: root.inputFill; border.color: root.border } }
              Text { text: "IN"; color: root.muted; font.pixelSize: 8; font.bold: true; anchors.verticalCenter: parent.verticalCenter }
              TextField { id: samplePromptInput; width: 72; height: 34; text: String(root.samplePromptTokens); color: root.text; font.pixelSize: 9; inputMethodHints: Qt.ImhDigitsOnly; ToolTip.visible: hovered; ToolTip.text: "Sample input tokens"; onTextChanged: root.samplePromptTokens = Math.max(0, Math.min(10000000, parseInt(text) || 0)); background: Rectangle { radius: 2; color: root.inputFill; border.color: root.border } }
              Text { text: "OUT"; color: root.muted; font.pixelSize: 8; font.bold: true; anchors.verticalCenter: parent.verticalCenter }
              TextField { id: sampleCompletionInput; width: 72; height: 34; text: String(root.sampleCompletionTokens); color: root.text; font.pixelSize: 9; inputMethodHints: Qt.ImhDigitsOnly; ToolTip.visible: hovered; ToolTip.text: "Sample output tokens"; onTextChanged: root.sampleCompletionTokens = Math.max(0, Math.min(10000000, parseInt(text) || 0)); background: Rectangle { radius: 2; color: root.inputFill; border.color: root.border } }
              Rectangle { width: 80; height: 34; radius: 2; color: root.raised; border.color: root.border
                Text { anchors.centerIn: parent; text: "Reset filters"; color: root.accent; font.pixelSize: 8; font.bold: true }
                MouseArea { anchors.fill: parent; onClicked: root.resetCatalogFilters() }
              }
            }
            Row { width: parent.width; height: 32; spacing: 8
              Rectangle { width: 105; height: 30; radius: 2; color: root.raised; border.color: root.border
                Text { anchors.centerIn: parent; text: "Collapse all groups"; color: root.accent; font.pixelSize: 8; font.bold: true }
                MouseArea { anchors.fill: parent; onClicked: root.collapseAllCatalogGroups() }
              }
              Rectangle { width: 105; height: 30; radius: 2; color: root.raised; border.color: root.border
                Text { anchors.centerIn: parent; text: "Expand all groups"; color: root.accent; font.pixelSize: 8; font.bold: true }
                MouseArea { anchors.fill: parent; onClicked: root.expandAllCatalogGroups() }
              }
              Text { id: catalogCount; text: root.catalogItems.length + " matching · " + Math.min(root.catalogItems.length, root.catalogVisibleLimit) + " loaded · " + root.modelCatalog.length + " total"; color: root.muted; font.pixelSize: 9; anchors.verticalCenter: parent.verticalCenter }
            }
            Row { width: parent.width; height: 28; spacing: 8
              Text { text: "MODEL"; color: root.muted; font.pixelSize: 8; font.bold: true; font.letterSpacing: 1; width: parent.width * 0.55; leftPadding: 12; anchors.verticalCenter: parent.verticalCenter }
              Text { text: "INPUT / 1M TOKENS"; color: root.muted; font.pixelSize: 8; font.bold: true; width: 118; anchors.verticalCenter: parent.verticalCenter }
              Text { text: "OUTPUT / 1M TOKENS"; color: root.muted; font.pixelSize: 8; font.bold: true; width: 128; anchors.verticalCenter: parent.verticalCenter }
              Text { text: "CONTEXT"; color: root.muted; font.pixelSize: 8; font.bold: true; width: 70; anchors.verticalCenter: parent.verticalCenter }
              Item { width: 28; height: 1 }
              Item { width: 75; height: 1 }
            }
            ListView { id: catalogList; width: parent.width; height: parent.height - 340; clip: true; spacing: 6; model: root.catalogDisplayItems; section.property: "catalog_section"; section.criteria: ViewSection.FullString
              section.delegate: Rectangle { width: catalogList.width; height: 25; radius: 2; color: root.raised
                Text { anchors.left: parent.left; anchors.leftMargin: 12; anchors.verticalCenter: parent.verticalCenter; text: (root.catalogGroupIsCollapsed(section) ? "▸  " : "▾  ") + section + "   ·   " + root.catalogItems.filter(function(item) { return item.catalog_section === section }).length; color: root.accent; font.pixelSize: 9; font.bold: true; font.letterSpacing: 0.4 }
                MouseArea { anchors.fill: parent; cursorShape: Qt.PointingHandCursor; onClicked: root.toggleCatalogGroup(section) }
              }
              ScrollBar.vertical: ScrollBar { policy: ScrollBar.AsNeeded }
              delegate: Rectangle { required property var modelData; width: catalogList.width; height: modelData.is_placeholder ? 0 : 74; visible: !modelData.is_placeholder; radius: 2; color: modelHover.containsMouse ? root.hoverFill : root.surface; border.color: root.border
              MouseArea { id: modelHover; anchors.fill: parent; hoverEnabled: true; onClicked: root.chooseCatalogModel(modelData.id) }
                Row { anchors.fill: parent; anchors.leftMargin: 12; anchors.rightMargin: 12; spacing: 8
                  Column { width: parent.width * 0.55 - 8; anchors.verticalCenter: parent.verticalCenter; spacing: 5
                    Text { text: modelData.name; color: root.text; font.pixelSize: 10; font.bold: true; elide: Text.ElideRight; width: parent.width }
                  Text { text: modelData.id + "   ·   " + modelData.category + (modelData.inputs.length ? "   ·   " + modelData.inputs.join(" + ") + " → " + modelData.outputs.join(" + ") : "") + ((modelData.supported_parameters || []).indexOf("tools") >= 0 ? "   ·   tools" : "") + (modelData.max_completion_tokens ? "   ·   max " + Math.round(modelData.max_completion_tokens / 1000) + "K out" : ""); color: root.muted; font.pixelSize: 8; elide: Text.ElideRight; width: parent.width }
                  }
                  Text { text: modelData.price_known === false ? "n/a" : root.formatRate(modelData.input_rate); color: root.text; font.pixelSize: 10; width: 118; anchors.verticalCenter: parent.verticalCenter }
                  Column { width: 128; anchors.verticalCenter: parent.verticalCenter; spacing: 3
                    Text { text: modelData.price_known === false ? "n/a" : root.formatRate(modelData.output_rate); color: root.text; font.pixelSize: 10 }
                    Text { visible: root.modelExtraPricing(modelData).length > 0; text: root.modelExtraPricing(modelData); color: root.muted; font.pixelSize: 8 }
                    Text { text: root.estimatedModelCost(modelData) === null ? "Sample: n/a" : "Sample: $" + root.estimatedModelCost(modelData).toFixed(4); color: root.accent; font.pixelSize: 8 }
                  }
                  Text { text: modelData.context_length ? (modelData.context_length >= 1000000 ? (modelData.context_length / 1000000).toFixed(1) + "M" : Math.round(modelData.context_length / 1000) + "K") : "—"; color: root.muted; font.pixelSize: 9; width: 70; anchors.verticalCenter: parent.verticalCenter }
                  Rectangle { width: 28; height: 28; radius: 2; color: root.raised; anchors.verticalCenter: parent.verticalCenter
                    Text { anchors.centerIn: parent; text: root.favoriteModels.indexOf(modelData.id) >= 0 ? "★" : "☆"; color: root.favoriteModels.indexOf(modelData.id) >= 0 ? root.amber : root.muted; font.pixelSize: 15 }
                    MouseArea { anchors.fill: parent; onClicked: root.toggleModelFavorite(modelData.id) }
                  }
                  Rectangle { width: 75; height: 30; radius: 2; color: root.accent; anchors.verticalCenter: parent.verticalCenter
                    Text { anchors.centerIn: parent; text: "Use model"; color: "#ffffff"; font.pixelSize: 8; font.bold: true }
                    MouseArea { anchors.fill: parent; onClicked: root.chooseCatalogModel(modelData.id) }
                  }
                }
              }
            }
            Rectangle { visible: root.catalogItems.length > root.catalogVisibleLimit; width: parent.width; height: 30; radius: 2; color: root.raised; border.color: root.border
              Text { anchors.centerIn: parent; text: "Show next 100 models · " + (root.catalogItems.length - root.catalogVisibleLimit) + " remaining"; color: root.accent; font.pixelSize: 9; font.bold: true }
              MouseArea { anchors.fill: parent; onClicked: root.catalogVisibleLimit += 100 }
            }
            Text { visible: !root.modelCatalogLoading && root.catalogItems.length === 0; text: root.modelCatalogError || (root.modelCatalog.length ? "No models match those filters." : "No model catalog is available for " + root.catalogProviderName() + ". Check provider credentials and refresh."); color: root.muted; font.pixelSize: 10; anchors.horizontalCenter: parent.horizontalCenter }
            Text { text: "Sample estimate uses " + root.samplePromptTokens + " input + " + root.sampleCompletionTokens + " output tokens. " + (root.modelCatalogProvider === "openrouter" ? "Published OpenRouter list prices are per million tokens; image/request charges may differ." : "A dash means this provider did not publish pricing or context details in Hermes' model list."); color: "#667783"; font.pixelSize: 8; wrapMode: Text.WordWrap; width: parent.width }
          }
        }
      }
    }
  }
}
