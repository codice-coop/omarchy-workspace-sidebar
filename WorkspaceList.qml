import QtQuick
import Quickshell.Hyprland
import qs.Commons
import "SidebarModel.js" as SidebarModel

// Panel 1: the workspaces the bar of this monitor shows (the first five of its
// block, any of the rest that exist, then visitors from another block), one row
// each.
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
    return SidebarModel.ownWorkspaceIds(sidebar.block, ids)
  }

  readonly property var ids: workspaceIds()

  // One row per workspace of the block, shown when it is in the list. Rows are
  // never rebuilt when Hyprland creates or destroys a workspace, so a flash
  // only follows a real focus change and an open title edit survives.
  readonly property var allIds: SidebarModel.blockIds(sidebar.block)

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

    // A gap sets visiting workspaces apart from the monitor's own, as in the bar.
    Item {
      width: column.width
      height: Style.space(6)
      visible: root.sidebar.guestIds.length > 0
    }

    Repeater {
      model: root.sidebar.guestIds

      WorkspaceRow {
        required property int modelData

        width: column.width
        sidebar: root.sidebar
        ws: modelData
        workspace: root.workspaceById(modelData)
      }
    }
  }
}
