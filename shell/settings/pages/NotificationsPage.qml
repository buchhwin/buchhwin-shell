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
            hint: "A Steam game or gamescope in front. The Gaming mode turns Do Not Disturb on by itself; Profiles sets that for each mode."
            ShellToggle { focusOnTab: true; checked: SettingsService.value("notifications.suppressGames"); onToggled: value => SettingsService.set("notifications.suppressGames", value) }
        }
        // NotificationService.screenShares: a share through the portal
        // (QuietLogic), not Hyprland's screencast event.
        SettingRow {
            Layout.fillWidth: true
            labelFills: true
            label: "Mute automatically while sharing the screen"
            hint: "A screen, window or region shared in a call or with OBS. An urgent one still shows its title, without the text."
            ShellToggle { focusOnTab: true; checked: SettingsService.value("notifications.suppressSharing"); onToggled: value => SettingsService.set("notifications.suppressSharing", value) }
        }
        SettingRow {
            Layout.fillWidth: true
            label: "Not muted in fullscreen"
            hint: "Window classes whose fullscreen window lets notifications through, separated by commas. Wfica is the Citrix desktop."
            StoredTextField {
                focusOnTab: true
                Layout.fillWidth: true
                placeholder: "Wfica"
                storedText: SettingsService.value("notifications.fullscreenExceptions")
                onCommit: value => SettingsService.set("notifications.fullscreenExceptions",
                                                       value.split(/[,\s]+/).filter(part => part.length).join(", "))
            }
        }
        SettingRow {
            Layout.fillWidth: true
            labelFills: true
            label: "Pop up on another screen instead"
            hint: "With a fullscreen window on one screen, notifications pop up on a screen without one rather than waiting."
            ShellToggle { focusOnTab: true; checked: SettingsService.value("notifications.fullscreenElsewhere"); onToggled: value => SettingsService.set("notifications.fullscreenElsewhere", value) }
        }
        SettingRow {
            Layout.fillWidth: true
            labelFills: true
            label: "Summary when Do Not Disturb ends"
            hint: "And when the automatic muting ends: one notice says how many came meanwhile, with Show."
            ShellToggle { focusOnTab: true; checked: SettingsService.value("notifications.missedSummary"); onToggled: value => SettingsService.set("notifications.missedSummary", value) }
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
            Layout.fillWidth: true
            labelFills: true
            label: "Play a sound"
            hint: "A short sound for a notification that pops up, never in Do Not Disturb or while muted. Off per app below."
            ShellToggle { focusOnTab: true; checked: SettingsService.value("notifications.sounds"); onToggled: value => SettingsService.set("notifications.sounds", value) }
        }
    }

    // Off by default: the words of every notification on disk
    // (NotificationService.keepsHistory, SavedLogic).
    SettingsSection {
        Layout.fillWidth: true
        title: "History"
        scope: "notifications.keepHistory"
        SettingRow {
            Layout.fillWidth: true
            labelFills: true
            label: "Keep notifications across restarts"
            hint: "The newest 50, without pictures or buttons, in a file only you can read. They show under Earlier. Turning it off deletes the file."
            ShellToggle { focusOnTab: true; checked: SettingsService.value("notifications.keepHistory"); onToggled: value => SettingsService.set("notifications.keepHistory", value) }
        }
    }

    // The user's own countdowns (TimerService): their end is shown through
    // every Do Not Disturb, and heard with this on.
    SettingsSection {
        Layout.fillWidth: true
        title: "Timers"
        SettingRow {
            Layout.fillWidth: true
            labelFills: true
            label: "Ring when a timer runs out"
            hint: "The alarm clock sound, in Do Not Disturb too: you started the timer. A Focus session rings the same way at its end."
            ShellToggle { focusOnTab: true; checked: SettingsService.value("timer.sound"); onToggled: value => SettingsService.set("timer.sound", value) }
        }
    }

    // Per app: the rule the notification centre's bell toggles (Normal,
    // Muted) and the one set only here (Always urgent). A rule used to be
    // visible only over its app's group in the centre, so a muted app with
    // nothing in the history stayed muted where nobody could see it.
    SettingsSection {
        Layout.fillWidth: true
        title: "Apps"
        hint: "Muted apps never pop up. Always urgent ones pop up through everything but a Do Not Disturb you turned on yourself, Never muted ones through that too. Teams and Outlook are apps of their own, not the browser's."
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
                // The app's sound, while sounds are on (NotificationService.appSound).
                ShellButton {
                    readonly property bool sounding: NotificationService.appSound(appRow.modelData)
                    visible: SettingsService.value("notifications.sounds") === true
                    focusOnTab: true
                    compact: true
                    icon: sounding ? "\u{f057e}" : "\u{f0581}"
                    variant: sounding ? "ghost" : "surface"
                    toolTip: sounding ? "Sound on · click to turn it off for this app" : "Sound off · click to turn it on"
                    onClicked: NotificationService.setAppSound(appRow.modelData, !sounding)
                }
                SegmentedControl {
                    focusOnTab: true
                    Layout.fillWidth: true
                    current: appRow.row.rule
                    options: [{ value: "default", label: "Normal" }, { value: "mute", label: "Muted" },
                              { value: "critical", label: "Always urgent" }, { value: "always", label: "Never muted" }]
                    onSelected: value => NotificationService.setAppRule(appRow.modelData, value)
                }
            }
        }
    }
}
