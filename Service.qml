import QtQuick
import Quickshell
import Quickshell.Io
import "DeploymentNotificationDeduper.js" as DeploymentNotificationDeduper

// Coolify fetch service. The helper talks to the API; this item schedules it,
// exposes one model to the panel, and tracks deployment transitions for
// desktop notifications. Multiple named sources go out as COOLIFY_SOURCES.
// A lone baseUrl/token pair is treated as "Personal".
Item {
  id: root

  property var settings: ({})
  property string omarchyPath: Quickshell.env("OMARCHY_PATH")
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
  property var deploymentStates: ({})

  readonly property int configuredIntervalSec: intSetting("refreshIntervalSec", 30, 10, 600)
  readonly property int refreshIntervalSec: running.length > 0 ? Math.min(15, configuredIntervalSec) : configuredIntervalSec
  readonly property bool iconAlwaysUnlit: boolSetting("iconAlwaysUnlit", false)
  readonly property string linkBehavior: String(setting("linkBehavior", "Web app window")).toLowerCase() === "browser tab" ? "Browser tab" : "Web app window"
  readonly property var sourcesConfig: sourcesFromSettings(settings)
  readonly property bool notificationsEnabled: boolSetting("notificationsEnabled", true)
  readonly property bool notificationSoundEnabled: boolSetting("notificationSoundEnabled", true)
  readonly property bool configured: hasConfiguredSource(sourcesConfig)
  readonly property int runningCount: running.length
  readonly property int failureCount: failures.length
  readonly property bool alarming: !iconAlwaysUnlit && (runningCount > 0 || failureCount > 0)
  readonly property string runningBadge: runningCount > 9 ? "9+" : String(runningCount)

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
  function notificationCommand() {
    var path = String(omarchyPath || "").trim().replace(/\/+$/, "")
    return path !== "" ? path + "/bin/omarchy-notification-send" : "omarchy-notification-send"
  }
  function notificationSoundPath() {
    return decodeURIComponent(Qt.resolvedUrl("coolify-notification.wav").toString().replace(/^file:\/\//, ""))
  }

  function playNotificationSound() {
    if (!notificationSoundEnabled)
      return
    try {
      Quickshell.execDetached([
        "pw-play",
        "--media-category", "Notification",
        "--media-role", "Notification",
        "--volume", "0.35",
        notificationSoundPath()
      ])
    } catch (error) {
      console.warn("coolify", "Could not play deployment notification sound:", error)
    }
  }


  function isActiveDeployment(kind) {
    return kind === "running" || kind === "queued"
  }

  function deploymentBody(deploy) {
    var parts = []
    var sourceName = String(deploy.sourceName || "").trim()
    var applicationName = String(deploy.applicationName || "Unknown").trim()
    var commit = String(deploy.commit || "").trim()
    if (sourceName !== "")
      parts.push(sourceName)
    if (applicationName !== "")
      parts.push(applicationName)
    if (commit !== "")
      parts.push(commit)
    return parts.join(" · ")
  }

  function notifyDeployment(sourceId, statusKind, summary, deploy, urgency, glyph) {
    if (!notificationsEnabled)
      return
    var deploymentId = String(deploy.id || "").trim()
    if (deploymentId === ""
        || !DeploymentNotificationDeduper.claim(sourceId, deploymentId, statusKind))
      return
    var args = [
      notificationCommand(),
      "--app-name", "Coolify",
      "-g", glyph,
      "-u", urgency,
      "-t", "10000",
      summary,
      deploymentBody(deploy)
    ]
    try {
      Quickshell.execDetached(args)
    } catch (error) {
      DeploymentNotificationDeduper.release(sourceId, deploymentId, statusKind)
      console.warn("coolify", "Could not send deployment notification:", error)
      return
    }
    playNotificationSound()
  }

  function collectDeploymentStates(target, rows) {
    var items = rows || []
    for (var i = 0; i < items.length; i++) {
      var deploy = items[i] || {}
      var id = String(deploy.id || "").trim()
      if (id === "")
        continue
      target[id] = {
        kind: String(deploy.statusKind || "unknown"),
        deploy: deploy
      }
    }
  }

  function currentDeploymentStates(sourceRows) {
    var result = {}
    var rows = sourceRows || []
    for (var i = 0; i < rows.length; i++) {
      var source = rows[i] || {}
      if (String(source.state || "") !== "ready")
        continue
      var sourceId = String(source.id || "default")
      var states = {}
      collectDeploymentStates(states, source.recent)
      collectDeploymentStates(states, source.running)
      result[sourceId] = states
    }
    return result
  }

  function previousReadyDeploymentStates(sourceRows) {
    var result = {}
    var rows = sourceRows || []
    for (var i = 0; i < rows.length; i++) {
      var source = rows[i] || {}
      if (String(source.state || "") !== "ready")
        continue
      var sourceId = String(source.id || "default")
      result[sourceId] = deploymentStates[sourceId] || {}
    }
    return result
  }

  function notifyDeploymentChanges(previous, next) {
    for (var sourceId in next) {
      var nextSource = next[sourceId] || {}
      var previousSource = previous[sourceId] || {}
      for (var id in nextSource) {
        var nextState = nextSource[id] || {}
        var previousState = previousSource[id] || {}
        var nextKind = String(nextState.kind || "")
        var previousKind = String(previousState.kind || "")
        if (isActiveDeployment(nextKind) && !isActiveDeployment(previousKind)) {
          notifyDeployment(sourceId, nextKind, "Deploy in progress", nextState.deploy, "normal", "󰑐")
        } else if (isActiveDeployment(previousKind) && nextKind === "success") {
          notifyDeployment(sourceId, nextKind, "Deploy succeeded", nextState.deploy, "normal", "󰄬")
        } else if (isActiveDeployment(previousKind) && nextKind === "failed") {
          notifyDeployment(sourceId, nextKind, "Deploy failed", nextState.deploy, "critical", "󰅙")
        }
      }
    }
  }

  function updateDeploymentNotifications(sourceRows) {
    var previous = previousReadyDeploymentStates(sourceRows)
    var next = currentDeploymentStates(sourceRows)
    notifyDeploymentChanges(previous, next)
    deploymentStates = next
  }

  function resetDeploymentNotifications() {
    deploymentStates = ({})
  }

  function helperPath() {
    return decodeURIComponent(Qt.resolvedUrl("omarchy-coolify-fetch").toString().replace(/^file:\/\//, ""))
  }

  function sourcesFromSettings(value) {
    var data = value || {}
    var raw = data.sources
    var list = []
    if (raw && raw.length) {
      for (var i = 0; i < raw.length; i++) {
        var item = raw[i] || {}
        list.push({
          id: String(item.id || ("src-" + i)),
          name: String(item.name || "Coolify").trim() || "Coolify",
          baseUrl: String(item.baseUrl || "").trim(),
          token: String(item.token || "").trim()
        })
      }
    }
    if (list.length === 0) {
      var url = String(data.baseUrl || "").trim()
      var token = String(data.token || "").trim()
      if (url !== "" || token !== "") {
        list.push({
          id: "default",
          name: String(data.sourceName || "Personal").trim() || "Personal",
          baseUrl: url,
          token: token
        })
      }
    }
    return list
  }

  function hasConfiguredSource(list) {
    var rows = list || []
    for (var i = 0; i < rows.length; i++) {
      if (rows[i].baseUrl && rows[i].token)
        return true
    }
    return false
  }

  function refresh() {
    if (!configured) {
      state = "unconfigured"
      message = "Add a Coolify instance in settings."
      running = []
      recent = []
      failures = []
      warnings = []
      resetDeploymentNotifications()
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
      "COOLIFY_SOURCES": JSON.stringify(sourcesConfig),
      "COOLIFY_HISTORY_TAKE": "8",
      "COOLIFY_APP_LIMIT": "12"
    }
    fetchProcess.command = [helperPath()]
    fetchProcess.running = true
  }

  function isRateLimited(src) {
    var stateName = String((src && src.state) || "")
    var text = String((src && src.message) || "")
    return stateName === "rate-limited" || text.indexOf("rate-limited") !== -1 || text.indexOf("HTTP 429") !== -1
  }

  function flattenField(rows, key) {
    var out = []
    var list = rows || []
    for (var i = 0; i < list.length; i++) {
      var items = list[i][key] || []
      for (var j = 0; j < items.length; j++)
        out.push(items[j])
    }
    return out
  }

  function keepPreviousOnRateLimit(prev, next) {
    var prevById = {}
    var i
    for (i = 0; i < (prev || []).length; i++)
      prevById[String(prev[i].id || "")] = prev[i]
    var out = []
    for (i = 0; i < (next || []).length; i++) {
      var src = next[i]
      var old = prevById[String(src.id || "")]
      var hasOld = old && ((old.recent || []).length > 0 || (old.running || []).length > 0)
      if (isRateLimited(src) && hasOld) {
        var warnings = []
        var w
        for (w = 0; w < (old.warnings || []).length; w++)
          warnings.push(old.warnings[w])
        warnings.push(String(src.message || "Coolify rate-limited this instance."))
        out.push({
          id: old.id,
          name: old.name,
          baseUrl: old.baseUrl,
          state: "ready",
          message: src.message,
          running: old.running || [],
          recent: old.recent || [],
          failures: old.failures || [],
          warnings: warnings
        })
      } else {
        out.push(src)
      }
    }
    return out
  }

  function apply(raw) {
    try {
      var data = JSON.parse(String(raw || ""))
      var nextSources = Array.isArray(data.sources) ? data.sources : []
      sources = keepPreviousOnRateLimit(sources, nextSources)
      updateDeploymentNotifications(sources)
      running = flattenField(sources, "running")
      recent = flattenField(sources, "recent")
      failures = flattenField(sources, "failures")
      warnings = flattenField(sources, "warnings")
      source = data.source || {}
      fetchedAt = String(data.fetchedAt || "")
      var anyReady = false
      var i
      for (i = 0; i < sources.length; i++) {
        if (String(sources[i].state || "") === "ready")
          anyReady = true
      }
      if (anyReady)
        state = "ready"
      else
        state = String(data.state || "error")
      message = String(data.message || "")
      for (i = 0; i < sources.length; i++) {
        if (isRateLimited(sources[i]) || (String(sources[i].message || "").indexOf("rate-limited") !== -1)) {
          message = String(sources[i].message || message)
          break
        }
      }
    } catch (error) {
      state = "error"
      message = "Coolify returned an unreadable response."
      warnings = [String(error)]
      resetDeploymentNotifications()
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
        root.resetDeploymentNotifications()
      }
      if (root.refreshQueued) {
        root.refreshQueued = false
        if (root.state !== "rate-limited")
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
