import QtQuick
import qs.Commons
import qs.Commons as Commons
import "../SidebarModel.js" as SidebarModel

// Notices left by Claude for review. Each one shows until dismissed; dismissed
// ids live in _sidebar.json, so the file itself is never rewritten by the UI.
Item {
  id: root

  property var block: null
  property var dismissed: []
  property string today: ""

  signal dismiss(string noticeId)

  readonly property var items: block ? SidebarModel.pendingNotices({ blocks: [block] }, dismissed) : []
  readonly property bool hasContent: items.length > 0

  function levelColor(level) {
    if (level === "error") return Commons.Color.urgent
    if (level === "warn") return Commons.Color.accent
    return Util.alpha(Commons.Color.foreground, 0.5)
  }

  // "2026-11-06T10:12" reads as "10:12" today and as "11-06" otherwise.
  function shortTime(at) {
    var value = String(at || "")
    if (value === "") return ""
    var parts = value.split("T")
    if (parts.length > 1 && parts[0] === root.today) return parts[1].slice(0, 5)
    return parts[0].length >= 10 ? parts[0].slice(5, 10) : parts[0]
  }

  implicitHeight: column.implicitHeight

  Column {
    id: column
    width: parent.width
    spacing: Style.spacing.sm

    Repeater {
      model: root.items

      Rectangle {
        id: notice
        required property var modelData

        width: column.width
        implicitHeight: Math.max(body.implicitHeight, closeButton.height) + Style.spacing.md * 2
        height: implicitHeight
        color: Util.alpha(root.levelColor(modelData.level), 0.08)

        Rectangle {
          anchors.left: parent.left
          anchors.top: parent.top
          anchors.bottom: parent.bottom
          width: Style.space(3)
          color: root.levelColor(notice.modelData.level)
        }

        Column {
          id: body
          anchors.left: parent.left
          anchors.leftMargin: Style.space(3) + Style.spacing.md
          anchors.right: closeButton.left
          anchors.rightMargin: Style.spacing.sm
          anchors.verticalCenter: parent.verticalCenter
          spacing: Style.spacing.xxs

          Text {
            width: parent.width
            textFormat: Text.PlainText
            text: notice.modelData.text
            wrapMode: Text.Wrap
            color: Commons.Color.foreground
            font.family: Style.font.family
            font.pixelSize: Style.font.bodySmall
          }

          Text {
            visible: text !== ""
            textFormat: Text.PlainText
            text: root.shortTime(notice.modelData.at)
            color: Commons.Color.foreground
            opacity: 0.45
            font.family: Style.font.family
            font.pixelSize: Style.font.caption
          }
        }

        Rectangle {
          id: closeButton
          anchors.right: parent.right
          anchors.top: parent.top
          anchors.margins: Style.spacing.xxs
          width: closeGlyph.implicitHeight + Style.spacing.xs * 2
          height: width
          color: closeArea.containsMouse ? Style.hoverFill : "transparent"

          Text {
            id: closeGlyph
            anchors.centerIn: parent
            textFormat: Text.PlainText
            text: "×"
            color: Commons.Color.foreground
            opacity: closeArea.containsMouse ? 1 : 0.55
            font.family: Style.font.family
            font.pixelSize: Style.font.body
          }

          MouseArea {
            id: closeArea
            anchors.fill: parent
            hoverEnabled: true
            cursorShape: Qt.PointingHandCursor
            onClicked: root.dismiss(notice.modelData.id)
          }
        }
      }
    }
  }
}
