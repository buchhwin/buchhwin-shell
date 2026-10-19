import Quickshell
import QtQuick
import QtQuick.Layouts
import qs.theme
import qs.services
import qs.shell.components
import "../../../services/appearance/DateFormat.js" as DateFormat

ColumnLayout {
    id: page
    spacing: Metrics.pageGap
    // A date to show the choices with: today, as the page opens.
    readonly property var dateSample: new Date()
    // Formats: English in its two date orders and the system's own; a value
    // set by hand in settings.json stays offered.
    readonly property var localeOptions: {
        const base = [{ value: "en_GB", label: "English (United Kingdom)" },
                      { value: "en_US", label: "English (United States)" },
                      { value: "system", label: "System (" + Qt.locale().name + ")" }]
        const current = SettingsService.localeName
        return base.some(option => option.value === current) ? base : base.concat([{ value: current, label: current }])
    }

    SettingsSection {
        Layout.fillWidth: true
        title: "Clock"
        SettingRow {
            Layout.fillWidth: true
            label: "Time format"
            hint: "Automatic follows Formats below. Applies to the clock, the notch, the dashboard, the lock screen and the weather."
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
        // The order of day and month in every date the shell writes
        // (DateFormat.js), in the language's words either way.
        SettingRow {
            Layout.fillWidth: true
            label: "Date order"
            hint: "Applies to the notch, the dashboard, the widgets, the popups and the lock screen."
            SegmentedControl {
                focusOnTab: true
                Layout.fillWidth: true
                current: SettingsService.dateOrder
                options: [{ value: "locale", label: "Automatic" },
                          { value: "dayMonth", label: DateFormat.date(page.dateSample, SettingsService.locale, "day", "dayMonth") },
                          { value: "monthDay", label: DateFormat.date(page.dateSample, SettingsService.locale, "day", "monthDay") }]
                onSelected: value => SettingsService.set("appearance.dateOrder", value)
            }
        }
        SettingRow {
            Layout.fillWidth: true
            labelFills: true
            label: "Short dates in numbers"
            hint: "Where a date has little room: " + DateFormat.date(page.dateSample, SettingsService.locale, "short", SettingsService.dateOrder, true)
                + " instead of " + DateFormat.date(page.dateSample, SettingsService.locale, "short", SettingsService.dateOrder, false)
            ShellToggle {
                focusOnTab: true
                checked: SettingsService.shortDateNumbers
                onToggled: value => SettingsService.set("appearance.shortDateNumbers", value)
            }
        }
        SettingRow {
            Layout.fillWidth: true
            label: "Formats"
            hint: "The names of days and months, and what Automatic means for the time format and the date order."
            ShellSelect {
                focusOnTab: true
                Layout.fillWidth: true
                options: page.localeOptions
                current: SettingsService.localeName
                onSelected: value => SettingsService.set("appearance.locale", value)
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

    // Short messages for state changes (Osd.qml, OsdLogic): each off unless
    // turned on here, and none while the indicator above is off.
    SettingsSection {
        Layout.fillWidth: true
        title: "Messages on screen"
        description: "A short message where the volume indicator shows. Needs the indicator above."
        SettingRow {
            Layout.fillWidth: true
            labelFills: true
            label: "Audio output changes"
            hint: "The name of the output that plays now, after headphones are plugged in or connect"
            ShellToggle { focusOnTab: true; enabledState: SettingsService.value("desktop.osd"); checked: SettingsService.value("toasts.output") === true; onToggled: value => SettingsService.set("toasts.output", value) }
        }
        SettingRow {
            Layout.fillWidth: true
            labelFills: true
            label: "Charger plugged in or out"
            hint: "With the battery's level"
            ShellToggle { focusOnTab: true; enabledState: SettingsService.value("desktop.osd"); checked: SettingsService.value("toasts.charger") === true; onToggled: value => SettingsService.set("toasts.charger", value) }
        }
        SettingRow {
            Layout.fillWidth: true
            labelFills: true
            label: "VPN connects or disconnects"
            ShellToggle { focusOnTab: true; enabledState: SettingsService.value("desktop.osd"); checked: SettingsService.value("toasts.vpn") === true; onToggled: value => SettingsService.set("toasts.vpn", value) }
        }
        SettingRow {
            Layout.fillWidth: true
            labelFills: true
            label: "Caps Lock"
            hint: "When it is turned on or off"
            ShellToggle { focusOnTab: true; enabledState: SettingsService.value("desktop.osd"); checked: SettingsService.value("toasts.capsLock") === true; onToggled: value => SettingsService.set("toasts.capsLock", value) }
        }
    }

    SettingsSection {
        Layout.fillWidth: true
        title: "Clipboard"
        scope: "clipboard.history"
        description: "History with " + ShortcutService.keyHint("SUPER + V", true) + ". Entries marked as sensitive by password managers are not saved. Passwords from programs that do not mark them are kept like any text. Ctrl+P in the history pins an entry: pinned entries stay through Clear history and forgetting until you unpin them."
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
        title: "Media player"
        SettingRow {
            Layout.fillWidth: true
            labelFills: true
            label: "Visualizer in the media popup"
            // cava draws it (in every distribution's package list); a machine
            // without it is told how to get it rather than given a switch
            // that does nothing.
            hint: MprisService.visualizerMissing ? "cava is not installed. " + DistroService.installHint("cava")
                : "Bars that move with the sound while something plays. Not with reduced motion."
            ShellToggle {
                focusOnTab: true
                checked: SettingsService.value("desktop.mediaVisualizer") === true
                onToggled: value => SettingsService.set("desktop.mediaVisualizer", value)
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

    // The share picker (shell/sharepicker): beside the recording, the other
    // thing that hands the screen to someone.
    ScreenSharingSection { Layout.fillWidth: true }

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

    SettingsSection {
        Layout.fillWidth: true
        title: "System disk"
        scope: "drives.lowSpace"
        description: "The disk the system and your files are on: / and /home."
        SettingRow {
            Layout.fillWidth: true
            labelFills: true
            label: "Warn when it is almost full"
            hint: "Looks every 15 minutes and tells once, with a button to the System popup: below a tenth of the disk, at most 20 GiB and at least 5 GiB free"
            ShellToggle { focusOnTab: true; checked: DrivesService.lowSpaceEnabled; onToggled: value => SettingsService.set("drives.lowSpace", value) }
        }
    }

    // The assistant panel (shell/assistant): a model on this computer.
    AssistantSection { Layout.fillWidth: true }
}
