import QtQuick
import Quickshell
import Quickshell.Io

// Coolify fetch service. The helper talks to the API; this item schedules it
// and exposes one model to the panel. V1 is a single source. The payload
// already has `sources[]` so extra Coolify instances can land later.
Item {
  id: root

  property var settings: ({})
  property bool loading: false
  property string state: "unconfigured"
  property string message: "Paste your Coolify URL and API token in settings."
  property string fetchedAt: ""
  property var source: ({})
  property var sources: []
  property var running: []
  property var recent: []
  property var failures: []
  property var warnings: []
  property string _stdout: ""
  property string _stderr: ""
  property bool refreshQueued: false

  readonly property int configuredIntervalSec: intSetting("refreshIntervalSec", 30, 10, 600)
  readonly property int refreshIntervalSec: running.length > 0 ? Math.min(15, configuredIntervalSec) : configuredIntervalSec
  readonly property bool iconAlwaysUnlit: boolSetting("iconAlwaysUnlit", false)
  readonly property string linkBehavior: String(setting("linkBehavior", "Web app window")).toLowerCase() === "browser tab" ? "Browser tab" : "Web app window"
  readonly property string baseUrl: String(setting("baseUrl", "")).trim()
  readonly property string token: String(setting("token", "")).trim()
  readonly property bool configured: baseUrl !== "" && token !== ""
  readonly property int runningCount: running.length
  readonly property int failureCount: failures.length
  readonly property bool alarming: !iconAlwaysUnlit && (runningCount > 0 || failureCount > 0)

  function setting(name, fallback) {
    var value = settings ? settings[name] : undefined
    return value === undefined || value === null ? fallback : value
  }

  function intSetting(name, fallback, minimum, maximum) {
    var value = parseInt(String(setting(name, fallback)), 10)
    if (!isFinite(value))
      value = fallback
    return Math.max(minimum, Math.min(maximum, value))
  }

  function boolSetting(name, fallback) {
    var value = setting(name, fallback)
    if (value === true || value === false)
      return value
    var text = String(value).toLowerCase()
    return text === "true" || text === "yes" || text === "on" || text === "1"
  }

  function helperPath() {
    return decodeURIComponent(Qt.resolvedUrl("omarchy-coolify-fetch").toString().replace(/^file:\/\//, ""))
  }

  function refresh() {
    if (!configured) {
      state = "unconfigured"
      message = "Paste your Coolify URL and API token in settings."
      running = []
      recent = []
      failures = []
      warnings = []
      loading = false
      return
    }
    if (fetchProcess.running) {
      refreshQueued = true
      return
    }
    refreshQueued = false
    loading = true
    _stdout = ""
    _stderr = ""
    fetchProcess.environment = {
      "COOLIFY_BASE_URL": baseUrl,
      "COOLIFY_TOKEN": token,
      "COOLIFY_HISTORY_TAKE": "8",
      "COOLIFY_APP_LIMIT": "40"
    }
    fetchProcess.command = [helperPath()]
    fetchProcess.running = true
  }

  function apply(raw) {
    try {
      var data = JSON.parse(String(raw || ""))
      state = String(data.state || "error")
      message = String(data.message || "")
      fetchedAt = String(data.fetchedAt || "")
      source = data.source || {}
      sources = Array.isArray(data.sources) ? data.sources : []
      running = Array.isArray(data.running) ? data.running : []
      recent = Array.isArray(data.recent) ? data.recent : []
      failures = Array.isArray(data.failures) ? data.failures : []
      warnings = Array.isArray(data.warnings) ? data.warnings : []
    } catch (error) {
      state = "error"
      message = "Coolify returned an unreadable response."
      warnings = [String(error)]
    }
  }

  onConfiguredChanged: refresh()
  onConfiguredIntervalSecChanged: poll.restart()
  onRunningCountChanged: poll.restart()
  Component.onCompleted: refresh()

  Timer {
    id: poll
    interval: Math.max(1000, root.refreshIntervalSec * 1000)
    repeat: true
    running: root.configured
    onTriggered: root.refresh()
  }

  Process {
    id: fetchProcess
    running: false
    command: []
    onExited: function() {
      root.loading = false
      var stdout = String(output.text || root._stdout || "")
      var stderr = String(errors.text || root._stderr || "").trim()
      if (stdout.trim() !== "") {
        root.apply(stdout)
      } else {
        root.state = "error"
        root.message = stderr !== "" ? stderr : "Coolify refresh failed."
      }
      if (root.refreshQueued) {
        root.refreshQueued = false
        Qt.callLater(root.refresh)
      }
    }
    stdout: StdioCollector {
      id: output
      waitForEnd: true
      onStreamFinished: root._stdout = text
    }
    stderr: StdioCollector {
      id: errors
      waitForEnd: true
      onStreamFinished: root._stderr = text
    }
  }
}
