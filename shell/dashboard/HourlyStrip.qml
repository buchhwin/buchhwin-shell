import QtQuick
import QtQuick.Layouts
import qs.theme
import qs.services
import qs.shell.components
import "../../services/appearance/TimeFormat.js" as TimeFormat

// Next 24 hours in three-hour steps.
ShellCard {
    id: root
    readonly property var hours: WeatherService.sampleHours(3, 8)
    visible: hours.length > 0
    implicitHeight: row.implicitHeight + Metrics.spaceMd * 2

    RowLayout {
        id: row
        anchors.fill: parent
        anchors.margins: Metrics.spaceMd
        spacing: 0

        Repeater {
            model: root.hours
            ColumnLayout {
                required property var modelData
                required property int index
                Layout.fillWidth: true
                Layout.preferredWidth: row.width / Math.max(1, root.hours.length)
                spacing: Metrics.spaceXxs
                ShellText {
                    Layout.alignment: Qt.AlignHCenter
                    text: index === 0 ? "Now" : TimeFormat.hourLabel(modelData.time, SettingsService.twelveHourClock)
                    role: "caption"
                }
                ShellIcon {
                    Layout.alignment: Qt.AlignHCenter
                    glyph: modelData.icon
                    size: Metrics.iconMd
                    color: Colors.text
                }
                ShellText {
                    Layout.alignment: Qt.AlignHCenter
                    text: WeatherService.formatTemperature(modelData.temperature)
                    role: "small"
                    font.features: { "tnum": 1 }
                }
                ShellText {
                    Layout.alignment: Qt.AlignHCenter
                    text: modelData.precipitation === null ? " " : modelData.precipitation + "%"
                    role: "caption"
                    color: modelData.precipitation !== null && modelData.precipitation >= 40 ? Colors.accentForeground : Colors.subtleText
                    font.features: { "tnum": 1 }
                }
            }
        }
    }
}
