import Quickshell
import QtQuick
import QtQuick.Layouts
import qs.theme
import qs.services
import qs.shell.components
import "../../../services/appearance/TimeFormat.js" as TimeFormat

ColumnLayout {
    id: page
    spacing: Metrics.pageGap
    readonly property var appRows: NotificationService.ruleRows()

    SettingsSection {
        Layout.fillWidth: true
        title: "Do Not Disturb"
        description: NotificationService.dndActive ? NotificationService.dndLabel : "Off"
        SegmentedControl {
            focusOnTab: true
            Layout.fillWidth: true
            current: NotificationService.dndActive ? NotificationService.dndMode : "off"
            options: [{ value: "off", label: "Off" }, { value: "1h", label: "1 hour" }, { value: "tomorrow", label: "Until tomorrow" }, { value: "manual", label: "Indefinitely" }]
            onSelected: value => NotificationService.setDnd(value)
        }
        // Beside the choice it belongs to, and a label that fits its column:
        // "“Until tomorrow” ends at" under Popups wrapped over two lines.
        SettingRow {
            label: "Ends at"
            hint: "When “Until tomorrow” turns Do Not Disturb off"
            SegmentedControl {
                focusOnTab: true
                Layout.fillWidth: true
                current: String(SettingsService.value("notifications.dndTomorrowHour"))
                // "06:00" or "6:00 AM", as the clock is set.
                options: [6, 7, 8].map(hour => ({ value: String(hour),
                    label: TimeFormat.time(new Date(2000, 0, 1, hour, 0), SettingsService.twelveHourClock, ":") }))
                onSelected: value => SettingsService.set("notifications.dndTomorrowHour", parseInt(value))
            }
        }
        SettingRow {
            Layout.fillWidth: true
            labelFills: true
            label: "Mute automatically in fullscreen"
            ShellToggle { focusOnTab: true; checked: SettingsService.value("notifications.suppressFullscreen"); onToggled: value => SettingsService.set("notifications.suppressFullscreen", value) }
        }
        SettingRow {
            Layout.fillWidth: true
            labelFills: true
            label: "Mute automatically while a game is focused"
            // HyprlandService.gameActive: a Steam game or gamescope in front.
            hint: "A Steam game or gamescope in front. The Gaming mode turns Do Not Disturb on by itself."
            ShellToggle { focusOnTab: true; checked: SettingsService.value("notifications.suppressGames"); onToggled: value => SettingsService.set("notifications.suppressGames", value) }
        }
    }

    SettingsSection {
        Layout.fillWidth: true
        title: "Popups"
        SettingRow {
            label: "Duration"
            hint: "When the app does not set its own duration. The volume, brightness and keyboard-light displays have their own, much shorter one; this is only for notifications."
            SegmentedControl {
                focusOnTab: true
                Layout.fillWidth: true
                current: String(SettingsService.value("notifications.popupTimeoutMs"))
                options: [{ value: "2000", label: "2 s" }, { value: "4000", label: "4 s" },
                          { value: "6000", label: "6 s" }, { value: "10000", label: "10 s" }]
                onSelected: value => SettingsService.set("notifications.popupTimeoutMs", parseInt(value))
            }
        }
    }

    // Per app: the rule the notification centre's bell toggles (Normal,
    // Muted) and the one set only here (Always urgent). A rule used to be
    // visible only over its app's group in the centre, so a muted app with
    // nothing in the history stayed muted where nobody could see it.
    SettingsSection {
        Layout.fillWidth: true
        title: "Apps"
        description: "Muted apps never pop up. Always urgent ones pop up through everything but a Do Not Disturb you turned on yourself"
        EmptyState {
            Layout.fillWidth: true
            row: true
            visible: page.appRows.length === 0
            icon: "󰂚"
            title: "No apps yet"
            description: "An app appears here once it has sent a notification"
        }
        // Keyed by the app keys, strings (pitfall 76): a notification that
        // comes while the page is open does not rebuild every row.
        Repeater {
            model: ScriptModel { values: page.appRows.map(row => row.key) }
            SettingRow {
                id: appRow
                required property string modelData
                readonly property var row: page.appRows.find(entry => entry.key === modelData)
                    || ({ key: modelData, name: modelData, rule: "default" })
                Layout.fillWidth: true
                label: row.name
                SegmentedControl {
                    focusOnTab: true
                    Layout.fillWidth: true
                    current: appRow.row.rule
                    options: [{ value: "default", label: "Normal" }, { value: "mute", label: "Muted" }, { value: "critical", label: "Always urgent" }]
                    onSelected: value => NotificationService.setAppRule(appRow.modelData, value)
                }
            }
        }
    }
}
