import QtQuick
import QtQuick.Layouts
import qs.theme
import qs.services
import qs.shell.components

// Seven-day forecast: weekday, icon, rain chance and a min/max bar scaled to
// the whole week.
CardSection {
    id: root
    readonly property var days: WeatherService.daily
    readonly property real weekMin: days.reduce((low, day) => day.min === null ? low : Math.min(low, day.min), Infinity)
    readonly property real weekMax: days.reduce((high, day) => day.max === null ? high : Math.max(high, day.max), -Infinity)
    readonly property real span: Math.max(1, weekMax - weekMin)
    visible: days.length > 0
    padding: Metrics.spaceMd
    spacing: Metrics.spaceXxs

    // Beside the hourly strip the forecast is half as wide, and the rain
    // chance is the one column that can go: the bar carries the day's shape.
    readonly property bool narrow: width > 0 && width < Metrics.iconXl * 11

    Repeater {
        model: root.days
        RowLayout {
            id: dayRow
            required property var modelData
            required property int index
            Layout.fillWidth: true
            spacing: Metrics.spaceSm

            ShellText {
                Layout.minimumWidth: Metrics.iconXl * 1.4
                text: dayRow.index === 0 ? "Today" : SettingsService.locale.toString(dayRow.modelData.date, "ddd")
                role: "small"
            }
            ShellIcon { Layout.preferredWidth: Metrics.iconLg; glyph: dayRow.modelData.icon; size: Metrics.iconSm; color: Colors.text }
            ShellText {
                visible: !root.narrow
                Layout.minimumWidth: Metrics.iconXl + Metrics.spaceMd
                text: dayRow.modelData.precipitation !== null && dayRow.modelData.precipitation >= 20 ? dayRow.modelData.precipitation + "%" : ""
                role: "caption"
                color: Colors.accentForeground
                font.features: { "tnum": 1 }
            }
            ShellText {
                Layout.minimumWidth: Metrics.iconXl
                horizontalAlignment: Text.AlignRight
                text: WeatherService.formatTemperature(dayRow.modelData.min)
                role: "small"
                muted: true
                font.features: { "tnum": 1 }
            }
            Item {
                Layout.fillWidth: true
                Layout.minimumWidth: Metrics.iconXl * 2
                implicitHeight: Metrics.progressTrack
                Rectangle {
                    anchors.fill: parent
                    radius: height / 2
                    color: Colors.track
                }
                Rectangle {
                    visible: dayRow.modelData.min !== null && dayRow.modelData.max !== null
                    x: parent.width * (dayRow.modelData.min - root.weekMin) / root.span
                    width: Math.max(height, parent.width * (dayRow.modelData.max - dayRow.modelData.min) / root.span)
                    height: parent.height
                    radius: height / 2
                    color: Colors.accent
                }
            }
            ShellText {
                Layout.minimumWidth: Metrics.iconXl
                text: WeatherService.formatTemperature(dayRow.modelData.max)
                role: "small"
                font.features: { "tnum": 1 }
            }
        }
    }
}
