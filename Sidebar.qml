import QtQuick

// Plugin entry point. The shell's IPC (`omarchy-shell shell call io.github.codice-coop.workspace-sidebar
// <method> <arg>`) can call any function on this root item, so it holds only
// the public surface — toggle, show, hide, moveTo <monitor> — and delegates to
// SidebarController, whose internals stay out of reach.
Item {
  id: root

  function toggle(arg) { return controller.toggle(arg) }
  function show(arg) { return controller.show(arg) }
  function hide(arg) { return controller.hide(arg) }
  function moveTo(arg) { return controller.moveTo(arg) }

  SidebarController {
    id: controller
  }
}
