import QtQuick
import qs.Commons
import qs.Commons as Commons

// Milestones in order: done ones muted with a check, the current one in the
// accent color, pending ones plain.
Item {
  id: root

  property var block: null

  readonly property var items: block && Array.isArray(block.items) ? block.items : []
  readonly property bool hasContent: items.length > 0

  implicitHeight: column.implicitHeight

  Column {
    id: column
    width: parent.width
    spacing: Style.spacing.xs

    Caption { text: "Hitos" }

    Repeater {
      model: root.items

      Item {
        id: milestone
        required property var modelData
        readonly property string status: modelData.status
        readonly property color tone: status === "current" ? Commons.Color.accent : Commons.Color.foreground

        width: column.width
        implicitHeight: Math.max(label.implicitHeight, marker.implicitHeight)
        opacity: status === "done" ? 0.5 : 1

        Text {
          id: marker
          anchors.left: parent.left
          anchors.top: parent.top
          width: markerMetrics.advanceWidth
          textFormat: Text.PlainText
          text: milestone.status === "done" ? "✓" : (milestone.status === "current" ? "●" : "○")
          color: milestone.tone
          font.family: Style.font.family
          font.pixelSize: Style.font.bodySmall
        }

        TextMetrics {
          id: markerMetrics
          font: marker.font
          text: "●"
        }

        Text {
          id: label
          anchors.left: marker.right
          anchors.leftMargin: Style.spacing.md
          anchors.right: date.visible ? date.left : parent.right
          anchors.rightMargin: date.visible ? Style.spacing.md : 0
          anchors.top: parent.top
          textFormat: Text.PlainText
          text: milestone.modelData.label
          wrapMode: Text.Wrap
          color: milestone.tone
          font.family: Style.font.family
          font.pixelSize: Style.font.bodySmall
          font.bold: milestone.status === "current"
          font.strikeout: milestone.status === "done"
        }

        Text {
          id: date
          anchors.right: parent.right
          anchors.top: parent.top
          visible: text !== ""
          textFormat: Text.PlainText
          // YYYY-MM-DD shown as MM-DD; the year is noise at this scale.
          text: milestone.modelData.date ? String(milestone.modelData.date).slice(5) : ""
          color: milestone.tone
          opacity: 0.6
          font.family: Style.font.family
          font.pixelSize: Style.font.caption
        }
      }
    }
  }
}
