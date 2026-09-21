import QtQuick
import QtQuick.Layouts
import qs.theme
import qs.services
import qs.shell.components

ColumnLayout {
    spacing: Metrics.panelGap

    CardSection {
        Layout.fillWidth: true
        padding: Metrics.spaceXs
        spacing: Metrics.spaceXxs

        Repeater {
            model: [
                { mode: "off", label: "Off", icon: "󰂚" },
                { mode: "1h", label: "For 1 hour", icon: Icons.busy },
                { mode: "tomorrow", label: "Until tomorrow morning", icon: "󰖔" },
                { mode: "manual", label: "Until I turn it off", icon: "󰂛" }
            ]
            ListRow {
                required property var modelData
                Layout.fillWidth: true
                level: 1
                icon: modelData.icon
                title: modelData.label
                selected: (modelData.mode === "off" && !NotificationService.dndActive)
                    || (NotificationService.dndActive && NotificationService.dndMode === modelData.mode)
                subtitle: selected && NotificationService.dndActive ? NotificationService.dndLabel : ""
                onClicked: NotificationService.setDnd(modelData.mode)
            }
        }
    }

    CardSection {
        Layout.fillWidth: true

        SettingRow {
            Layout.fillWidth: true
            labelFills: true
            label: "Mute automatically in fullscreen"
            ShellToggle {
                checked: SettingsService.value("notifications.suppressFullscreen")
                onToggled: value => SettingsService.set("notifications.suppressFullscreen", value)
            }
        }
        SettingRow {
            Layout.fillWidth: true
            labelFills: true
            label: "Mute automatically while gaming"
            ShellToggle {
                checked: SettingsService.value("notifications.suppressGames")
                onToggled: value => SettingsService.set("notifications.suppressGames", value)
            }
        }
        ShellText {
            Layout.fillWidth: true
            visible: NotificationService.autoSuppressed
            text: "Automatically muted right now"
            role: "small"
            color: Colors.warning
        }
    }
}
