import QtQuick
import qs.shell.widgets
import qs.theme
import qs.services

WidgetBase {
    id: root
    icon: NetworkService.icon
    label: inGroup ? "" : NetworkService.summary
    maxLabelWidth: 160
    name: "Network"
    // The island's strip asks for bars (`options.glyph: "bars"`): four rising
    // bars in the accent, lit by signal strength, the rest in the muted ink.
    // Everywhere else the glyph stays the one the theme names.
    readonly property bool bars: instance !== null && instance.options !== undefined
        && instance.options !== null && instance.options.glyph === "bars"
    readonly property int barCount: 4
    readonly property int litBars: NetworkService.signalBars(barCount)
    glyph: bars ? barsGlyph : null

    Component {
        id: barsGlyph
        Row {
            spacing: Metrics.spaceXxs * root.scaleFactor
            Repeater {
                model: root.barCount
                Rectangle {
                    required property int index
                    anchors.bottom: parent.bottom
                    width: Metrics.signalBarWidth * root.scaleFactor
                    height: (Metrics.signalBarMin + index * Metrics.signalBarStep) * root.scaleFactor
                    radius: width / 3
                    // A level, so the accent made for a fill: the raw teal's
                    // lit bars were all but gone on a light pill.
                    color: index < root.litBars ? root.levelFill : root.mutedTextColor
                    opacity: index < root.litBars ? 1 : Effects.mutedOpacity
                }
            }
        }
    }
}
