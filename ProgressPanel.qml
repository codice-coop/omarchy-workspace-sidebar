import QtQuick
import qs.Commons
import qs.Commons as Commons
import qs.Ui
import "SidebarModel.js" as SidebarModel
import "blocks"

// Panel 2: the focused workspace's workspaceN.json. The progress strip stays
// fixed on the left; blocks scroll beside it in file order. Each load of the
// file re-applies its `scroll`; manual scrolling holds until the next one.
Item {
  id: root

  required property var sidebar
  property int ws: 0
  // WorkspaceFile for `ws`, or null for workspaces the sidebar doesn't track.
  property var file: null
  property var dismissed: []
  property string today: ""

  readonly property var config: file ? file.config : null
  readonly property string error: file ? file.error : ""
  readonly property var progress: config ? config.progress : null
  readonly property var pace: progress ? SidebarModel.paceInfo(progress, today) : null
  readonly property var blocks: config ? config.blocks : []
  readonly property bool empty: !config

  // Scroll is (re)applied once layout settles after a load or a workspace
  // switch; content height changes in between keep pushing it back.
  property bool scrollPending: true
  onWsChanged: scrollPending = true
  Connections {
    target: root.file
    function onRevisionChanged() { root.scrollPending = true }
  }
  onScrollPendingChanged: if (scrollPending) scrollTimer.restart()

  function applyScroll() {
    if (!config) {
      scrollPending = false
      return
    }
    var offsets = {}
    for (var i = 0; i < blockRepeater.count; i++) {
      var item = blockRepeater.itemAt(i)
      if (item && item.blockId) offsets[item.blockId] = blockColumn.y + item.y
    }
    flick.contentY = SidebarModel.resolveScroll(config.scroll, offsets, flick.contentHeight, flick.height)
    scrollPending = false
  }

  Timer {
    id: scrollTimer
    interval: 50
    onTriggered: root.applyScroll()
  }

  Column {
    anchors.centerIn: parent
    width: parent.width - Style.spacing.panelPadding * 2
    visible: root.empty
    spacing: Style.spacing.xxs
    opacity: 0.55

    Repeater {
      // Two lines so the command never wraps apart from its slash.
      model: ["Sin progreso.", "Pedile a Claude: /progreso"]

      Text {
        required property string modelData
        width: parent.width
        textFormat: Text.PlainText
        text: modelData
        horizontalAlignment: Text.AlignHCenter
        wrapMode: Text.WordWrap
        color: Commons.Color.foreground
        font.family: Style.font.family
        font.pixelSize: Style.font.bodySmall
      }
    }
  }

  ProgressStrip {
    id: strip
    anchors.top: parent.top
    anchors.bottom: parent.bottom
    anchors.left: parent.left
    anchors.topMargin: Style.spacing.lg
    anchors.bottomMargin: Style.spacing.lg
    anchors.leftMargin: Style.spacing.md
    visible: root.progress !== null
    pace: root.pace
  }

  Flickable {
    id: flick
    anchors.top: parent.top
    anchors.bottom: parent.bottom
    anchors.left: strip.visible ? strip.right : parent.left
    anchors.right: parent.right
    anchors.leftMargin: strip.visible ? Style.spacing.lg : Style.spacing.md
    visible: !root.empty
    clip: true
    contentWidth: width
    contentHeight: blockColumn.implicitHeight + Style.spacing.lg * 2
    boundsBehavior: Flickable.StopAtBounds
    onContentHeightChanged: if (root.scrollPending) scrollTimer.restart()
    onHeightChanged: if (root.scrollPending) scrollTimer.restart()

    Column {
      id: blockColumn
      x: 0
      y: Style.spacing.lg
      width: flick.width - Style.spacing.md
      spacing: Style.spacing.panelGap

      Repeater {
        id: blockRepeater
        model: root.blocks

        Loader {
          id: blockLoader
          // Read the block from root.blocks rather than modelData: the model
          // copy turns nested arrays into list wrappers Array.isArray rejects.
          required property int index
          readonly property var block: root.blocks[index]
          readonly property string blockId: block ? block.id : ""

          width: blockColumn.width
          // A notices block whose items were all dismissed takes no space.
          visible: item !== null && item.hasContent !== false
          sourceComponent: !block ? null
            : block.type === "notices" ? noticesComponent
            : block.type === "focus" ? focusComponent
            : block.type === "milestones" ? milestonesComponent
            : block.type === "text" ? textComponent
            : block.type === "progress" ? progressComponent
            : null

          Component {
            id: noticesComponent
            NoticesBlock {
              block: blockLoader.block
              dismissed: root.dismissed
              today: root.today
              onDismiss: function(noticeId) { root.sidebar.dismissNotice(root.ws, noticeId) }
            }
          }
          Component { id: focusComponent; FocusBlock { block: blockLoader.block } }
          Component { id: milestonesComponent; MilestonesBlock { block: blockLoader.block } }
          Component { id: textComponent; TextBlock { block: blockLoader.block } }
          Component { id: progressComponent; ProgressBlock { block: blockLoader.block } }
        }
      }
    }
  }

  // Thin scroll position indicator; only when the blocks overflow.
  Rectangle {
    anchors.right: flick.right
    width: Style.space(2)
    y: flick.y + flick.visibleArea.yPosition * flick.height
    height: flick.visibleArea.heightRatio * flick.height
    visible: flick.visible && flick.contentHeight > flick.height
    color: Commons.Color.foreground
    opacity: flick.moving ? 0.45 : 0.2
    Behavior on opacity { NumberAnimation { duration: 160 } }
  }

  // Bad JSON or an unknown version: the last valid content stays up and this
  // marker carries the parser's message.
  Rectangle {
    id: errorMarker
    // Bottom-right is the one corner no block or strip label uses.
    anchors.bottom: parent.bottom
    anchors.right: parent.right
    anchors.margins: Style.spacing.md
    visible: root.error !== ""
    width: Style.space(16)
    height: width
    radius: width / 2
    color: Commons.Color.urgent

    Text {
      anchors.centerIn: parent
      textFormat: Text.PlainText
      text: "!"
      color: Commons.Color.background
      font.family: Style.font.family
      font.pixelSize: Style.font.caption
      font.bold: true
    }

    HoverHandler { id: errorHover }

    PanelToolTip {
      visible: errorHover.hovered
      text: root.error
    }
  }
}
