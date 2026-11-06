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
// it in _sidebar.json, which only this plugin writes.
//
// The shell's IPC can call any function on a plugin's root item, so this
// controller is not the root: Sidebar.qml wraps it and exposes only toggle,
// show, hide and moveTo.
Item {
  id: root

  property string dataDir: Quickshell.env("HOME") + "/.config/workspaces/sidebar"

  // Nothing renders until the directory exists and _sidebar.json was read,
  // so a hidden sidebar never flashes on at startup.
  property bool dirReady: false
  property bool stateLoaded: false
  readonly property bool ready: dirReady && stateLoaded

  property var uiState: SidebarModel.normalizeSidebarState("")
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

  readonly property int focusedWs: Hyprland.focusedWorkspace ? Hyprland.focusedWorkspace.id : 0
  readonly property var workspaceFile: focusedWs >= 1 && focusedWs <= 10 ? fileFor(focusedWs) : null

  function fileFor(ws) {
    var files = workspaceFiles.instances
    for (var i = 0; i < files.length; i++)
      if (files[i] && files[i].ws === ws) return files[i]
    return null
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
    saveState(SidebarModel.dismiss(uiState, ws, noticeId))
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
    // The id is spliced into a Lua dispatch string: only a plain 1..10 integer.
    ws = Number(ws)
    if (!Number.isInteger(ws) || ws < 1 || ws > 10) return
    Util.execDetached("hyprctl dispatch " + Util.shellQuote("hl.dsp.focus({ workspace = \"" + ws + "\" })"))
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

  Variants {
    id: workspaceFiles
    model: [1, 2, 3, 4, 5, 6, 7, 8, 9, 10]

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

    WlrLayershell.namespace: "matis-sidebar"
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
        ws: root.focusedWs
        file: root.workspaceFile
        dismissed: root.dismissedFor(root.focusedWs)
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
