import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import Quickshell
import Quickshell.Io
import qs.Commons
import qs.Ui

Panel {
  id: root
  moduleName: "eaedave.coolify"
  ipcTarget: "eaedave.coolify"
  manageIpc: false

  readonly property color foreground: bar ? bar.foreground : Color.foreground
  readonly property color urgent: bar ? bar.urgent : Color.urgent
  readonly property color dim: Qt.darker(foreground, 1.55)
  readonly property string fontFamily: bar ? bar.fontFamily : Style.font.family
  property bool cursorActive: false
  property int cursorIndex: 0
  property bool settingsOpen: false
  property bool pendingSettingsOpen: false
  property string editingId: ""
  property string draftName: ""
  property string draftBaseUrl: ""
  property string draftToken: ""
  property string sourceFilter: "all"
  property real wheelAccumulator: 0
  readonly property int activityPreviewCount: 8
  readonly property var refreshIntervalOptions: [
    { value: "10", label: "Every 10 seconds" },
    { value: "15", label: "Every 15 seconds" },
    { value: "30", label: "Every 30 seconds" },
    { value: "60", label: "Every minute" },
    { value: "180", label: "Every 3 minutes" }
  ]
  readonly property var linkBehaviorOptions: [
    { value: "Web app window", label: "Web app window" },
    { value: "Browser tab", label: "Browser tab" }
  ]
  readonly property var cursorTargets: buildCursorTargets()
  readonly property var selectedTarget: cursorTargets.length > 0 ? cursorTargets[Math.max(0, Math.min(cursorIndex, cursorTargets.length - 1))] : null
  readonly property var filteredRunning: filterRows(coolify.running)
  readonly property var filteredRecent: filterRows(coolify.recent)
  readonly property var filteredFailures: filterRows(coolify.failures)
  readonly property var filteredSource: sourceFilter === "all" ? null : sourceById(sourceFilter)
  readonly property bool showSourceName: coolify.sourcesConfig.length > 1 && sourceFilter === "all"

  function setting(name, fallback) {
    var value = settings ? settings[name] : undefined
    return value === undefined || value === null ? fallback : value
  }

  function copySources() {
    var list = []
    var rows = coolify.sourcesConfig
    for (var i = 0; i < rows.length; i++) {
      list.push({
        id: rows[i].id,
        name: rows[i].name,
        baseUrl: rows[i].baseUrl,
        token: rows[i].token
      })
    }
    return list
  }

  function persistSources(list) {
    var first = list.length > 0 ? list[0] : { name: "", baseUrl: "", token: "" }
    persistSettings({
      sources: list,
      sourceName: first.name || "",
      baseUrl: first.baseUrl || "",
      token: first.token || ""
    })
  }

  function newSourceId() {
    return "src-" + Date.now().toString(36)
  }

  function startNewSource() {
    editingId = ""
    draftName = coolify.sourcesConfig.length === 0 ? "Personal" : ""
    draftBaseUrl = ""
    draftToken = ""
  }

  function startEditSource(item) {
    editingId = String(item.id || "")
    draftName = String(item.name || "")
    draftBaseUrl = String(item.baseUrl || "")
    draftToken = String(item.token || "")
  }

  function saveSource() {
    var name = String(draftName || "").trim() || "Coolify"
    var url = String(draftBaseUrl || "").trim()
    var token = String(draftToken || "").trim()
    if (url === "" || token === "")
      return
    var list = copySources()
    var found = false
    for (var i = 0; i < list.length; i++) {
      if (list[i].id === editingId && editingId !== "") {
        list[i] = { id: list[i].id, name: name, baseUrl: url, token: token }
        found = true
        break
      }
    }
    if (!found)
      list.push({ id: newSourceId(), name: name, baseUrl: url, token: token })
    persistSources(list)
    startNewSource()
    Qt.callLater(function() { coolify.refresh() })
  }

  function removeSource(id) {
    var list = []
    var rows = copySources()
    for (var i = 0; i < rows.length; i++) {
      if (rows[i].id !== id)
        list.push(rows[i])
    }
    persistSources(list)
    if (sourceFilter === id)
      sourceFilter = "all"
    if (editingId === id)
      startNewSource()
    Qt.callLater(function() { coolify.refresh() })
  }

  function filterRows(rows) {
    var incoming = rows || []
    if (sourceFilter === "all")
      return incoming
    var out = []
    for (var i = 0; i < incoming.length; i++) {
      if (String(incoming[i].sourceId || "") === sourceFilter)
        out.push(incoming[i])
    }
    return out
  }

  function sourceById(id) {
    var rows = coolify.sources || []
    for (var i = 0; i < rows.length; i++) {
      if (String(rows[i].id || "") === String(id || ""))
        return rows[i]
    }
    return null
  }

  function sourceWarnings(source) {
    if (source && source.warnings && source.warnings.length)
      return source.warnings
    return []
  }

  function persistSettings(values) {
    var entry = { id: root.moduleName }
    for (var existing in root.settings)
      if (existing !== "id")
        entry[existing] = root.settings[existing]
    for (var key in values) {
      if (values[key] === undefined)
        delete entry[key]
      else
        entry[key] = values[key]
    }
    root.settings = entry
    if (root.bar && root.bar.shell && typeof root.bar.shell.updateEntryInline === "function")
      root.bar.shell.updateEntryInline(root.moduleName, entry)
  }

  function showSettings(open) {
    var next = open === true
    if (settingsOpen === next || pageFlip.running)
      return
    pendingSettingsOpen = next
    refreshIntervalDropdown.close()
    linkBehaviorDropdown.close()
    if (next) {
      if (Array.isArray(setting("sources", null)) === false && coolify.sourcesConfig.length > 0)
        persistSources(copySources())
      startNewSource()
    }
    pageFlip.restart()
  }

  function buildCursorTargets() {
    var targets = []
    function add(kind, rows) {
      for (var i = 0; i < rows.length; i++)
        targets.push({
          key: kind + ":" + String(rows[i].id || i),
          kind: kind,
          row: rows[i]
        })
    }
    add("running", filteredRunning)
    add("recent", filteredRecent)
    add("failure", filteredFailures)
    return targets
  }

  function ensureCursor() {
    if (cursorTargets.length === 0) {
      cursorIndex = 0
      return
    }
    cursorIndex = Math.max(0, Math.min(cursorIndex, cursorTargets.length - 1))
  }

  function moveCursor(delta) {
    cursorActive = true
    if (cursorTargets.length === 0)
      return
    cursorIndex = Math.max(0, Math.min(cursorTargets.length - 1, cursorIndex + delta))
  }

  function activateCursor() {
    if (!selectedTarget)
      return
    openUrl(selectedTarget.row.url)
  }

  function openUrl(url) {
    var value = String(url || "").trim()
    if (!/^https?:\/\//i.test(value))
      return
    if (coolify.linkBehavior === "Browser tab")
      Quickshell.execDetached(["omarchy-launch-browser", value])
    else
      Quickshell.execDetached(["omarchy-launch-webapp", value])
    close()
  }

  function relativeTime(value) {
    var then = new Date(String(value || "")).getTime()
    if (!isFinite(then))
      return ""
    var seconds = Math.max(0, Math.floor((Date.now() - then) / 1000))
    if (seconds < 60)
      return "just now"
    if (seconds < 3600)
      return Math.floor(seconds / 60) + "m ago"
    if (seconds < 86400)
      return Math.floor(seconds / 3600) + "h ago"
    return Math.floor(seconds / 86400) + "d ago"
  }

  function statusGlyph(kind) {
    if (kind === "running")
      return "󰑐"
    if (kind === "queued")
      return "󰥔"
    if (kind === "success")
      return "󰄬"
    if (kind === "failed")
      return "󰅙"
    if (kind === "cancelled")
      return "󰜺"
    return "󰋼"
  }

  function statusColor(kind) {
    if (kind === "failed")
      return root.urgent
    if (kind === "running" || kind === "queued")
      return root.foreground
    return root.dim
  }

  function applyPanelWheel(event) {
    if (!panelFlick)
      return false
    var maxY = Math.max(0, panelFlick.contentHeight - panelFlick.height)
    if (maxY <= 0)
      return false
    var pixel = event.pixelDelta.y
    var angle = event.angleDelta.y
    var wheel = Util.wheelSteps(root.wheelAccumulator, angle)
    root.wheelAccumulator = wheel.remainder
    if (wheel.steps !== 0) {
      panelFlick.contentY = Math.max(0, Math.min(maxY, panelFlick.contentY - wheel.steps * Style.space(80)))
      return true
    }
    if (pixel !== 0 && Math.abs(pixel) > Math.abs(angle) / 8) {
      root.wheelAccumulator = 0
      panelFlick.contentY = Math.max(0, Math.min(maxY, panelFlick.contentY - pixel * 3))
      return true
    }
    return angle !== 0 || pixel !== 0
  }

  implicitWidth: button.implicitWidth
  implicitHeight: button.implicitHeight

  onOpenedChanged: {
    if (!opened) {
      pageFlip.stop()
      settingsOpen = false
      pendingSettingsOpen = false
      cardRotation.angle = 0
    }
    if (opened) {
      cursorActive = false
      cursorIndex = 0
      if (panelFlick)
        panelFlick.contentY = 0
      if (!coolify.configured)
        showSettings(true)
      else
        coolify.refresh()
      Qt.callLater(function() { keyCatcher.forceActiveFocus() })
    }
  }
  onCursorTargetsChanged: ensureCursor()

  Service {
    id: coolify
    settings: root.settings
  }

  IpcHandler {
    target: root.ipcTarget
    function open(): void { root.open() }
    function close(): void { root.close() }
    function show(): void { root.open() }
    function hide(): void { root.close() }
    function toggle(): void { root.toggle() }
    function refresh(): string { coolify.refresh(); return "ok" }
    function status(): string { return coolify.state }
  }

  BarIconButton {
    id: button
    anchors.fill: parent
    bar: root.bar
    text: coolify.runningCount > 0 ? "" : "󰒋"
    active: coolify.alarming
    tooltipText: coolify.runningCount > 0
      ? (coolify.runningCount + (coolify.runningCount === 1 ? " deploy running" : " deploys running"))
      : "Coolify"
    iconComponent: coolify.runningCount > 0 ? runningIcon : null
    onPressed: function(buttonCode) {
      if (buttonCode === Qt.RightButton || buttonCode === Qt.MiddleButton)
        coolify.refresh()
      else
        root.toggle()
    }
  }

  Component {
    id: runningIcon
    Item {
      Text {
        anchors.centerIn: parent
        text: "󰒋"
        color: button.active && button.useActiveColor ? button.activeColor : button.foreground
        font.family: root.fontFamily
        font.pixelSize: button.fontSize
      }
      Rectangle {
        anchors.right: parent.right
        anchors.bottom: parent.bottom
        width: badgeLabel.implicitWidth + Style.space(6)
        height: badgeLabel.implicitHeight + Style.space(2)
        radius: height / 2
        color: button.activeColor
        Text {
          id: badgeLabel
          anchors.centerIn: parent
          text: coolify.runningBadge
          color: Color.popups.background
          font.family: root.fontFamily
          font.pixelSize: Math.max(8, Style.font.caption - 2)
          font.bold: true
        }
      }
    }
  }

  KeyboardPanel {
    id: panel
    anchorItem: button
    owner: root
    bar: root.bar
    open: root.opened
    focusTarget: keyCatcher
    contentWidth: panel.fittedContentWidth(Style.space(400))
    contentHeight: panel.fittedContentHeight(root.settingsOpen
      ? settingsHeader.implicitHeight + settingsContent.implicitHeight + Style.space(24)
      : content.implicitHeight, Style.space(620))

    PanelKeyCatcher {
      id: keyCatcher
      anchors.fill: parent
      blocked: root.settingsOpen
      onMoveRequested: function(dx, dy) {
        if (root.settingsOpen)
          return
        if (dy !== 0)
          root.moveCursor(dy)
      }
      onActivateRequested: if (!root.settingsOpen) root.activateCursor()
      onCloseRequested: if (root.settingsOpen) root.showSettings(false); else root.close()
      onTextKey: function(text) {
        if (root.settingsOpen)
          return
        if (text === "r" || text === "R")
          coolify.refresh()
      }

      transform: Rotation {
        id: cardRotation
        origin.x: keyCatcher.width / 2
        origin.y: keyCatcher.height / 2
        axis.x: 0
        axis.y: 1
        axis.z: 0
      }

      SequentialAnimation {
        id: pageFlip
        NumberAnimation { target: cardRotation; property: "angle"; from: 0; to: 90; duration: 130; easing.type: Easing.InQuad }
        ScriptAction {
          script: {
            root.settingsOpen = root.pendingSettingsOpen
            cardRotation.angle = -90
            if (root.settingsOpen && settingsFlick)
              settingsFlick.contentY = 0
          }
        }
        NumberAnimation { target: cardRotation; property: "angle"; from: -90; to: 0; duration: 170; easing.type: Easing.OutQuad }
        ScriptAction {
          script: Qt.callLater(function() {
            if (root.settingsOpen)
              nameField.forceActiveFocus()
            else
              keyCatcher.forceActiveFocus()
          })
        }
      }

      Flickable {
        id: panelFlick
        anchors.fill: parent
        visible: !root.settingsOpen
        contentWidth: width
        contentHeight: content.implicitHeight
        clip: true
        boundsBehavior: Flickable.StopAtBounds
        flickableDirection: Flickable.VerticalFlick
        interactive: contentHeight > height
        ScrollBar.vertical: ScrollBar { policy: ScrollBar.AsNeeded }
        WheelHandler {
          acceptedDevices: PointerDevice.Mouse | PointerDevice.TouchPad
          orientation: Qt.Vertical
          grabPermissions: PointerHandler.CanTakeOverFromAnything
          onWheel: function(event) {
            if (root.applyPanelWheel(event))
              event.accepted = true
          }
        }

        Column {
          id: content
          width: panelFlick.width
          spacing: Style.space(12)

          PanelHero {
            width: parent.width
            title: {
              if (root.sourceFilter !== "all") {
                for (var i = 0; i < coolify.sourcesConfig.length; i++)
                  if (coolify.sourcesConfig[i].id === root.sourceFilter)
                    return "Coolify · " + coolify.sourcesConfig[i].name
              }
              if (coolify.sourcesConfig.length === 1)
                return "Coolify · " + coolify.sourcesConfig[0].name
              return "Coolify"
            }
            meta: {
              if (coolify.loading)
                return "Refreshing deployments…"
              if (root.filteredSource && String(root.filteredSource.state || "") !== "ready")
                return String(root.filteredSource.message || coolify.message)
              if (coolify.state === "ready")
                return filteredRunning.length + " running · " + filteredRecent.length + " recent"
                  + (filteredFailures.length > 0 ? " · " + filteredFailures.length + " failed" : "")
              return coolify.message
            }
            foreground: root.foreground
            fontFamily: root.fontFamily
            trailingControl: Component {
              PanelActionButton {
                iconText: "󰒓"
                tooltipText: "Coolify settings"
                foreground: root.foreground
                fontFamily: root.fontFamily
                onClicked: root.showSettings(true)
              }
            }
            iconComponent: Component {
              Text {
                text: "󰒋"
                color: root.foreground
                font.family: root.fontFamily
                font.pixelSize: Style.font.display
                horizontalAlignment: Text.AlignHCenter
                verticalAlignment: Text.AlignVCenter
              }
            }
          }

          BorderSurface {
            visible: {
              if (root.filteredSource)
                return String(root.filteredSource.state || "") !== "ready" || root.sourceWarnings(root.filteredSource).length > 0
              return coolify.state !== "ready" || coolify.warnings.length > 0
            }
            width: parent.width
            implicitHeight: statusText.implicitHeight + Style.space(20)
            color: Qt.rgba(root.urgent.r, root.urgent.g, root.urgent.b, 0.10)
            borderSpec: Border.flat(Qt.rgba(root.urgent.r, root.urgent.g, root.urgent.b, 0.35), 1)
            radius: Style.cornerRadius
            Text {
              id: statusText
              anchors.left: parent.left
              anchors.right: parent.right
              anchors.verticalCenter: parent.verticalCenter
              anchors.margins: Style.space(10)
              text: {
                var source = root.filteredSource
                var state = source ? String(source.state || "") : coolify.state
                var message = source ? String(source.message || coolify.message) : coolify.message
                var warnings = source ? root.sourceWarnings(source) : coolify.warnings
                if (state !== "ready")
                  return message
                var summary = String(warnings[0] || "A Coolify request failed.")
                if (!source)
                  summary = "Partial results · " + summary
                if (warnings.length > 1)
                  summary += " · " + (warnings.length - 1) + " more"
                return summary
              }
              textFormat: Text.PlainText
              color: coolify.state === "ready" ? root.dim : root.urgent
              font.family: root.fontFamily
              font.pixelSize: Style.font.bodySmall
              wrapMode: Text.WordWrap
            }
          }

          Flow {
            visible: coolify.sourcesConfig.length > 1
            width: parent.width
            spacing: Style.space(6)
            Button {
              text: "All"
              selected: root.sourceFilter === "all"
              bordered: true
              foreground: root.foreground
              fontFamily: root.fontFamily
              fontSize: Style.font.caption
              verticalPadding: Style.spacing.controlPaddingY
              onClicked: root.sourceFilter = "all"
            }
            Repeater {
              model: coolify.sourcesConfig
              Button {
                required property var modelData
                text: modelData.name
                selected: root.sourceFilter === modelData.id
                bordered: true
                foreground: root.foreground
                fontFamily: root.fontFamily
                fontSize: Style.font.caption
                verticalPadding: Style.spacing.controlPaddingY
                onClicked: root.sourceFilter = modelData.id
              }
            }
          }

          DeploySection {
            title: "RUNNING"
            emptyText: coolify.state === "ready" ? "Nothing deploying right now." : "No running deployments loaded."
            rows: root.filteredRunning
            kind: "running"
          }

          DeploySection {
            title: "RECENT"
            emptyText: {
              if (root.filteredSource && root.sourceWarnings(root.filteredSource).length > 0)
                return String(root.filteredSource.message || root.filteredSource.warnings[0])
              return coolify.state === "ready" ? "No recent deployments yet." : "No history loaded."
            }
            rows: root.filteredRecent
            kind: "recent"
          }

          DeploySection {
            visible: root.filteredFailures.length > 0
            title: "FAILED"
            emptyText: ""
            rows: root.filteredFailures
            kind: "failure"
          }

          Text {
            visible: coolify.fetchedAt !== ""
            width: parent.width
            text: "Updated " + root.relativeTime(coolify.fetchedAt)
            color: root.dim
            font.family: root.fontFamily
            font.pixelSize: Style.font.caption
            horizontalAlignment: Text.AlignHCenter
          }
        }
      }

      ColumnLayout {
        id: settingsPage
        anchors.fill: parent
        visible: root.settingsOpen
        spacing: Style.space(12)
        Keys.priority: Keys.AfterItem
        Keys.onEscapePressed: function(event) {
          if (!coolify.configured) {
            root.close()
          } else {
            root.showSettings(false)
          }
          event.accepted = true
        }

        Column {
          id: settingsHeader
          Layout.fillWidth: true
          spacing: Style.space(12)

          Item {
            width: parent.width
            implicitHeight: Math.max(settingsBackButton.implicitHeight, settingsLabels.implicitHeight)
            PanelActionButton {
              id: settingsBackButton
              visible: coolify.configured
              anchors.left: parent.left
              anchors.verticalCenter: parent.verticalCenter
              iconText: "󰁍"
              tooltipText: "Back to deployments"
              foreground: root.foreground
              focusable: true
              fontFamily: root.fontFamily
              onClicked: root.showSettings(false)
            }
            Column {
              id: settingsLabels
              anchors.left: settingsBackButton.visible ? settingsBackButton.right : parent.left
              anchors.leftMargin: settingsBackButton.visible ? Style.space(10) : 0
              anchors.right: parent.right
              anchors.verticalCenter: parent.verticalCenter
              spacing: Style.space(3)
              Text {
                text: "COOLIFY SETTINGS"
                color: root.foreground
                font.family: root.fontFamily
                font.pixelSize: Style.font.title
                font.bold: true
              }
              Text {
                text: "Name each Coolify so you can tell them apart."
                color: root.dim
                font.family: root.fontFamily
                font.pixelSize: Style.font.caption
                wrapMode: Text.WordWrap
                width: parent.width
              }
            }
          }

          PanelSeparator { foreground: root.foreground }
        }

        Flickable {
          id: settingsFlick
          Layout.fillWidth: true
          Layout.fillHeight: true
          contentWidth: width
          contentHeight: settingsContent.implicitHeight
          clip: true
          boundsBehavior: Flickable.StopAtBounds
          flickableDirection: Flickable.VerticalFlick
          interactive: contentHeight > height
          ScrollBar.vertical: ScrollBar { policy: ScrollBar.AsNeeded }

          Column {
            id: settingsContent
            width: settingsFlick.width
            spacing: Style.space(20)

            Column {
              width: parent.width
              spacing: Style.space(6)
              Text {
                text: "INSTANCES"
                color: root.dim
                font.family: root.fontFamily
                font.pixelSize: Style.font.caption
                font.bold: true
              }
              Repeater {
                model: coolify.sourcesConfig
                Item {
                  required property var modelData
                  width: parent.width
                  implicitHeight: Math.max(instanceLabels.implicitHeight, instanceEdit.implicitHeight) + Style.space(8)
                  MouseArea {
                    anchors.fill: parent
                    cursorShape: Qt.PointingHandCursor
                    onClicked: root.startEditSource(modelData)
                  }
                  Column {
                    id: instanceLabels
                    anchors.left: parent.left
                    anchors.right: instanceEdit.left
                    anchors.rightMargin: Style.space(8)
                    anchors.verticalCenter: parent.verticalCenter
                    spacing: Style.space(2)
                    Text {
                      width: parent.width
                      text: modelData.name
                      color: root.editingId === modelData.id ? root.foreground : root.foreground
                      font.family: root.fontFamily
                      font.pixelSize: Style.font.body
                      font.bold: root.editingId === modelData.id
                      elide: Text.ElideRight
                    }
                    Text {
                      width: parent.width
                      text: modelData.baseUrl
                      color: root.dim
                      font.family: root.fontFamily
                      font.pixelSize: Style.font.caption
                      elide: Text.ElideMiddle
                    }
                  }
                  PanelActionButton {
                    id: instanceEdit
                    anchors.right: instanceDelete.left
                    anchors.rightMargin: Style.space(2)
                    anchors.verticalCenter: parent.verticalCenter
                    iconText: "󰏫"
                    tooltipText: "Edit " + modelData.name
                    foreground: root.foreground
                    fontFamily: root.fontFamily
                    onClicked: root.startEditSource(modelData)
                  }
                  PanelActionButton {
                    id: instanceDelete
                    anchors.right: parent.right
                    anchors.verticalCenter: parent.verticalCenter
                    iconText: "󰧧"
                    tooltipText: "Remove " + modelData.name
                    foreground: root.urgent
                    hoverColor: root.urgent
                    fontFamily: root.fontFamily
                    onClicked: root.removeSource(modelData.id)
                  }
                }
              }
              Text {
                visible: coolify.sourcesConfig.length === 0
                width: parent.width
                text: "None yet. Add Personal, Work, or any other Coolify."
                color: root.dim
                font.family: root.fontFamily
                font.pixelSize: Style.font.body
                wrapMode: Text.WordWrap
              }
            }

            Column {
              width: parent.width
              spacing: Style.space(6)
              Text {
                text: root.editingId === "" ? "ADD COOLIFY" : "EDIT COOLIFY"
                color: root.dim
                font.family: root.fontFamily
                font.pixelSize: Style.font.caption
                font.bold: true
              }
              TextField {
                id: nameField
                width: parent.width
                foreground: root.foreground
                placeholderText: "Name · Personal, Work…"
                text: root.draftName
                onTextChanged: root.draftName = text
              }
              TextField {
                id: urlField
                width: parent.width
                foreground: root.foreground
                placeholderText: "https://coolify.example.com"
                text: root.draftBaseUrl
                onTextChanged: root.draftBaseUrl = text
              }
              TextField {
                id: tokenField
                width: parent.width
                foreground: root.foreground
                password: true
                placeholderText: "Paste the Coolify bearer token"
                text: root.draftToken
                onTextChanged: root.draftToken = text
              }
              Text {
                width: parent.width
                text: "Keys & Tokens in Coolify, with the team selected. Read is enough. Stored in shell.json."
                color: root.dim
                font.family: root.fontFamily
                font.pixelSize: Style.font.caption
                wrapMode: Text.WordWrap
              }
              Row {
                spacing: Style.space(8)
                Button {
                  text: root.editingId === "" ? "Add instance" : "Save instance"
                  bordered: true
                  foreground: root.foreground
                  fontFamily: root.fontFamily
                  onClicked: root.saveSource()
                }
                Button {
                  visible: root.editingId !== ""
                  text: "Cancel"
                  bordered: true
                  foreground: root.foreground
                  fontFamily: root.fontFamily
                  onClicked: root.startNewSource()
                }
              }
            }

            Column {
              width: parent.width
              spacing: Style.space(6)
              Text {
                text: "REFRESH INTERVAL"
                color: root.dim
                font.family: root.fontFamily
                font.pixelSize: Style.font.caption
                font.bold: true
              }
              Dropdown {
                id: refreshIntervalDropdown
                width: parent.width
                showLabel: false
                options: root.refreshIntervalOptions
                foreground: root.foreground
                background: Color.popups.background
                accent: Color.accent
                fontFamily: root.fontFamily
                onChanged: function(value) { root.persistSettings({ refreshIntervalSec: parseInt(value, 10) }) }
                Binding on value { value: String(root.setting("refreshIntervalSec", 30)) }
              }
            }

            Column {
              width: parent.width
              spacing: Style.space(6)
              Text {
                text: "OPEN LINKS"
                color: root.dim
                font.family: root.fontFamily
                font.pixelSize: Style.font.caption
                font.bold: true
              }
              Dropdown {
                id: linkBehaviorDropdown
                width: parent.width
                showLabel: false
                options: root.linkBehaviorOptions
                foreground: root.foreground
                background: Color.popups.background
                accent: Color.accent
                fontFamily: root.fontFamily
                onChanged: function(value) { root.persistSettings({ linkBehavior: value }) }
                Binding on value { value: coolify.linkBehavior }
              }
            }

            Toggle {
              width: parent.width
              label: "Keep the bar icon unlit"
              description: "Leave the icon dim even when a deploy is running or failed."
              checked: coolify.iconAlwaysUnlit
              foreground: root.foreground
              accent: Color.accent
              fontFamily: root.fontFamily
              onClicked: root.persistSettings({ iconAlwaysUnlit: !coolify.iconAlwaysUnlit })
            }
            Toggle {
              width: parent.width
              label: "Desktop notifications"
              description: "Notify when a deploy starts, succeeds, or fails."
              checked: coolify.notificationsEnabled
              foreground: root.foreground
              accent: Color.accent
              fontFamily: root.fontFamily
              onClicked: root.persistSettings({ notificationsEnabled: !coolify.notificationsEnabled })
            }
            Toggle {
              width: parent.width
              label: "Notification sound"
              description: "Play the Coolify chime with each deployment notification."
              checked: coolify.notificationSoundEnabled
              foreground: root.foreground
              accent: Color.accent
              fontFamily: root.fontFamily
              onClicked: root.persistSettings({ notificationSoundEnabled: !coolify.notificationSoundEnabled })
            }


          }
        }
      }
    }
  }

  component DeploySection: Column {
    id: section
    property string title: ""
    property string emptyText: ""
    property var rows: []
    property string kind: ""
    width: content.width
    spacing: Style.space(6)
    visible: true

    PanelSectionHeader {
      width: parent.width
      text: section.title + "  " + section.rows.length
      foreground: root.foreground
      fontFamily: root.fontFamily
    }

    Text {
      visible: section.rows.length === 0 && section.emptyText !== ""
      width: parent.width
      text: section.emptyText
      color: root.dim
      font.family: root.fontFamily
      font.pixelSize: Style.font.body
    }

    Repeater {
      model: section.rows
      DeployRow {
        required property var modelData
        width: section.width
        deploy: modelData
        sectionKind: section.kind
      }
    }
  }

  component DeployRow: Item {
    id: row
    property var deploy: ({})
    property string sectionKind: ""
    implicitHeight: Math.max(glyph.implicitHeight, labels.implicitHeight) + Style.space(10)
    readonly property bool selected: root.cursorActive && root.selectedTarget && root.selectedTarget.key === row.sectionKind + ":" + String(row.deploy.id || "")

    Rectangle {
      anchors.fill: parent
      radius: Style.cornerRadius
      color: row.selected ? (root.bar ? Style.selectedFillFor(root.foreground, Color.accent) : "transparent") : "transparent"
    }

    MouseArea {
      anchors.fill: parent
      hoverEnabled: true
      cursorShape: Qt.PointingHandCursor
      onClicked: root.openUrl(row.deploy.url)
    }

    Text {
      id: glyph
      anchors.left: parent.left
      anchors.verticalCenter: parent.verticalCenter
      text: root.statusGlyph(row.deploy.statusKind)
      color: root.statusColor(row.deploy.statusKind)
      font.family: root.fontFamily
      font.pixelSize: Style.font.title
      width: Style.space(22)
      horizontalAlignment: Text.AlignHCenter
    }

    Column {
      id: labels
      anchors.left: glyph.right
      anchors.leftMargin: Style.space(8)
      anchors.right: parent.right
      anchors.verticalCenter: parent.verticalCenter
      spacing: Style.space(2)
      Text {
        width: parent.width
        text: String(row.deploy.applicationName || "Unknown")
        color: root.foreground
        font.family: root.fontFamily
        font.pixelSize: Style.font.body
        elide: Text.ElideRight
      }
      Text {
        width: parent.width
        text: {
          var parts = []
          if (root.showSourceName && row.deploy.sourceName)
            parts.push(String(row.deploy.sourceName))
          if (row.deploy.status)
            parts.push(String(row.deploy.status).replace(/_/g, " "))
          if (row.deploy.commit)
            parts.push(row.deploy.commit)
          var when = root.relativeTime(row.deploy.updatedAt || row.deploy.createdAt)
          if (when)
            parts.push(when)
          return parts.join(" · ")
        }
        color: root.dim
        font.family: root.fontFamily
        font.pixelSize: Style.font.caption
        elide: Text.ElideRight
      }
    }
  }
}
