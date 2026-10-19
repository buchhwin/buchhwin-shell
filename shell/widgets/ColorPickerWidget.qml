import QtQuick
import qs.shell.widgets
import qs.theme
import qs.services
import "../../services/color/ColorLogic.js" as Logic

// The last colour picked, as a widget: a dot in that colour beside the
// dropper. A click opens the list; picking a new one is a keystroke away from
// there, or Super+Shift+C from anywhere.
//
// It goes wherever a widget goes - the desktop, the bar, the notch, the quick
// panel, the dashboard - because it is an ordinary WidgetBase and the surfaces
// take whatever the registry offers.
WidgetBase {
    id: root
    readonly property string latest: ColorPickerService.history.length
        ? ColorPickerService.history[0] : ""

    // The dropper keeps the surface's ink and the colour goes into a dot
    // beside it, so the widget says what it knows even with no room for a
    // label at all. The dropper used to wear the colour itself, and a black
    // one picked vanished on the black notch (a white one on a light bar).
    icon: "󰈊"
    iconColor: root.latest.length ? root.glyphInk : root.mutedTextColor
    glyph: root.latest.length ? pickedGlyph : null
    label: root.latest.length ? root.latest.slice(1).toUpperCase() : "Pick"
    name: "Color"
    detail: ColorPickerService.history.length > 1
        ? ColorPickerService.history.length + " picked" : ""
    maxLabelWidth: 120

    Component {
        id: pickedGlyph
        Row {
            spacing: Metrics.spaceXxs * root.scaleFactor
            Text {
                anchors.verticalCenter: parent.verticalCenter
                text: root.icon
                color: root.iconColor
                font.family: Typography.iconFamily
                font.pixelSize: Typography.titleSize * root.scaleFactor
                textFormat: Text.PlainText
                renderType: Typography.renderType
            }
            // A ring in the muted ink around it: a dot in the surface's own
            // colour is still a dot.
            Rectangle {
                anchors.verticalCenter: parent.verticalCenter
                width: Metrics.dotSize * root.scaleFactor
                height: width
                radius: width / 2
                color: root.latest
                border.width: Metrics.borderWidth
                border.color: root.mutedTextColor
            }
        }
    }
}
