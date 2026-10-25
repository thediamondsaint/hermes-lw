import QtQml

QtObject {
  id: client
  property int pendingCount: 0
  property Component deadlineFactory: Component {
    Timer {
      property var expired
      repeat: false
      onTriggered: if (expired) expired()
    }
  }

  // QML provides XHR Level 1: use a real Timer, rather than browser-only
  // timeout/onerror properties. Every path settles exactly once.
  function send(method, url, payload, timeoutMs, success, failure) {
    var xhr = new XMLHttpRequest()
    var deadline = deadlineFactory.createObject(client, {interval: timeoutMs || 20000})
    var settled = false
    client.pendingCount += 1
    function complete(ok, value) {
      if (settled) return
      settled = true
      deadline.stop()
      deadline.destroy()
      client.pendingCount = Math.max(0, client.pendingCount - 1)
      if (ok) { if (success) success(value) }
      else if (failure) failure(value)
    }
    deadline.expired = function() {
      complete(false, {error: "Hermes request timed out", status: 0, transport_error: true, timed_out: true})
      xhr.abort()
    }
    xhr.onreadystatechange = function() {
      if (settled || xhr.readyState !== XMLHttpRequest.DONE) return
      if (xhr.status === 0) {
        complete(false, {error: "Hermes LW backend is unreachable", status: 0, transport_error: true})
        return
      }
      var value
      try {
        value = JSON.parse(xhr.responseText)
        if (!value || typeof value !== "object" || Array.isArray(value)) throw new Error("Expected a JSON object")
      } catch (e) {
        complete(false, {error: "Invalid JSON response from Hermes LW", status: xhr.status, transport_error: false})
        return
      }
      if (xhr.status >= 200 && xhr.status < 300) complete(true, value)
      else complete(false, Object.assign({}, value, {error: value.error || "Request failed", status: xhr.status, transport_error: false}))
    }
    try {
      xhr.open(method, url)
      if (method !== "GET") xhr.setRequestHeader("Content-Type", "application/json")
      deadline.start()
      xhr.send(method === "GET" ? "" : JSON.stringify(payload || {}))
    } catch (e) {
      complete(false, {error: "Could not send Hermes request: " + e.message, status: 0, transport_error: true})
    }
  }
}
