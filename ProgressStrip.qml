import QtQuick
import qs.Commons
import qs.Commons as Commons
import qs.Ui

// Overall progress as a thin vertical bar on the panel's left edge, filled
// bottom-up, with a tick at the percent expected for today. The bar turns to
// the theme's warning color when progress is behind that tick.
Item {
  id: root

  // SidebarModel.paceInfo() result.
  property var pace: null
  property int barWidth: Style.space(6)

  readonly property real percent: pace ? pace.percent : 0
  readonly property bool hasExpected: pace !== null && pace.expected !== null && pace.expected !== undefined
  readonly property color fillColor: pace && pace.behind ? Commons.Color.urgent : Commons.Color.accent

  implicitWidth: Math.max(barWidth, percentLabel.implicitWidth, daysLabel.implicitWidth)

  Text {
    id: percentLabel
    anchors.top: parent.top
    anchors.left: parent.left
    textFormat: Text.PlainText
    text: Math.round(root.percent) + "%"
    color: root.fillColor
    font.family: Style.font.family
    font.pixelSize: Style.font.caption
    font.bold: true
  }

  Item {
    id: track
    anchors.top: percentLabel.bottom
    anchors.topMargin: Style.spacing.xs
    anchors.bottom: daysLabel.visible ? daysLabel.top : parent.bottom
    anchors.bottomMargin: daysLabel.visible ? Style.spacing.xs : 0
    anchors.left: parent.left
    width: root.barWidth

    Rectangle {
      anchors.fill: parent
      color: Util.alpha(Commons.Color.foreground, 0.12)
    }

    Rectangle {
      anchors.left: parent.left
      anchors.right: parent.right
      anchors.bottom: parent.bottom
      height: parent.height * Math.max(0, Math.min(100, root.percent)) / 100
      color: root.fillColor
      Behavior on height { NumberAnimation { duration: 240; easing.type: Easing.OutCubic } }
    }

    // Pace tick, slightly wider than the bar so it reads over either fill.
    Rectangle {
      visible: root.hasExpected
      x: -Style.space(2)
      width: parent.width + Style.space(4)
      height: Math.max(2, Style.space(2))
      y: Math.round(parent.height * (1 - (root.hasExpected ? root.pace.expected : 0) / 100) - height / 2)
      color: Commons.Color.foreground
    }
  }

  Text {
    id: daysLabel
    anchors.bottom: parent.bottom
    anchors.left: parent.left
    visible: root.pace !== null && root.pace.daysLabel !== ""
    textFormat: Text.PlainText
    text: root.pace ? root.pace.daysLabel : ""
    color: root.pace && root.pace.daysLeft !== null && root.pace.daysLeft < 0
      ? Commons.Color.urgent : Commons.Color.foreground
    font.family: Style.font.family
    font.pixelSize: Style.font.caption
  }

  HoverHandler {
    id: hover
  }

  PanelToolTip {
    visible: hover.hovered && text !== ""
    text: root.pace ? root.pace.tooltip : ""
  }
}
