import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Io
import Quickshell.Wayland
import Quickshell.Hyprland
import qs.Commons
import qs.Commons as Commons
import qs.Ui
import "SidebarModel.js" as SidebarModel

// Left sidebar: monitor selector, the workspace list, and the progress panel of
// the focused workspace. Content comes from ~/.config/workspaces/sidebar/
// workspaceN.json (written by wsbar); the sidebar's own UI state lives next to
// it in _sidebar.json, which only this plugin writes. _sessions.json, also
// written by wsbar (`wsbar connect`), says which workspaces have a Claude Code
// session; the plugin only reads it.
//
// The shell's IPC can call any function on a plugin's root item, so this
// controller is not the root: Sidebar.qml wraps it and exposes only toggle,
// show, hide and moveTo.
Item {
  id: root

  property string dataDir: Quickshell.env("HOME") + "/.config/workspaces/sidebar"
  readonly property string wsbarPath: String(Qt.resolvedUrl("bin/wsbar")).replace(/^file:\/\//, "")

  // Nothing renders until the directory exists and _sidebar.json was read,
  // so a hidden sidebar never flashes on at startup.
  property bool dirReady: false
  property bool stateLoaded: false
  readonly property bool ready: dirReady && stateLoaded

  property var uiState: SidebarModel.normalizeSidebarState("")
  // {"5": {session, project, since, active}}; {} while there is no file.
  property var sessions: ({})
  // Live width while the edge is being dragged; -1 otherwise.
  property int dragWidth: -1
  readonly property int panelWidth: dragWidth > 0 ? dragWidth : uiState.width

  // Workspace whose title is being edited inline; 0 when none.
  property int editingWs: 0
  property bool focusPrimed: false

  // Screen the saved monitor names, or a fallback latched from the focused
  // monitor while the saved one is absent. The fallback is not persisted, so
  // the sidebar returns to its monitor when it reconnects.
  property string fallbackMonitor: ""
  readonly property var targetScreen: {
    var screens = Quickshell.screens
    var wanted = [uiState.monitor, fallbackMonitor]
    for (var w = 0; w < wanted.length; w++) {
      if (!wanted[w]) continue
      for (var i = 0; i < screens.length; i++)
        if (screens[i].name === wanted[w]) return screens[i]
    }
    return null
  }

  property string today: Qt.formatDate(new Date(), "yyyy-MM-dd")

  // The sidebar is a view of the monitor it lives on: that monitor's workspaces,
  // and the progress of the one it is showing, wherever the focus is.
  readonly property var monitor: targetScreen ? Hyprland.monitorFor(targetScreen) : Hyprland.focusedMonitor
  readonly property string monitorName: monitor ? monitor.name : ""
  readonly property int activeWs: monitor && monitor.activeWorkspace ? monitor.activeWorkspace.id : 0
  // Connector -> block, from the file Hyprland keeps them in; {} on an Omarchy
  // from before per-monitor workspaces.
  property var monitorBlocks: ({})
  readonly property int block: SidebarModel.monitorBlock(monitorBlocks, monitorName, activeWs)
  readonly property var guestIds: {
    var values = Hyprland.workspaces.values
    var list = []
    for (var i = 0; i < values.length; i++)
      list.push({ id: values[i].id, monitor: values[i].monitor ? values[i].monitor.name : "" })
    return SidebarModel.guestWorkspaceIds(block, monitorName, list)
  }
  readonly property var workspaceFile: SidebarModel.isWorkspaceId(activeWs) ? fileFor(activeWs) : null

  function fileFor(ws) {
    var files = workspaceFiles.instances
    for (var i = 0; i < files.length; i++)
      if (files[i] && files[i].ws === ws) return files[i]
    return null
  }

  function sessionFor(ws) {
    var link = sessions[String(ws)]
    return link ? link : null
  }

  function dismissedFor(ws) {
    var list = uiState.dismissed[String(ws)]
    return Array.isArray(list) ? list : []
  }

  function screenNamed(name) {
    var screens = Quickshell.screens
    for (var i = 0; i < screens.length; i++)
      if (screens[i].name === name) return screens[i]
    return null
  }

  function refreshFallback() {
    if (screenNamed(uiState.monitor)) return
    if (fallbackMonitor && screenNamed(fallbackMonitor)) return
    var focused = Hyprland.focusedMonitor ? Hyprland.focusedMonitor.name : ""
    if (focused && screenNamed(focused)) fallbackMonitor = focused
    else fallbackMonitor = Quickshell.screens.length > 0 ? Quickshell.screens[0].name : ""
  }

  // Writing while the first load is in flight replaces the file and the load
  // never reports back, so nothing is written before _sidebar.json was read.
  function saveState(next) {
    if (!stateLoaded) return
    uiState = next
    stateFile.setText(SidebarModel.serializeSidebarState(next))
  }

  // IPC calls that arrive before the state is loaded (a keybind right after a
  // shell restart) run in order once it is.
  property var pendingCalls: []

  function whenLoaded(call) {
    if (stateLoaded) return call()
    pendingCalls = pendingCalls.concat([call])
    return "queued"
  }

  function finishLoad() {
    refreshFallback()
    stateLoaded = true
    var calls = pendingCalls
    pendingCalls = []
    for (var i = 0; i < calls.length; i++) calls[i]()
  }

  function withState(changes) {
    var next = SidebarModel.normalizeSidebarState(SidebarModel.serializeSidebarState(uiState))
    for (var key in changes) next[key] = changes[key]
    return next
  }

  function setVisible(value) {
    if (uiState.visible !== value) saveState(withState({ visible: value }))
    if (!value) cancelEdit()
    return value ? "visible" : "hidden"
  }

  function commitWidth(width) {
    var clamped = SidebarModel.clampWidth(width)
    if (clamped !== uiState.width) saveState(withState({ width: clamped }))
  }

  function dismissNotice(ws, noticeId) {
    var file = fileFor(ws)
    saveState(SidebarModel.dismiss(uiState, ws, noticeId, SidebarModel.noticeIds(file ? file.config : null)))
  }

  function beginEdit(ws) {
    focusPrimed = false
    editingWs = ws
    focusPrimeTimer.restart()
  }

  function commitTitle(ws, title) {
    if (editingWs === ws) editingWs = 0
    saveState(SidebarModel.setTitle(uiState, ws, title))
  }

  function cancelEdit() {
    editingWs = 0
  }

  function focusWorkspace(ws) {
    var perMonitor = Object.keys(monitorBlocks).length > 0
    var expression = SidebarModel.focusExpression(Number(ws), block, monitorName, perMonitor)
    if (expression) Util.execDetached("hyprctl dispatch " + Util.shellQuote(expression))
  }

  // Hyprland renumbers a workspace when it changes monitor or its monitor is
  // unplugged. Title and dismissed notices live here; `wsbar rekey` moves its
  // file and session link. Queued: one reconcile renumbers several in a row.
  // The title moves once wsbar has, so if it fails they all stay together.
  property var pendingRenumbers: []
  property var currentRenumber: null

  function renumber(from, to) {
    if (editingWs === from || editingWs === to) cancelEdit()
    pendingRenumbers = pendingRenumbers.concat([[from, to]])
    runNextRenumber()
  }

  function runNextRenumber() {
    if (rekeyProcess.running || currentRenumber !== null || pendingRenumbers.length === 0) return
    currentRenumber = pendingRenumbers[0]
    pendingRenumbers = pendingRenumbers.slice(1)
    rekeyProcess.command = [root.wsbarPath, "rekey", String(currentRenumber[0]), String(currentRenumber[1])]
    rekeyProcess.running = true
  }

  function finishRenumber(exitCode) {
    var done = currentRenumber
    currentRenumber = null
    if (done !== null && exitCode === 0)
      whenLoaded(function() { saveState(SidebarModel.renumberState(uiState, done[0], done[1])) })
    Qt.callLater(runNextRenumber)
  }

  // ---------------------------------------------------------------- IPC

  function toggle(arg) { return whenLoaded(function() { return setVisible(!uiState.visible) }) }
  function show(arg) { return whenLoaded(function() { return setVisible(true) }) }
  function hide(arg) { return whenLoaded(function() { return setVisible(false) }) }

  function moveTo(arg) {
    var name = String(arg || "").trim()
    if (!screenNamed(name)) return "unknown monitor: " + name
    return whenLoaded(function() {
      if (uiState.monitor !== name) saveState(withState({ monitor: name }))
      return "ok"
    })
  }

  // ---------------------------------------------------------------- state

  Process {
    id: mkdirProcess
    command: ["mkdir", "-p", "-m", "700", root.dataDir]
    running: true
    onExited: root.dirReady = true
  }

  FileView {
    id: stateFile
    path: root.dirReady ? root.dataDir + "/_sidebar.json" : ""
    watchChanges: false
    atomicWrites: true
    printErrors: false
    onLoaded: {
      root.uiState = SidebarModel.normalizeSidebarState(text())
      root.finishLoad()
    }
    onLoadFailed: root.finishLoad()
  }

  // Read-only and watched: wsbar replaces it atomically on connect/disconnect
  // and from the Claude Code hooks. A missing or broken file means no links.
  FileView {
    id: sessionsFile
    path: root.dirReady ? root.dataDir + "/_sessions.json" : ""
    watchChanges: true
    printErrors: false
    onFileChanged: reload()
    onLoaded: root.sessions = SidebarModel.normalizeSessions(text())
    onLoadFailed: root.sessions = ({})
  }

  FileView {
    path: (Quickshell.env("XDG_STATE_HOME") || Quickshell.env("HOME") + "/.local/state") + "/omarchy/monitor-workspaces"
    watchChanges: true
    printErrors: false
    onFileChanged: reload()
    onLoaded: root.monitorBlocks = SidebarModel.parseMonitorBlocks(text())
    onLoadFailed: root.monitorBlocks = ({})
  }

  // A shell restarted from inside Claude Code inherits its session id, and
  // wsbar refuses rekey for a session.
  Process {
    id: rekeyProcess
    environment: ({ CLAUDE_CODE_SESSION_ID: null })
    stderr: StdioCollector {
      onStreamFinished: if (text.trim() !== "") console.warn("workspace-sidebar:", text.trim())
    }
    onExited: function(exitCode) { root.finishRenumber(exitCode) }
  }

  Connections {
    target: Hyprland
    function onRawEvent(event) {
      var name = event ? String(event.name) : ""
      if (name === "changeworkspaceid") {
        var change = SidebarModel.parseRenumber(event.data)
        if (change) root.renumber(change.from, change.to)
      }
      // Hyprland's events don't say which monitor switched, and a workspace
      // that changes number or monitor is only learned by asking.
      var switched = name === "workspacev2" && root.monitor !== null && root.monitor.focused
      if (switched || name === "moveworkspacev2" || name === "changeworkspaceid") {
        Hyprland.refreshMonitors()
        Hyprland.refreshWorkspaces()
      }
    }
  }

  Variants {
    id: workspaceFiles
    model: SidebarModel.blockIds(root.block).concat(root.guestIds)

    WorkspaceFile {
      required property var modelData
      ws: modelData
      dir: root.dirReady ? root.dataDir : ""
    }
  }

  Connections {
    target: Quickshell
    function onScreensChanged() { root.refreshFallback() }
  }

  onUiStateChanged: refreshFallback()
  // Guest rows are rebuilt with the list, which would strand an open edit.
  onGuestIdsChanged: if (editingWs !== 0 && SidebarModel.blockOf(editingWs) !== block) cancelEdit()

  Timer {
    interval: 60 * 1000
    running: true
    repeat: true
    onTriggered: root.today = Qt.formatDate(new Date(), "yyyy-MM-dd")
  }

  // Layer-shell only grants keyboard focus on map or click; a surface that is
  // already mapped needs a brief Exclusive prime before settling on OnDemand.
  Timer {
    id: focusPrimeTimer
    interval: 75
    onTriggered: if (root.editingWs !== 0) root.focusPrimed = true
  }

  // ---------------------------------------------------------------- window

  PanelWindow {
    id: panel

    screen: root.targetScreen
    visible: root.ready && root.uiState.visible && root.targetScreen !== null && !remapGuard.remapping
    anchors {
      top: true
      bottom: true
      left: true
    }
    implicitWidth: root.panelWidth
    // The zone follows the committed width, not the live drag, so windows
    // reflow once on release instead of on every pointer move.
    exclusiveZone: root.uiState.width
    color: Commons.Color.bar.background
    surfaceFormat.opaque: false

    WlrLayershell.namespace: "workspace-sidebar"
    WlrLayershell.layer: WlrLayer.Top
    WlrLayershell.keyboardFocus: root.editingWs !== 0
      ? (root.focusPrimed ? WlrKeyboardFocus.OnDemand : WlrKeyboardFocus.Exclusive)
      : WlrKeyboardFocus.None

    ScreenMoveRemap {
      id: remapGuard
      window: panel
    }

    ColumnLayout {
      anchors.fill: parent
      anchors.rightMargin: edge.width
      spacing: 0

      MonitorSelector {
        Layout.fillWidth: true
        currentName: root.targetScreen ? root.targetScreen.name : ""
        onSelected: function(name) { root.moveTo(name) }
      }

      Separator { }

      WorkspaceList {
        Layout.fillWidth: true
        sidebar: root
      }

      Separator { }

      ProgressPanel {
        Layout.fillWidth: true
        Layout.fillHeight: true
        sidebar: root
        ws: root.activeWs
        file: root.workspaceFile
        dismissed: root.dismissedFor(root.activeWs)
        today: root.today
      }
    }

    // Right edge: a hairline divider plus a wider invisible grab area.
    Rectangle {
      anchors.top: parent.top
      anchors.bottom: parent.bottom
      anchors.right: parent.right
      width: Math.max(1, Style.normalBorderWidth)
      color: edgeArea.containsMouse || edgeArea.pressed ? Commons.Color.accent : Style.normalBorderColor
    }

    Item {
      id: edge
      anchors.top: parent.top
      anchors.bottom: parent.bottom
      anchors.right: parent.right
      width: 4

      MouseArea {
        id: edgeArea
        anchors.fill: parent
        hoverEnabled: true
        cursorShape: Qt.SizeHorCursor
        // Distance from the pointer to the window's right edge at press, so
        // the edge doesn't jump to the pointer when the drag starts.
        property real grabOffset: 0

        onPressed: function(mouse) {
          grabOffset = edge.width - mouse.x
          root.dragWidth = root.uiState.width
        }
        onPositionChanged: function(mouse) {
          if (!pressed) return
          var x = mapToItem(null, mouse.x, 0).x
          root.dragWidth = SidebarModel.clampWidth(Math.round(x + grabOffset))
        }
        onReleased: {
          var width = root.dragWidth
          root.dragWidth = -1
          if (width > 0) root.commitWidth(width)
        }
        onCanceled: root.dragWidth = -1
      }
    }
  }

  component Separator: Rectangle {
    Layout.fillWidth: true
    Layout.preferredHeight: Math.max(1, Style.normalBorderWidth)
    color: Style.normalBorderColor
  }
}
