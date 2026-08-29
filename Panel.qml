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
  property string draftBaseUrl: ""
  property string draftToken: ""
  property real wheelAccumulator: 0
  readonly property int activityPreviewCount: 8
  readonly property var refreshIntervalOptions: [
    { value: "15", label: "Every 15 seconds" },
    { value: "30", label: "Every 30 seconds" },
    { value: "60", label: "Every minute" },
    { value: "120", label: "Every 2 minutes" },
    { value: "300", label: "Every 5 minutes" }
  ]
  readonly property var linkBehaviorOptions: [
    { value: "Web app window", label: "Web app window" },
    { value: "Browser tab", label: "Browser tab" }
  ]
  readonly property var cursorTargets: buildCursorTargets()
  readonly property var selectedTarget: cursorTargets.length > 0 ? cursorTargets[Math.max(0, Math.min(cursorIndex, cursorTargets.length - 1))] : null

  function setting(name, fallback) {
    var value = settings ? settings[name] : undefined
    return value === undefined || value === null ? fallback : value
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
      draftBaseUrl = String(setting("baseUrl", ""))
      draftToken = String(setting("token", ""))
    }
    pageFlip.restart()
  }

  function saveSettings() {
    persistSettings({
      baseUrl: String(draftBaseUrl || "").trim(),
      token: String(draftToken || "").trim()
    })
    showSettings(false)
    Qt.callLater(function() { coolify.refresh() })
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
    add("running", coolify.running)
    add("recent", coolify.recent)
    add("failure", coolify.failures)
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
    var value = String(url || "")
    if (value === "")
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
    text: "󰒋"
    active: coolify.alarming
    onPressed: function(buttonCode) {
      if (buttonCode === Qt.RightButton || buttonCode === Qt.MiddleButton)
        coolify.refresh()
      else
        root.toggle()
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
              urlField.forceActiveFocus()
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
            title: coolify.source && coolify.source.name ? "Coolify · " + String(coolify.source.name) : "Coolify"
            meta: coolify.loading ? "Refreshing deployments…" : (coolify.state === "ready"
              ? coolify.runningCount + " running · " + coolify.recent.length + " recent"
                + (coolify.failureCount > 0 ? " · " + coolify.failureCount + " failed" : "")
              : coolify.message)
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
            visible: coolify.state !== "ready" || coolify.warnings.length > 0
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
                if (coolify.state !== "ready")
                  return coolify.message
                var summary = "Partial results · " + String(coolify.warnings[0] || "A Coolify request failed.")
                if (coolify.warnings.length > 1)
                  summary += " · " + (coolify.warnings.length - 1) + " more"
                return summary
              }
              textFormat: Text.PlainText
              color: coolify.state === "ready" ? root.dim : root.urgent
              font.family: root.fontFamily
              font.pixelSize: Style.font.bodySmall
              wrapMode: Text.WordWrap
            }
          }

          DeploySection {
            title: "RUNNING"
            emptyText: coolify.state === "ready" ? "Nothing deploying right now." : "No running deployments loaded."
            rows: coolify.running
            kind: "running"
          }

          DeploySection {
            title: "RECENT"
            emptyText: coolify.state === "ready" ? "No recent deployments yet." : "No history loaded."
            rows: coolify.recent
            kind: "recent"
          }

          DeploySection {
            visible: coolify.failures.length > 0
            title: "FAILED"
            emptyText: ""
            rows: coolify.failures
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
                text: "One instance in v1. More Coolify sources can join this panel later."
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
                text: "COOLIFY URL"
                color: root.dim
                font.family: root.fontFamily
                font.pixelSize: Style.font.caption
                font.bold: true
              }
              TextField {
                id: urlField
                width: parent.width
                foreground: root.foreground
                placeholderText: "https://coolify.example.com"
                text: root.draftBaseUrl
                onTextChanged: root.draftBaseUrl = text
              }
            }

            Column {
              width: parent.width
              spacing: Style.space(6)
              Text {
                text: "API TOKEN"
                color: root.dim
                font.family: root.fontFamily
                font.pixelSize: Style.font.caption
                font.bold: true
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
                text: "Keys & Tokens in Coolify. Read is enough. Stored in shell.json for v1."
                color: root.dim
                font.family: root.fontFamily
                font.pixelSize: Style.font.caption
                wrapMode: Text.WordWrap
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

            Button {
              width: parent.width
              text: "Save and refresh"
              foreground: root.foreground
              fontFamily: root.fontFamily
              onClicked: root.saveSettings()
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
