import QtQuick
import Quickshell
import qs.Commons
import qs.Ui

// One button per connected monitor; the one hosting the sidebar is selected.
Item {
  id: root

  property string currentName: ""
  signal selected(string name)

  implicitHeight: flow.implicitHeight + Style.spacing.md * 2

  Flow {
    id: flow
    anchors.fill: parent
    anchors.margins: Style.spacing.md
    spacing: Style.spacing.xs

    Repeater {
      model: Quickshell.screens

      Button {
        required property var modelData

        text: modelData.name
        selected: modelData.name === root.currentName
        fontSize: Style.font.caption
        horizontalPadding: Style.spacing.md
        verticalPadding: Style.spacing.xxs
        tooltipText: modelData.model ? modelData.model : ""
        onClicked: root.selected(modelData.name)
      }
    }
  }
}
