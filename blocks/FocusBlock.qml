import QtQuick
import qs.Commons
import qs.Commons as Commons

// What the session is on now, and what comes after.
Item {
  id: root

  property var block: null

  readonly property string now: block ? String(block.now || "") : ""
  readonly property var next: block && Array.isArray(block.next) ? block.next : []
  readonly property bool hasContent: now !== "" || next.length > 0

  implicitHeight: column.implicitHeight

  Column {
    id: column
    width: parent.width
    spacing: Style.spacing.xs

    Caption {
      visible: root.now !== ""
      text: "Ahora"
    }

    Text {
      width: column.width
      visible: root.now !== ""
      textFormat: Text.PlainText
      text: root.now
      wrapMode: Text.Wrap
      color: Commons.Color.accent
      font.family: Style.font.family
      font.pixelSize: Style.font.body
      font.bold: true
    }

    Item {
      width: 1
      height: Style.spacing.xs
      visible: root.now !== "" && root.next.length > 0
    }

    Caption {
      visible: root.next.length > 0
      text: "Después"
    }

    Repeater {
      model: root.next

      Row {
        required property var modelData
        width: column.width
        spacing: Style.spacing.md

        Text {
          id: bullet
          textFormat: Text.PlainText
          text: "›"
          color: Commons.Color.foreground
          opacity: 0.5
          font.family: Style.font.family
          font.pixelSize: Style.font.bodySmall
        }

        Text {
          width: column.width - bullet.width - Style.spacing.md
          textFormat: Text.PlainText
          text: modelData
          wrapMode: Text.Wrap
          color: Commons.Color.foreground
          font.family: Style.font.family
          font.pixelSize: Style.font.bodySmall
        }
      }
    }
  }
}
