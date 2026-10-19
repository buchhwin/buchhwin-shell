import QtQuick
import QtQuick.Layouts
import qs.theme
import qs.services
import qs.shell.components

ColumnLayout {
    spacing: Metrics.pageGap

    CardSection {
        Layout.fillWidth: true
        padding: Metrics.spaceXs
        spacing: Metrics.spaceXxs

        Repeater {
            model: [
                { mode: "off", label: "Off", icon: "󰂚" },
                { mode: "1h", label: "For 1 hour", icon: Icons.busy },
                { mode: "tomorrow", label: "Until tomorrow morning", icon: Icons.untilMorning },
                { mode: "manual", label: "Until I turn it off", icon: "󰂛" }
            ]
            ListRow {
                required property var modelData
                Layout.fillWidth: true
                level: 1
                icon: modelData.icon
                selected: (modelData.mode === "off" && !NotificationService.dndActive)
                    || (NotificationService.dndActive && NotificationService.dndMode === modelData.mode)
                // A Do Not Disturb that a mode turned on (gaming) ends with
                // the mode, not when the user turns it off: the selected row
                // says so in its title, rather than "Until I turn it off"
                // over a line that said otherwise. A click makes it the
                // user's own, which that title then names.
                readonly property bool owned: selected && modelData.mode === "manual" && NotificationService.dndBy.length > 0
                title: owned ? NotificationService.dndLabel : modelData.label
                subtitle: selected && NotificationService.dndActive && !owned ? NotificationService.dndLabel : ""
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
            // A game's window in front (Steam, gamescope), which is not the
            // Gaming mode: that one has a Do Not Disturb of its own.
            label: "Mute automatically while a game is focused"
            ShellToggle {
                checked: SettingsService.value("notifications.suppressGames")
                onToggled: value => SettingsService.set("notifications.suppressGames", value)
            }
        }
        SettingRow {
            Layout.fillWidth: true
            labelFills: true
            label: "Mute automatically while sharing the screen"
            ShellToggle {
                checked: SettingsService.value("notifications.suppressSharing")
                onToggled: value => SettingsService.set("notifications.suppressSharing", value)
            }
        }
        // Why, when it is (NotificationService.quietReason).
        ShellText {
            Layout.fillWidth: true
            visible: NotificationService.autoSuppressed
            text: NotificationService.quietReason === "sharing" ? "Muted while the screen is shared"
                : NotificationService.quietReason === "game" ? "Muted while a game is in front"
                : "Automatically muted right now"
            role: "small"
            color: Colors.warning
        }
    }
}
