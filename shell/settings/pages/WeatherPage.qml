import QtQuick
import QtQuick.Layouts
import qs.theme
import qs.services
import qs.shell.components

ColumnLayout {
    spacing: Metrics.spaceLg

    SettingsSection {
        Layout.fillWidth: true
        title: "Location"
        description: "Only the location, rounded to about 1 km, is sent to Open-Meteo, and it is stored only locally."

        ListRow {
            Layout.fillWidth: true
            icon: "󰍎"
            active: WeatherService.hasLocation
            title: WeatherService.hasLocation ? WeatherService.locationName : "No location set"
            subtitle: !WeatherService.hasLocation ? "Search for your city below"
                : WeatherService.status === "ok" ? "Updated " + WeatherService.updatedText
                : WeatherService.status === "stale" ? "Offline · updated " + WeatherService.updatedText
                : WeatherService.status === "error" ? "Weather service not reachable"
                : WeatherService.status === "disabled" ? "Weather is turned off" : "Loading …"
            ShellButton {
                focusOnTab: true
                visible: WeatherService.hasLocation
                icon: Icons.remove
                variant: "ghost"
                compact: true
                toolTip: "Clear"
                onClicked: WeatherService.clearLocation()
            }
        }

        ShellTextField {
            focusOnTab: true
            id: searchField
            Layout.fillWidth: true
            icon: Icons.search
            placeholder: "Search city …"
            busy: LocationService.busy
            onTextChanged: LocationService.search(text)
            onAccepted: if (LocationService.results.length) { LocationService.select(LocationService.results[0]); text = "" }
        }

        ShellText {
            visible: LocationService.error.length > 0 && searchField.text.trim().length >= 2 && !LocationService.busy
            text: LocationService.error
            role: "small"
            color: Colors.warning
        }

        Repeater {
            model: searchField.text.trim().length >= 2 ? LocationService.results : []
            ListRow {
                focusOnTab: true
                required property var modelData
                Layout.fillWidth: true
                icon: "󰍎"
                title: modelData.name
                subtitle: modelData.region
                chevron: true
                // Clearing the search removes this delegate, so keep the place first.
                onClicked: {
                    const place = modelData
                    searchField.text = ""
                    LocationService.select(place)
                }
            }
        }
    }

    SettingsSection {
        Layout.fillWidth: true
        title: "Display"

        SettingRow {
            Layout.fillWidth: true
            labelFills: true
            label: "Show weather"
            ShellToggle {
                focusOnTab: true
                checked: SettingsService.value("weather.enabled")
                onToggled: value => SettingsService.set("weather.enabled", value)
            }
        }
        SettingRow {
            label: "Unit"
            SegmentedControl {
                focusOnTab: true
                Layout.fillWidth: true
                current: SettingsService.value("weather.unit")
                options: [{ value: "celsius", label: "°C" }, { value: "fahrenheit", label: "°F" }]
                onSelected: value => SettingsService.set("weather.unit", value)
            }
        }
        SettingRow {
            label: "Refresh"
            hint: "Only while the dashboard or weather widget is visible"
            SegmentedControl {
                focusOnTab: true
                Layout.fillWidth: true
                current: String(SettingsService.value("weather.refreshMinutes"))
                options: [{ value: "15", label: "15 min" }, { value: "30", label: "30 min" }, { value: "60", label: "1 h" }]
                onSelected: value => SettingsService.set("weather.refreshMinutes", parseInt(value))
            }
        }
        RowLayout {
            ShellButton {
                focusOnTab: true
                icon: Icons.refresh
                text: "Refresh now"
                enabledState: WeatherService.hasLocation && WeatherService.enabled
                onClicked: WeatherService.refresh()
            }
        }
    }
}
