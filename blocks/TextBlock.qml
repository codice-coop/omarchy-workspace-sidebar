import QtQuick
import qs.Commons
import qs.Commons as Commons
import qs.Ui
import "../SidebarModel.js" as SidebarModel

// Free-form note in basic Markdown (bold, italic, code, https links).
// The text comes from files that untrusted repo content can influence, so it
// is never handed to Text.MarkdownText (which fetches images, even from local
// devices): SidebarModel.markdownToStyled escapes it and builds a StyledText
// subset, and only https links are opened.
Item {
  id: root

  property var block: null

  readonly property string source: block ? String(block.text || "") : ""
  readonly property bool hasContent: source.trim() !== ""

  implicitHeight: body.implicitHeight

  Text {
    id: body
    width: parent.width
    textFormat: Text.StyledText
    text: SidebarModel.markdownToStyled(root.source)
    wrapMode: Text.Wrap
    color: Commons.Color.foreground
    linkColor: Commons.Color.accent
    font.family: Style.font.family
    font.pixelSize: Style.font.bodySmall
    onLinkActivated: function(link) {
      if (SidebarModel.isSafeLink(link)) Qt.openUrlExternally(link)
    }

    HoverHandler {
      id: hover
      cursorShape: body.hoveredLink !== "" ? Qt.PointingHandCursor : Qt.ArrowCursor
    }
  }

  // The label of a link is free text: show where it really goes.
  PanelToolTip {
    visible: hover.hovered && body.hoveredLink !== ""
    text: body.hoveredLink
  }
}
