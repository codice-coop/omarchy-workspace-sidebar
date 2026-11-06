import QtQuick
import Quickshell.Io
import "SidebarModel.js" as SidebarModel

// One workspaceN.json, watched on disk. A file that stops parsing keeps the
// last valid config and only raises `error`, so a half-written or bad edit
// never blanks the panel; a file that disappears does clear it.
QtObject {
  id: root

  required property int ws
  property string dir: ""

  property var config: null
  property string error: ""
  // Bumped on every successful load, even when the content is unchanged, so
  // the panel can re-apply the file's `scroll` on each write.
  property int revision: 0

  function parse(text) {
    var result = SidebarModel.normalizeWorkspaceConfig(text)
    if (result.ok) {
      root.config = result.config
      root.error = ""
      root.revision++
    } else {
      root.error = result.error
    }
  }

  property FileView view: FileView {
    path: root.dir ? root.dir + "/workspace" + root.ws + ".json" : ""
    watchChanges: true
    printErrors: false
    onFileChanged: reload()
    onLoaded: root.parse(text())
    onLoadFailed: function(error) {
      root.config = null
      root.error = error === FileViewError.FileNotFound ? "" : "No se pudo leer workspace" + root.ws + ".json"
      root.revision++
    }
  }
}
