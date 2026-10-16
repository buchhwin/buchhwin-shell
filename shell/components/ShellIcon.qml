import QtQuick
import qs.theme

// Nerd Font glyph icon.
Text {
    property string glyph: ""
    property int size: Metrics.iconMd

    text: glyph
    color: Colors.text
    textFormat: Text.PlainText
    font.family: Typography.iconFamily
    font.pixelSize: size
    horizontalAlignment: Text.AlignHCenter
    verticalAlignment: Text.AlignVCenter
    renderType: Typography.renderType
}
