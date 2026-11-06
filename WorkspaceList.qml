import QtQuick
import Quickshell.Hyprland
import qs.Commons
import "SidebarModel.js" as SidebarModel

// Panel 1: the same workspaces the bar shows (1-5 always, plus any existing
// one up to 10), one row each.
Item {
  id: root

  required property var sidebar

  function workspaceById(id) {
    var values = Hyprland.workspaces.values
    for (var i = 0; i < values.length; i++)
      if (values[i].id === id) return values[i]
    return null
  }

  function workspaceIds() {
    var values = Hyprland.workspaces.values
    var ids = []
    for (var i = 0; i < values.length; i++) ids.push(values[i].id)
    return SidebarModel.workspaceIds(ids)
  }

  readonly property var ids: workspaceIds()

  // One row per possible workspace, shown when it is in the list. Rows are
  // never rebuilt when Hyprland creates or destroys a workspace, so a flash
  // only follows a real focus change and an open title edit survives.
  readonly property var allIds: [1, 2, 3, 4, 5, 6, 7, 8, 9, 10]

  implicitHeight: column.implicitHeight + Style.spacing.sm * 2

  Column {
    id: column
    anchors.fill: parent
    anchors.topMargin: Style.spacing.sm
    anchors.bottomMargin: Style.spacing.sm

    Repeater {
      model: root.allIds

      WorkspaceRow {
        required property int modelData

        width: column.width
        visible: shown
        sidebar: root.sidebar
        ws: modelData
        shown: root.ids.indexOf(modelData) >= 0
        workspace: shown ? root.workspaceById(modelData) : null
      }
    }
  }
}
