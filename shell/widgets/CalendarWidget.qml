import Quickshell
import QtQuick
import QtQuick.Layouts
import qs.theme
import qs.services

// Next of today's remaining events. small: one line; medium: up to three
// events. Hidden when nothing else happens today.
ColumnLayout {
    id: root
    property var instance: null
    property real scaleFactor: 1
    property string sizeClass: "small"
    property bool hovered: false
    property string alignment: "right"
    property bool inGroup: false
    // A bar that runs down the screen: the glyph goes above the time, and the
    // title goes. A title is the one part of an event that has no short form
    // - "Review with the platform team" on a strip a pill wide is three
    // characters and an ellipsis, which says less than nothing - so stacked
    // the widget answers the smaller question it can answer honestly: when.
    // The time stacks the way the clock's does, hours over minutes.
    property bool vertical: false
    // The surface decides the ink: the notch is black in both themes, so a
    // widget placed there is handed its colours instead of the theme's.
    property color textColor: Colors.text
    property color mutedTextColor: Colors.mutedText
    readonly property var remaining: CalendarService.remainingToday(clock.date)
        .filter(event => !event.allDay)
    readonly property var shown: remaining.slice(0,
        sizeClass === "medium" && !inGroup && !vertical ? 3 : 1)
    property bool hasData: shown.length > 0

    spacing: Metrics.spaceXxs * scaleFactor

    SystemClock { id: clock; precision: SystemClock.Minutes }

    Repeater {
        model: root.shown
        GridLayout {
            id: row
            required property var modelData
            required property int index
            readonly property bool running: modelData.start <= clock.date
            Layout.alignment: root.vertical ? Qt.AlignHCenter
                : root.alignment === "left" ? Qt.AlignLeft
                : root.alignment === "center" ? Qt.AlignHCenter : Qt.AlignRight
            // One column stacks, a count nothing will reach lays them in a
            // line - the same two numbers `WidgetBase` uses.
            columns: root.vertical ? 1 : 1000
            columnSpacing: Metrics.spaceSm * root.scaleFactor
            rowSpacing: Metrics.spaceXxs * root.scaleFactor

            Text {
                visible: row.index === 0
                Layout.alignment: root.vertical ? Qt.AlignHCenter : Qt.AlignVCenter
                text: "󰃭"
                color: row.running ? Colors.accentForeground : root.textColor
                font.family: Typography.iconFamily
                font.pixelSize: Typography.titleSize * root.scaleFactor
                renderType: Typography.renderType
            }
            Text {
                Layout.alignment: root.vertical ? Qt.AlignHCenter : Qt.AlignVCenter
                horizontalAlignment: Text.AlignHCenter
                // No colon on two lines: the break is the separator, and a
                // colon left hanging after the hours reads as a missing
                // number. `lineHeight` pulls the pair back into one time.
                lineHeight: root.vertical && !row.running ? 0.92 : 1
                text: row.running ? "Now"
                    : root.vertical ? Qt.formatTime(row.modelData.start, "HH") + "\n"
                        + Qt.formatTime(row.modelData.start, "mm")
                    : Qt.formatTime(row.modelData.start, "HH:mm")
                color: row.running ? Colors.accentForeground : root.mutedTextColor
                font.family: Typography.family
                font.pixelSize: Typography.bodySize * root.scaleFactor
                font.features: { "tnum": 1 }
                renderType: Typography.renderType
            }
            Text {
                visible: root.sizeClass !== "icon" && !root.vertical
                Layout.maximumWidth: 220 * root.scaleFactor
                text: row.modelData.title
                elide: Text.ElideRight
                color: root.textColor
                font.family: Typography.family
                font.pixelSize: Typography.bodyLargeSize * root.scaleFactor
                renderType: Typography.renderType
            }
        }
    }
}
