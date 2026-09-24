import QtQuick
import QtQuick.Layouts
import qs.theme
import qs.services
import qs.shell.components

ColumnLayout {
    spacing: Metrics.spaceLg

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
        SettingRow {
            Layout.fillWidth: true
            labelFills: true
            label: "Mute automatically in fullscreen"
            ShellToggle { focusOnTab: true; checked: SettingsService.value("notifications.suppressFullscreen"); onToggled: value => SettingsService.set("notifications.suppressFullscreen", value) }
        }
        SettingRow {
            Layout.fillWidth: true
            labelFills: true
            label: "Mute automatically while gaming"
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
        SettingRow {
            label: "“Until tomorrow” ends at"
            SegmentedControl {
                focusOnTab: true
                Layout.fillWidth: true
                current: String(SettingsService.value("notifications.dndTomorrowHour"))
                options: [{ value: "6", label: "06:00" }, { value: "7", label: "07:00" }, { value: "8", label: "08:00" }]
                onSelected: value => SettingsService.set("notifications.dndTomorrowHour", parseInt(value))
            }
        }
    }
}
