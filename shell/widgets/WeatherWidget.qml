import QtQuick
import QtQuick.Layouts
import qs.theme
import qs.services

// small: icon and temperature. medium: plus condition and today's range.
// icon (pill bar): condition icon only.
// Hidden until a forecast exists (no location, disabled, first load).
// On a bar that runs down the screen this stacks: the glyph above the temperature.
GridLayout {
    id: root
    property bool vertical: false
    property var instance: null
    property real scaleFactor: 1
    property string sizeClass: "small"
    property bool hovered: false
    property string alignment: "right"
    property bool inGroup: false
    // The surface decides the ink: the notch is black in both themes, so a
    // widget placed there is handed its colours instead of the theme's.
    property color textColor: Colors.text
    property color mutedTextColor: Colors.mutedText
    readonly property var current: WeatherService.current
    property bool hasData: current !== null
    readonly property bool detailed: sizeClass !== "small" && !inGroup

    columns: vertical ? 1 : 1000
    columnSpacing: Metrics.spaceSm * scaleFactor
    rowSpacing: Metrics.spaceSm * scaleFactor

    Component.onCompleted: WeatherService.track()
    Component.onDestruction: WeatherService.untrack()

    Text {
        text: root.current ? root.current.icon : ""
        color: root.textColor
        font.family: Typography.iconFamily
        font.pixelSize: (root.detailed ? Typography.headlineSize : Typography.titleSize) * root.scaleFactor
        renderType: Typography.renderType
    }

    ColumnLayout {
        spacing: 0
        visible: root.sizeClass !== "icon"
        Text {
            text: root.current ? WeatherService.formatTemperature(root.current.temperature) : ""
            color: root.textColor
            font.family: Typography.family
            font.pixelSize: (root.detailed ? Typography.headlineSize : Typography.bodyLargeSize) * root.scaleFactor
            font.weight: root.detailed ? Typography.light : Typography.regular
            font.features: { "tnum": 1 }
            renderType: Typography.renderType
        }
        Text {
            visible: root.detailed && root.current !== null
            text: root.current ? root.current.label + " · " + WeatherService.formatTemperature(root.current.max)
                + " / " + WeatherService.formatTemperature(root.current.min) : ""
            color: root.mutedTextColor
            font.family: Typography.family
            font.pixelSize: Typography.smallSize * root.scaleFactor
            font.features: { "tnum": 1 }
            renderType: Typography.renderType
        }
    }
}
