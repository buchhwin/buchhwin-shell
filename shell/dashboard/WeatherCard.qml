import QtQuick
import QtQuick.Layouts
import qs.theme
import qs.services
import qs.shell.components

// Current weather with details, hourly strip and seven-day forecast. Empty,
// loading and offline states stay honest instead of showing sample data.
ColumnLayout {
    id: root
    spacing: Metrics.spaceLg

    // Location and update time below the forecast (the popup shows them in its header).
    property bool showLocation: true
    // Two columns: current conditions and the hourly strip on the left, the
    // seven days beside them instead of underneath. A stack of four blocks
    // makes the weather popup very tall; the width is there, so use it.
    property bool wide: false
    readonly property real columnWidth: wide ? (width - Metrics.spaceLg) / 2 : width
    // How much of the forecast the card has room for, largest first. The
    // popup that has always shown all of it says nothing and keeps it; a card
    // in a grid cell says how tall it was pulled to, and gives up the seven
    // days before the next hours, and the next hours before the conditions
    // that are the point of the card.
    property bool showHourly: true
    property bool showDaily: true
    readonly property var current: WeatherService.current
    readonly property string status: WeatherService.status

    // The one empty state, not a card that draws one by hand.
    CardSection {
        Layout.fillWidth: true
        visible: root.current === null

        EmptyState {
            Layout.fillWidth: true
            row: true
            icon: root.status === "error" ? "󰖪" : "󰖐"
            // The state is the title, as in every other empty state; the card's
            // name is not news. The description is only where there is more to
            // say than the button under it already does.
            title: root.status === "disabled" ? "Weather is turned off"
                : root.status === "noLocation" ? "No location set"
                : root.status === "error" ? "Weather is unavailable"
                : "Loading weather …"
            description: root.status === "disabled" ? "Settings > Weather"
                : root.status === "error" ? "Retrying the next time you open this"
                : ""

            ShellButton {
                visible: root.status === "noLocation" || root.status === "disabled"
                icon: "󰍎"
                text: "Set location"
                compact: true
                onClicked: PanelService.open("settings", { page: "weather" })
            }
            ShellButton {
                visible: root.status === "error"
                icon: Icons.refresh
                text: "Retry"
                variant: "ghost"
                compact: true
                onClicked: WeatherService.refresh()
            }
        }
    }

    ColumnLayout {
        Layout.fillWidth: true
        visible: root.current !== null
        spacing: Metrics.spaceLg

        GridLayout {
            Layout.fillWidth: true
            columns: root.wide ? 2 : 1
            columnSpacing: Metrics.spaceLg
            rowSpacing: Metrics.spaceLg

            ColumnLayout {
                Layout.fillWidth: true
                Layout.alignment: Qt.AlignTop
                spacing: Metrics.spaceLg

            RowLayout {
                Layout.fillWidth: true
                spacing: Metrics.spaceLg

                ShellIcon {
                    Layout.alignment: Qt.AlignTop
                    glyph: root.current ? root.current.icon : ""
                    size: Metrics.iconXl * 1.5
                    color: Colors.text
                }

                ColumnLayout {
                    Layout.alignment: Qt.AlignTop
                    spacing: 0
                    Text {
                        text: root.current ? WeatherService.formatTemperature(root.current.temperature) : ""
                        color: Colors.text
                        font.family: Typography.family
                        font.pixelSize: Typography.displaySize
                        font.weight: Typography.light
                        font.features: { "tnum": 1 }
                        renderType: Typography.renderType
                    }
                    ShellText { text: root.current ? root.current.label : ""; role: "bodyLarge" }
                    ShellText {
                        visible: root.current !== null && root.current.max !== null
                        text: root.current ? "H " + WeatherService.formatTemperature(root.current.max) + "  L " + WeatherService.formatTemperature(root.current.min) : ""
                        role: "small"
                        muted: true
                    }
                }

                Item { Layout.fillWidth: true }

                ColumnLayout {
                    Layout.alignment: Qt.AlignTop
                    Layout.preferredWidth: Metrics.iconXl * 4
                    spacing: Metrics.spaceXs

                    Repeater {
                        model: root.current ? [
                            { label: "Feels like", value: WeatherService.formatTemperature(root.current.feelsLike) },
                            { label: "Rain", value: root.current.precipitation === null ? "–" : root.current.precipitation + "%" },
                            { label: "Wind", value: root.current.wind === null ? "–" : Math.round(root.current.wind) + " km/h" },
                            { label: "Humidity", value: root.current.humidity === null ? "–" : root.current.humidity + "%" },
                            { label: "UV index", value: root.current.uv === null ? "–" : String(Math.round(root.current.uv)) }
                        ] : []
                        delegate: RowLayout {
                            required property var modelData
                            Layout.fillWidth: true
                            spacing: Metrics.spaceMd
                            ShellText { Layout.fillWidth: true; text: modelData.label; role: "small"; muted: true }
                            ShellText { text: modelData.value; role: "small"; font.features: { "tnum": 1 } }
                        }
                    }
                }
            }

                HourlyStrip { Layout.fillWidth: true; visible: root.showHourly }
            }

            DailyForecast {
                visible: root.showDaily
                Layout.fillWidth: true
                Layout.preferredWidth: root.columnWidth
                Layout.maximumWidth: root.columnWidth
                Layout.alignment: Qt.AlignTop
            }
        }

        RowLayout {
            visible: root.showLocation
            Layout.fillWidth: true
            spacing: Metrics.spaceXs
            ShellIcon { glyph: "󰍎"; size: Metrics.iconXs; color: Colors.mutedText }
            ShellText { Layout.fillWidth: true; text: WeatherService.locationName; role: "small"; muted: true }
            ShellText {
                text: (WeatherService.status === "stale" ? "Offline · updated " : "Updated ") + WeatherService.updatedText
                role: "small"
                color: WeatherService.status === "stale" ? Colors.warning : Colors.subtleText
            }
        }
    }
}
