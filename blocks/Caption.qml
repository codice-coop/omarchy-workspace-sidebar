import QtQuick
import qs.Commons
import qs.Commons as Commons

// Small muted label above a block's content.
Text {
  textFormat: Text.PlainText
  color: Commons.Color.foreground
  opacity: 0.5
  font.family: Style.font.family
  font.pixelSize: Style.font.caption
  font.capitalization: Font.AllUppercase
  font.letterSpacing: 0.5
}
