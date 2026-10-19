import Quickshell
import QtQuick
import QtQuick.Layouts
import qs.theme
import qs.services
import qs.shell.components

ColumnLayout {
    spacing: Metrics.pageGap

    SettingsSection {
        Layout.fillWidth: true
        title: "Clock"
        SettingRow {
            Layout.fillWidth: true
            label: "Time format"
            hint: "Automatic follows the interface language. Applies to the clock, the notch, the dashboard, the lock screen and the weather."
            SegmentedControl {
                focusOnTab: true
                Layout.fillWidth: true
                current: SettingsService.value("appearance.clockFormat")
                options: [{ value: "locale", label: "Automatic" },
                          { value: "24", label: "24 hours" },
                          { value: "12", label: "12 hours" }]
                onSelected: value => SettingsService.set("appearance.clockFormat", value)
            }
        }
        SettingRow {
            Layout.fillWidth: true
            labelFills: true
            label: "Hints next to the clock"
            // The battery's level is the one Settings > Power warns at.
            hint: "Only when needed: screen sharing, upcoming event, microphone in use, unread notifications or Do Not Disturb, charging, battery at or below " + PowerService.lowBatteryLevel + "%"
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
        scope: "clipboard.history"
        description: "History with " + ShortcutService.keyHint("SUPER + V", true) + ". Entries marked as sensitive by password managers are not saved. Passwords from programs that do not mark them are kept like any text."
        SettingRow {
            Layout.fillWidth: true
            labelFills: true
            label: "Save history"
            ShellToggle { focusOnTab: true; checked: SettingsService.value("clipboard.history"); onToggled: value => SettingsService.set("clipboard.history", value) }
        }
        // Both off by default, which is how the history always behaved
        // (ClipboardService: the wipe at logout, the age limit).
        SettingRow {
            Layout.fillWidth: true
            labelFills: true
            label: "Forget the history at logout"
            hint: "Also after a crash or a power cut, at the next login."
            ShellToggle { focusOnTab: true; checked: SettingsService.value("clipboard.forgetAtLogout") === true; onToggled: value => SettingsService.set("clipboard.forgetAtLogout", value) }
        }
        SettingRow {
            label: "Forget entries after"
            ShellSelect {
                focusOnTab: true
                Layout.fillWidth: true
                options: [{ value: "0", label: "Never" }, { value: "1", label: "1 hour" }, { value: "8", label: "8 hours" },
                          { value: "24", label: "1 day" }, { value: "168", label: "1 week" }]
                current: String(SettingsService.value("clipboard.maxAgeHours"))
                onSelected: value => SettingsService.set("clipboard.maxAgeHours", parseInt(value))
            }
        }
        RowLayout {
            spacing: Metrics.spaceSm
            ShellButton { focusOnTab: true; icon: Icons.copy; text: "Open history"; onClicked: PanelService.open("clipboard") }
            ShellButton {
                focusOnTab: true
                icon: Icons.remove
                text: "Clear history"
                variant: "ghost"
                // Everything the clipboard remembers, at once and for good.
                confirm: true
                confirmText: "Clear history?"
                onClicked: ClipboardService.wipe()
            }
        }
    }

    SettingsSection {
        Layout.fillWidth: true
        title: "Screen recording"
        description: ShortcutService.keyHint("SUPER + SHIFT + R", true) + " records a region, " + ShortcutService.keyHint("SUPER + CTRL + SHIFT + R", true)
            + " the screen. Press it again or click the red indicator to stop."
        PageActivity { onOpened: RecordingService.refreshBackends() }
        ShellText {
            Layout.fillWidth: true
            visible: RecordingService.backendsKnown
            text: RecordingService.available ? "Recorder: " + RecordingService.backendLabel
                : "No recorder installed. " + DistroService.installHint("wf-recorder")
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
            // Leaving the field empty keeps the folder (Escape used to store
            // nothing on the way out); Return on an empty field is the way
            // back to the default.
            hint: "Clear it and press Enter for the default"
            StoredTextField {
                focusOnTab: true
                id: recordingFolder
                Layout.fillWidth: true
                icon: Icons.folder
                placeholder: "~/Videos/Recordings"
                storedText: SettingsService.value("recording.folder")
                onCommit: value => SettingsService.set("recording.folder", value.trim())
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
        scope: "drives.notify"
        description: "USB sticks, SD cards, external disks, encrypted volumes and MTP phones. Eject them in the control center before unplugging."
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
            focusOnTab: true
            visible: DrivesService.drives.length > 0 || DrivesService.phones.length > 0
            icon: "󰋊"; text: "Show drives"
            onClicked: PanelService.open("controlCenter", { page: "drives" })
        }
    }
}
