import QtQuick
import qs.Commons
import qs.Commons as Commons

// Free-form note in basic Markdown (bold, italic, code, links).
Item {
  id: root

  property var block: null

  readonly property string source: block ? String(block.text || "") : ""
  readonly property bool hasContent: source.trim() !== ""

  // MarkdownText paints links in the platform's link blue and ignores
  // linkColor, but it does pass inline HTML through: wrap each [label](url)
  // in an anchor whose span carries the theme accent.
  readonly property string rendered: source.replace(/\[([^\]]+)\]\(([^)\s]+)\)/g, function(match, label, url) {
    return "<a href=\"" + url.replace(/"/g, "%22") + "\"><span style=\"color:" + String(Commons.Color.accent) + "\">"
      + label + "</span></a>"
  })

  implicitHeight: body.implicitHeight

  Text {
    id: body
    width: parent.width
    textFormat: Text.MarkdownText
    text: root.rendered
    wrapMode: Text.Wrap
    color: Commons.Color.foreground
    font.family: Style.font.family
    font.pixelSize: Style.font.bodySmall
    onLinkActivated: function(link) { Qt.openUrlExternally(link) }

    HoverHandler {
      cursorShape: body.hoveredLink !== "" ? Qt.PointingHandCursor : Qt.ArrowCursor
    }
  }
}
