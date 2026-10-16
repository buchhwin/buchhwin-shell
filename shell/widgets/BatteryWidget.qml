import QtQuick
import qs.shell.widgets
import qs.theme
import qs.services

// Battery level, and from `medium` up what that level actually means: a bar,
// and how long it is good for. It used to be its own copy of WidgetBase's
// icon-and-label row, which is why it never gained anything the others did.
WidgetBase {
    id: root
    // The island's strip asks for a battery lying down (`options.glyph:
    // "horizontal"`): a case in the muted ink with its nub, filled to the level
    // in the icon's colour (charging, low, or the plain ink). Without a
    // battery there is nothing to lie down, and the power glyph stays.
    readonly property bool lying: instance !== null && instance.options !== undefined
        && instance.options !== null && instance.options.glyph === "horizontal"
    glyph: lying && PowerService.hasBattery ? batteryGlyph : null
    icon: PowerService.icon
    // Low is PowerService's, the level set in Settings > Power, so the glyph
    // turns red where the warning comes and nowhere else. Charging is the
    // green or the accent (Settings > Power > Status colors); low is red in
    // both.
    iconColor: PowerService.charging ? root.successInk
        : PowerService.low ? root.dangerInk : root.glyphInk
    label: PowerService.percent + "%"
    name: PowerService.hasBattery ? "Battery" : "Power"
    meter: PowerService.hasBattery ? PowerService.percent / 100 : -1
    // The plain level is the accent as a fill, which a charging level in
    // the accent is too: the same bar on and off the charger.
    meterColor: PowerService.charging ? root.successFill
        : PowerService.low ? root.dangerInk : root.levelFill
    detail: PowerService.remainingLabel.length ? PowerService.remainingLabel : PowerService.stateLabel

    Component {
        id: batteryGlyph
        Item {
            implicitWidth: (Metrics.batteryGlyphWidth + Metrics.batteryGlyphNub) * root.scaleFactor
            implicitHeight: Metrics.batteryGlyphHeight * root.scaleFactor
            Rectangle {
                id: batteryCase
                width: Metrics.batteryGlyphWidth * root.scaleFactor
                height: parent.height
                radius: height / 4
                color: "transparent"
                border.width: Metrics.borderWidth
                border.color: root.mutedTextColor
                Rectangle {
                    anchors.left: parent.left
                    anchors.top: parent.top
                    anchors.bottom: parent.bottom
                    anchors.margins: Metrics.spaceXxs
                    width: Math.max(0, (parent.width - Metrics.spaceXxs * 2) * Math.max(0, Math.min(1, PowerService.percent / 100)))
                    radius: parent.radius / 2
                    color: root.iconColor
                }
            }
            Rectangle {
                anchors.left: batteryCase.right
                anchors.verticalCenter: batteryCase.verticalCenter
                width: Metrics.batteryGlyphNub * root.scaleFactor
                height: parent.height / 3
                radius: width / 2
                color: root.mutedTextColor
            }
        }
    }
}
