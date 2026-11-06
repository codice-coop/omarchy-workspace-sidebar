import QtQuick
import qs.Commons
import qs.Commons as Commons

// A secondary measure: label and percent over a thin horizontal bar.
Item {
  id: root

  property var block: null

  readonly property string label: block ? String(block.label || "") : ""
  readonly property real percent: block && isFinite(block.percent) ? Math.max(0, Math.min(100, block.percent)) : 0
  readonly property bool hasContent: block !== null

  implicitHeight: header.implicitHeight + Style.spacing.xs + bar.height

  Item {
    id: header
    width: parent.width
    implicitHeight: Math.max(labelText.implicitHeight, percentText.implicitHeight)

    Text {
      id: labelText
      anchors.left: parent.left
      anchors.right: percentText.left
      anchors.rightMargin: Style.spacing.md
      textFormat: Text.PlainText
      text: root.label
      elide: Text.ElideRight
      color: Commons.Color.foreground
      font.family: Style.font.family
      font.pixelSize: Style.font.bodySmall
    }

    Text {
      id: percentText
      anchors.right: parent.right
      textFormat: Text.PlainText
      text: Math.round(root.percent) + "%"
      color: Commons.Color.foreground
      opacity: 0.7
      font.family: Style.font.family
      font.pixelSize: Style.font.caption
      font.bold: true
    }
  }

  Rectangle {
    id: bar
    anchors.top: header.bottom
    anchors.topMargin: Style.spacing.xs
    width: parent.width
    height: Style.space(4)
    color: Util.alpha(Commons.Color.foreground, 0.12)

    Rectangle {
      anchors.left: parent.left
      anchors.top: parent.top
      anchors.bottom: parent.bottom
      width: parent.width * root.percent / 100
      color: Commons.Color.accent
      Behavior on width { NumberAnimation { duration: 240; easing.type: Easing.OutCubic } }
    }
  }
}
