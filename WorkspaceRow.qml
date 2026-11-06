import QtQuick
import Quickshell.Hyprland
import qs.Commons
import qs.Commons as Commons
import qs.Ui
import "SidebarModel.js" as SidebarModel

// One workspace: number, title, a mark when a Claude Code session is
// connected to it, and the count of notices not yet dismissed. Click focuses
// it; double-click edits the title (Enter saves, Esc cancels).
Item {
  id: root

  required property var sidebar
  required property int ws
  property var workspace: null
  // In the list right now; a hidden row's workspace no longer exists.
  property bool shown: true

  readonly property bool occupied: workspace !== null && workspace.toplevels.values.length > 0
  readonly property bool focused: Hyprland.focusedWorkspace !== null && Hyprland.focusedWorkspace.id === ws
  readonly property bool editing: sidebar.editingWs === ws
  readonly property var file: sidebar.fileFor(ws)
  readonly property int pending: file ? SidebarModel.pendingCount(file.config, sidebar.dismissedFor(ws)) : 0
  readonly property string title: SidebarModel.titleFor(sidebar.uiState, ws)
  // Link from _sessions.json, or null. An ended session keeps its link (a
  // resumed one picks it up again), so it shows dimmed instead of vanishing.
  readonly property var session: sidebar.sessionFor(ws)
  readonly property bool sessionActive: session !== null && session.active === true
  // The row's MouseArea takes the hover, so the mark's tooltip follows the
  // pointer position over it instead of a handler of its own.
  readonly property bool sessionHovered: {
    if (!mouse.containsMouse || !sessionMark.visible) return false
    var point = sessionMark.mapFromItem(mouse, mouse.mouseX, mouse.mouseY)
    return sessionMark.contains(point)
  }

  implicitHeight: Style.spacing.popupRowHeight

  onFocusedChanged: if (focused) flash.restart()
  // The workspace going away under an open edit ends it, keeping what was typed.
  onShownChanged: if (!shown && editing) sidebar.commitTitle(ws, editor.text)

  Rectangle {
    anchors.fill: parent
    color: root.focused ? Style.selectedAccentFill
      : mouse.containsMouse ? Style.hoverFill
      : "transparent"
    Behavior on color { ColorAnimation { duration: 120 } }
  }

  // Focus marker on the leading edge, like a selected menu row.
  Rectangle {
    anchors.left: parent.left
    anchors.top: parent.top
    anchors.bottom: parent.bottom
    width: Style.space(2)
    color: Commons.Color.accent
    visible: root.focused
  }

  Rectangle {
    id: flashOverlay
    anchors.fill: parent
    color: Commons.Color.accent
    opacity: 0

    SequentialAnimation {
      id: flash
      NumberAnimation { target: flashOverlay; property: "opacity"; from: 0; to: 0.35; duration: 200; easing.type: Easing.OutQuad }
      NumberAnimation { target: flashOverlay; property: "opacity"; to: 0; duration: 400; easing.type: Easing.InQuad }
    }
  }

  Item {
    id: content
    anchors.fill: parent
    anchors.leftMargin: Style.spacing.rowPaddingX
    anchors.rightMargin: Style.spacing.lg
    opacity: root.occupied || root.focused ? 1 : 0.5

    Text {
      id: number
      anchors.left: parent.left
      anchors.verticalCenter: parent.verticalCenter
      width: numberMetrics.advanceWidth
      textFormat: Text.PlainText
      text: String(root.ws)
      color: root.focused ? Commons.Color.accent : Commons.Color.foreground
      font.family: Style.font.family
      font.pixelSize: Style.font.body
      font.bold: true
    }

    TextMetrics {
      id: numberMetrics
      font: number.font
      text: "10"
    }

    Text {
      anchors.left: number.right
      anchors.leftMargin: Style.spacing.lg
      anchors.right: trailing.width > 0 ? trailing.left : parent.right
      anchors.rightMargin: trailing.width > 0 ? Style.spacing.md : 0
      anchors.verticalCenter: parent.verticalCenter
      visible: !root.editing
      textFormat: Text.PlainText
      text: root.title
      elide: Text.ElideRight
      color: Commons.Color.foreground
      font.family: Style.font.family
      font.pixelSize: Style.font.body
      font.bold: root.focused
    }

    TextField {
      id: editor
      anchors.left: number.right
      anchors.leftMargin: Style.spacing.md
      anchors.right: parent.right
      anchors.verticalCenter: parent.verticalCenter
      visible: root.editing
      verticalPadding: Style.spacing.xxs
      horizontalPadding: Style.spacing.sm
      selectByMouse: true

      onAccepted: root.sidebar.commitTitle(root.ws, text)
      Keys.onEscapePressed: root.sidebar.cancelEdit()

      // Focus leaving the field (the pointer wandering onto a window under
      // follow-mouse, a keybind switching workspaces) keeps what was typed,
      // as Enter would. Only a loss that lasts counts: the Exclusive to
      // OnDemand handoff can drop focus for a frame.
      onActiveFocusChanged: if (!activeFocus && root.editing) blurTimer.restart()

      Timer {
        id: blurTimer
        interval: 200
        onTriggered: if (root.editing && !editor.activeFocus) root.sidebar.commitTitle(root.ws, editor.text)
      }
    }

    Row {
      id: trailing
      anchors.right: parent.right
      anchors.verticalCenter: parent.verticalCenter
      spacing: Style.spacing.sm
      visible: !root.editing

      Text {
        id: sessionMark
        anchors.verticalCenter: parent.verticalCenter
        visible: root.session !== null
        textFormat: Text.PlainText
        // nf-md-robot
        text: "\udb81\udea9"
        color: root.sessionActive ? Commons.Color.accent : Commons.Color.muted
        font.family: Style.font.family
        font.pixelSize: Style.font.body

        PanelToolTip {
          visible: root.sessionHovered && text !== ""
          text: SidebarModel.sessionTooltip(root.session, root.sidebar.today)
        }
      }

      Rectangle {
        id: badge
        anchors.verticalCenter: parent.verticalCenter
        visible: root.pending > 0
        height: badgeText.implicitHeight + Style.spacing.xxs * 2
        width: Math.max(height, badgeText.implicitWidth + Style.spacing.sm * 2)
        radius: height / 2
        color: Commons.Color.accent

        Text {
          id: badgeText
          anchors.centerIn: parent
          textFormat: Text.PlainText
          text: String(root.pending)
          color: Commons.Color.background
          font.family: Style.font.family
          font.pixelSize: Style.font.caption
          font.bold: true
        }
      }
    }
  }

  onEditingChanged: {
    if (editing) {
      editor.text = root.title
      Qt.callLater(function() {
        editor.forceActiveFocus()
        editor.selectAll()
      })
    }
  }

  MouseArea {
    id: mouse
    anchors.fill: parent
    enabled: !root.editing
    hoverEnabled: true
    cursorShape: Qt.PointingHandCursor
    // The focus dispatch waits out the double-click window: a rename must not
    // first switch workspaces, or the newly focused window takes the keyboard
    // from the title field.
    onClicked: clickTimer.restart()
    onDoubleClicked: {
      clickTimer.stop()
      root.sidebar.beginEdit(root.ws)
    }
  }

  Timer {
    id: clickTimer
    interval: Qt.styleHints.mouseDoubleClickInterval
    onTriggered: root.sidebar.focusWorkspace(root.ws)
  }
}
