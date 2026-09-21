import Quickshell
import QtQuick
import QtQuick.Layouts
import qs.theme
import qs.services
import qs.shell.components
import "../../../services/profile/ProfileLogic.js" as Profile

ColumnLayout {
    spacing: Metrics.spaceLg

    SettingsSection {
        Layout.fillWidth: true
        title: "Profile"
        description: "Each profile has its own desktop mode, widget layout per display and bar"
        RowLayout {
            Layout.fillWidth: true
            spacing: Metrics.spaceSm
            ShellText { Layout.fillWidth: true; text: "Desktop mode: " + LayoutService.modeLabel; muted: true; wrapMode: Text.Wrap }
            ShellButton { icon: Icons.edit; text: "Widgets"; compact: true; onClicked: PanelService.open("settings", { page: "widgets" }) }
            ShellButton { icon: "󰘔"; text: "Bar & Notch"; compact: true; onClicked: PanelService.open("settings", { page: "bar" }) }
        }
        SettingRow {
            Layout.fillWidth: true
            labelFills: true
            visible: AdaptiveService.hasInternal
            label: "Choose automatically"
            hint: "Laptop without, Docked with an external display"
            ShellToggle { focusOnTab: true; checked: SettingsService.value("desktop.autoProfile"); onToggled: value => SettingsService.set("desktop.autoProfile", value) }
        }
        Repeater {
            model: LayoutService.profileNames
            ListRow {
                required property string modelData
                readonly property var template: LayoutService.templates[modelData] || {}
                Layout.fillWidth: true
                icon: Profile.icon(modelData)
                title: Profile.label(modelData, LayoutService.templates)
                subtitle: template.description || ""
                selected: LayoutService.activeProfile === modelData
                onClicked: LayoutService.setActiveProfile(modelData)
            }
        }
    }

    SettingsSection {
        Layout.fillWidth: true
        title: "Clock"
        SettingRow {
            Layout.fillWidth: true
            labelFills: true
            label: "Hints next to the clock"
            hint: "Only when needed: screen sharing, upcoming event, microphone in use, unread notifications or Do Not Disturb, charging, battery below 20%"
            ShellToggle {
                focusOnTab: true
                checked: SettingsService.value("desktop.clockIndicators")
                onToggled: value => SettingsService.set("desktop.clockIndicators", value)
            }
        }
        SettingRow {
            Layout.fillWidth: true
            labelFills: true
            label: "Volume and brightness indicator"
            hint: "Brief overlay at the bottom edge on key presses and changes"
            ShellToggle {
                focusOnTab: true
                checked: SettingsService.value("desktop.osd")
                onToggled: value => SettingsService.set("desktop.osd", value)
            }
        }
    }

    SettingsSection {
        Layout.fillWidth: true
        title: "Clipboard"
        description: "History with Super + V. Entries marked as sensitive by password managers are not saved."
        SettingRow {
            Layout.fillWidth: true
            labelFills: true
            label: "Save history"
            ShellToggle { checked: SettingsService.value("clipboard.history"); onToggled: value => SettingsService.set("clipboard.history", value) }
        }
        RowLayout {
            spacing: Metrics.spaceSm
            ShellButton { icon: Icons.copy; text: "Open history"; onClicked: PanelService.open("clipboard") }
            ShellButton {
                icon: Icons.remove
                text: "Clear history"
                variant: "ghost"
                // Everything the clipboard remembers, at once and for good.
                confirm: true
                onClicked: ClipboardService.wipe()
            }
        }
    }

    SettingsSection {
        Layout.fillWidth: true
        title: "Screen recording"
        description: "Super + Shift + R records a region, Super + Ctrl + Shift + R the screen. Press it again or click the red indicator to stop."
        Component.onCompleted: RecordingService.refreshBackends()
        ShellText {
            Layout.fillWidth: true
            visible: RecordingService.backendsKnown
            text: RecordingService.available ? "Recorder: " + RecordingService.backendLabel
                : "No recorder installed. Install with: sudo dnf install wf-recorder"
            role: "small"
            color: RecordingService.available ? Colors.mutedText : Colors.warning
            wrapMode: Text.Wrap
        }
        SettingRow {
            label: "Sound"
            hint: RecordingService.backend === "wf-recorder" && RecordingService.audio === "desktop+mic" ? "wf-recorder records desktop sound only" : ""
            SegmentedControl {
                focusOnTab: true
                Layout.fillWidth: true
                current: RecordingService.audio
                options: [{ value: "off", label: "Off" }, { value: "desktop", label: "Desktop" }, { value: "desktop+mic", label: "Desktop + mic" }]
                onSelected: value => SettingsService.set("recording.audio", value)
            }
        }
        SettingRow {
            label: "Frame rate"
            SegmentedControl {
                focusOnTab: true
                Layout.fillWidth: true
                current: String(RecordingService.fps)
                options: [{ value: "30", label: "30 fps" }, { value: "60", label: "60 fps" }]
                onSelected: value => SettingsService.set("recording.fps", parseInt(value))
            }
        }
        SettingRow {
            label: "Folder"
            ShellTextField {
                focusOnTab: true
                id: recordingFolder
                Layout.fillWidth: true
                icon: Icons.folder
                placeholder: "~/Videos/Recordings"
                text: SettingsService.value("recording.folder")
                onAccepted: SettingsService.set("recording.folder", text.trim())
                onInputActiveFocusChanged: if (!inputActiveFocus) SettingsService.set("recording.folder", text.trim())
            }
            ShellButton {
                focusOnTab: true
                icon: Icons.folder; text: "Open"; compact: true
                onClicked: { Quickshell.execDetached(["sh", "-c", 'mkdir -p -- "$1" && xdg-open "$1"', "sh", RecordingService.folder]); PanelService.close() }
            }
        }
    }

    SettingsSection {
        Layout.fillWidth: true
        title: "Removable drives"
        description: "USB sticks, SD cards, external disks, encrypted volumes and MTP phones. Eject them in the Control Center before unplugging."
        SettingRow {
            Layout.fillWidth: true
            labelFills: true
            label: "Notify when a drive is connected"
            ShellToggle { focusOnTab: true; checked: SettingsService.value("drives.notify"); onToggled: value => SettingsService.set("drives.notify", value) }
        }
        SettingRow {
            Layout.fillWidth: true
            labelFills: true
            label: "Open automatically"
            hint: "Mount new drives and show them in the file manager (encrypted volumes still ask for the passphrase)"
            ShellToggle { focusOnTab: true; checked: SettingsService.value("drives.autoOpen"); onToggled: value => SettingsService.set("drives.autoOpen", value) }
        }
        ShellButton {
            visible: DrivesService.drives.length > 0 || DrivesService.phones.length > 0
            icon: "󰋊"; text: "Show drives"
            onClicked: PanelService.open("controlCenter", { page: "drives" })
        }
    }
}
