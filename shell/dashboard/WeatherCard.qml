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
    // The dashboard sizes the card to its cell; the last card of it then
    // runs to the cell's bottom edge (the empty state's, or the seven days),
    // so the cards beside it do not end on a ragged line. The popup grows
    // with its content and leaves this off. Something always takes the spare
    // height - the spacer at the end when no card can - or the column spread
    // it between its blocks and the conditions slid down the cell.
    property bool fillsCell: false
    // How many grid rows the dashboard's cell is tall, 0 outside a grid.
    property int rows: 0
    readonly property var current: WeatherService.current
    readonly property string status: WeatherService.status
    // Open-Meteo is asked for miles per hour with Fahrenheit (WeatherLogic's
    // forecastUrl), so the label follows the same setting.
    readonly property string windUnit: WeatherService.unit === "fahrenheit" ? "mph" : "km/h"

    // An empty state in a cell the size of a panel - the Default dashboard's
    // weather is 4 rows, 440 px - is a panel's: the column, in the middle of
    // the card. The row beside the icon is for the small cells and the
    // popup; at the top of a tall card it left ~380 px of nothing under it.
    readonly property bool centred: fillsCell && rows > 3
    // Asked from this card, so a failure is this card's to show.
    property bool locating: false

    // The one empty state, not a card that draws one by hand. A plain card
    // rather than a CardSection, whose content is stacked from the top: the
    // column form sits in the middle of whatever height the cell gives it.
    ShellCard {
        id: emptyCard
        Layout.fillWidth: true
        Layout.fillHeight: root.fillsCell
        visible: root.current === null
        implicitHeight: emptyState.implicitHeight + Metrics.spaceLg * 2

        EmptyState {
            id: emptyState
            anchors.left: parent.left
            anchors.right: parent.right
            anchors.margins: Metrics.spaceLg
            y: root.centred ? Math.max(Metrics.spaceLg, Math.round((emptyCard.height - implicitHeight) / 2))
                : Metrics.spaceLg
            row: !root.centred
            icon: root.status === "error" ? "󰖪" : "󰖐"
            // The state is the title, as in every other empty state; the card's
            // name is not news. The description is only where there is more to
            // say than the buttons under it already do.
            title: root.status === "disabled" ? "Weather is turned off"
                : root.status === "noLocation" ? "No location set"
                : root.status === "error" ? "Weather is unavailable"
                : "Loading weather …"
            description: root.status === "disabled" ? "Settings > Weather"
                : root.status === "error" ? "Retrying the next time you open this"
                : root.status !== "noLocation" ? ""
                : LocationService.detecting ? "Asking ipinfo.io …"
                : root.locating && LocationService.detectError.length ? LocationService.detectError
                : "Find it from this connection (asks ipinfo.io) or choose a city"

            // The welcome tour's two ways to a place: from the connection
            // (ipinfo.io sees this computer's address, so it is a button and
            // never automatic), or a city chosen in Settings.
            ShellButton {
                visible: root.status === "noLocation"
                icon: Icons.location
                text: "Find my place"
                toolTip: "Asks ipinfo.io once, which sees this computer's IP address"
                compact: true
                enabledState: !LocationService.detecting
                onClicked: {
                    root.locating = true
                    LocationService.detectByIp()
                }
            }
            ShellButton {
                visible: root.status === "noLocation"
                text: "Choose a city …"
                variant: "ghost"
                compact: true
                onClicked: PanelService.open("settings", { page: "weather" })
            }
            ShellButton {
                visible: root.status === "disabled"
                icon: Icons.location
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
        Layout.fillHeight: root.fillsCell && root.showDaily
        visible: root.current !== null
        spacing: Metrics.spaceLg

        GridLayout {
            Layout.fillWidth: true
            Layout.fillHeight: root.fillsCell && root.showDaily
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
                    size: Metrics.weatherNowIcon
                    color: Colors.text
                }

                ColumnLayout {
                    Layout.alignment: Qt.AlignTop
                    spacing: 0
                    Text {
                        text: root.current ? WeatherService.formatTemperature(root.current.temperature) : ""
                        color: Colors.text
                        textFormat: Text.PlainText
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
                    Layout.preferredWidth: Metrics.weatherNowColumn
                    spacing: Metrics.spaceXs

                    Repeater {
                        model: root.current ? [
                            { label: "Feels like", value: WeatherService.formatTemperature(root.current.feelsLike) },
                            { label: "Rain", value: root.current.precipitation === null ? "–" : root.current.precipitation + "%" },
                            { label: "Wind", value: root.current.wind === null ? "–" : Math.round(root.current.wind) + " " + root.windUnit },
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
                Layout.fillHeight: root.fillsCell
                Layout.preferredWidth: root.columnWidth
                Layout.maximumWidth: root.columnWidth
                Layout.alignment: Qt.AlignTop
            }
        }

        RowLayout {
            visible: root.showLocation
            Layout.fillWidth: true
            spacing: Metrics.spaceXs
            ShellIcon { glyph: Icons.location; size: Metrics.iconXs; color: Colors.mutedText }
            ShellText { Layout.fillWidth: true; text: WeatherService.locationName; role: "small"; muted: true }
            ShellText {
                text: (WeatherService.status === "stale" ? "Offline · updated " : "Updated ") + WeatherService.updatedText
                role: "small"
                color: WeatherService.status === "stale" ? Colors.warning : Colors.mutedText
            }
        }
    }

    Item {
        visible: root.fillsCell && root.current !== null && !root.showDaily
        Layout.fillHeight: true
    }
}
