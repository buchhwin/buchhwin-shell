import QtQuick
import QtQuick.Layouts
import qs.theme
import qs.services
import qs.shell.components

ColumnLayout {
    spacing: Metrics.pageGap

    SettingsSection {
        Layout.fillWidth: true
        title: "Location"
        scope: "weather.locationName"
        description: "Only the location, rounded to about 1 km, is sent to Open-Meteo, and it is stored only locally. "
            + "Detecting it automatically asks ipinfo.io once, which sees this connection's IP address."

        ListRow {
            interactive: false
            Layout.fillWidth: true
            icon: Icons.location
            active: WeatherService.hasLocation
            title: WeatherService.hasLocation ? WeatherService.locationName : "No location set"
            subtitle: !WeatherService.hasLocation ? (LocationService.detecting ? "Detecting …" : "Search for your city below")
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
            // A search, not a value: text left in it does not keep the page
            // from being let go (SettingsPanel.pendingEdits).
            property bool scratch: true
            Layout.fillWidth: true
            icon: Icons.search
            placeholder: "Search city …"
            busy: LocationService.busy
            onTextChanged: LocationService.search(text)
            // The first place found for what the field says now - waiting for
            // that search if it is still out, never the previous one's.
            onAccepted: LocationService.acceptFirst()
        }
        Connections {
            target: LocationService
            function onPlaceChosen() { searchField.text = "" }
        }

        ShellText {
            visible: LocationService.error.length > 0 && searchField.text.trim().length >= 2 && !LocationService.busy
            text: LocationService.error
            role: "small"
            color: Colors.warning
        }

        RowLayout {
            Layout.fillWidth: true
            spacing: Metrics.spaceSm
            ShellButton {
                focusOnTab: true
                icon: Icons.location
                text: LocationService.detecting ? "Detecting …" : "Detect automatically"
                compact: true
                enabledState: !LocationService.detecting
                onClicked: LocationService.detectByIp()
            }
            ShellText {
                Layout.fillWidth: true
                visible: LocationService.detectError.length > 0 && !LocationService.detecting
                text: LocationService.detectError
                role: "small"
                color: Colors.warning
                wrapMode: Text.Wrap
            }
        }

        SettingRow {
            Layout.fillWidth: true
            labelFills: true
            label: "Detect when no location is set"
            hint: "Asks ipinfo.io once at startup; a place you chose is never replaced"
            ShellToggle { focusOnTab: true; checked: SettingsService.value("weather.autoLocate"); onToggled: value => SettingsService.set("weather.autoLocate", value) }
        }

        Repeater {
            model: searchField.text.trim().length >= 2 ? LocationService.results : []
            ListRow {
                focusOnTab: true
                required property var modelData
                Layout.fillWidth: true
                icon: Icons.location
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
            // WeatherService.track: the dashboard, the weather widget and
            // popup, the notch's overview and the lock screen.
            hint: "Only while something shows the weather"
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
