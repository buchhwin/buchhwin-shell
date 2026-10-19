import Quickshell
import QtQuick
import QtQuick.Layouts
import qs.theme
import qs.services
import qs.shell.components
import Quickshell.Io
import "../../../services/wallpaper/WallpaperLogic.js" as WallpaperLogic
import "../../../services/settings/LoginLogic.js" as LoginLogic

// Settings > Login Screen: how the SDDM greeter looks. The greeter runs as
// another user and cannot read these settings, so installing them copies them
// into the theme - which needs root and stays an explicit step.
ColumnLayout {
    id: root
    spacing: Metrics.pageGap

    // The wallpaper the greeter will get. Empty is "the one this session has",
    // which is what the installer already falls back to; a path pins it.
    readonly property string wallpaper: SettingsService.expandHome(SettingsService.value("login.wallpaper"))
    // Text for a terminal, with every path one word for the shell whatever
    // the file is called, and the installer of the tree this shell runs
    // from (LoginLogic).
    readonly property string installer: Paths.shellFile("install/system-install.sh")
    readonly property string command: LoginLogic.installCommand(root.installer, root.wallpaper)
    readonly property string removeCommand: LoginLogic.removeCommand(root.installer)

    // What the greeter is showing *now*, which is a copy made the last time
    // that command was run. Reading it is the point of this page: a stale copy
    // is invisible, which is why a wallpaper that had been changed weeks ago
    // read as one that could not be changed at all. Read only while the page
    // is open, the way the terminal page previews its prompt - and read again
    // on every open, since the panel keeps the page.
    property string installedAt: ""
    PageActivity { id: activity }
    Process {
        running: activity.active
        command: ["sh", "-c",
                  "stat -c %y /usr/share/sddm/themes/buchhwin/background.* 2>/dev/null | head -1 | cut -c1-16"]
        stdout: StdioCollector { onStreamFinished: root.installedAt = text.trim() }
    }
    readonly property var fontFamilies: {
        const seen = {}
        return Qt.fontFamilies().filter(name => !name.startsWith(".") && !seen[name] && (seen[name] = true))
            .map(family => ({ value: family, label: family }))
    }
    readonly property string accent: SettingsService.value("login.accent")
    readonly property string font: SettingsService.value("login.font")

    SettingsSection {
        Layout.fillWidth: true
        title: "Look"
        description: "The login screen follows the lock screen's design, and shows whichever wallpaper you choose below."

        // Said plainly rather than implied: this screen is a separate
        // application that cannot load the shell's blocks, so it has the
        // clock, the date and the keyboard layout and nothing else. A lock
        // screen arranged with weather and a player shows neither here, and
        // that is not a bug to go looking for.
        ShellText {
            Layout.fillWidth: true
            text: "It follows what you arranged on the lock screen: the clock, the date and the keyboard layout, in that order. The rest of the lock screen's blocks do not exist here."
            role: "small"; muted: true; wrapMode: Text.Wrap
        }

        SettingRow {
            label: "Wallpaper"
            // Until the command runs, the login screen keeps the copy it has,
            // which is why one changed long ago can look as though it cannot
            // be changed at all.
            hint: "Copied into the installed theme by the command below: the greeter runs as its own user and cannot read your home. Until then the login screen keeps its old copy."
            ShellSelect {
                focusOnTab: true
                Layout.fillWidth: true
                current: SettingsService.value("login.wallpaper")
                placeholder: "Same as the desktop"
                options: [{ value: "", label: "Same as the desktop" }]
                    .concat(WallpaperService.images.map(path => ({
                        value: path, label: WallpaperLogic.displayName(path)
                    })))
                onSelected: value => SettingsService.set("login.wallpaper", value)
            }
        }
        ShellText {
            Layout.fillWidth: true
            visible: root.installedAt.length > 0
            text: "The login screen is showing a copy made on " + root.installedAt + "."
            role: "caption"
            muted: true
            wrapMode: Text.Wrap
        }
        SettingRow {
            Layout.fillWidth: true
            labelFills: true
            label: "Blur the background"
            hint: "Like the lock screen does"
            ShellToggle {
                focusOnTab: true
                checked: SettingsService.value("login.blur")
                onToggled: value => SettingsService.set("login.blur", value)
            }
        }
        SettingRow {
            label: "Accent"
            hint: "Behind the avatar initial and on a confirming power button"
            SegmentedControl {
                focusOnTab: true
                Layout.fillWidth: true
                current: root.accent === "shell" ? "shell" : "custom"
                options: [{ value: "shell", label: "Shell accent" }, { value: "custom", label: "Own color" }]
                onSelected: value => SettingsService.set("login.accent", value === "shell" ? "shell" : SettingsService.accent)
            }
        }
        // The installer copies only #rrggbb into the theme and dropped
        // anything else without a word, the greeter keeping its default: the
        // field takes a hex color (a short one is written out), says so
        // otherwise, and stores nothing it would drop.
        SettingRow {
            label: "Accent color"
            visible: root.accent !== "shell"
            StoredTextField {
                id: accentField
                focusOnTab: true
                Layout.fillWidth: true
                icon: "󰏘"
                placeholder: "#4f8ff7" // style: an example in a placeholder, not a colour the shell uses
                storedText: root.accent === "shell" ? "" : root.accent
                error: text.trim().length > 0 && !PanelStyleService.normalizeHex(text).length
                onCommit: value => {
                    const hex = PanelStyleService.normalizeHex(value)
                    if (hex.length) SettingsService.set("login.accent", hex)
                }
            }
        }
        // Also for a value stored before the field checked it ("teal", "#4f8",
        // an empty one), which the installer drops just the same.
        ShellText {
            Layout.fillWidth: true
            visible: root.accent !== "shell" && (accentField.error || !/^#[0-9a-fA-F]{6}$/.test(root.accent))
            text: "Enter a hex color like #4f8ff7 or #48f; the login screen takes nothing else."
            role: "small"
            color: Colors.danger
            wrapMode: Text.Wrap
        }
        SettingRow {
            label: "Font"
            SegmentedControl {
                focusOnTab: true
                Layout.fillWidth: true
                current: root.font === "shell" ? "shell" : "custom"
                options: [{ value: "shell", label: "Shell font" }, { value: "custom", label: "Own font" }]
                onSelected: value => SettingsService.set("login.font", value === "shell" ? "shell" : SettingsService.fontFamily)
            }
        }
        SettingRow {
            label: "Font family"
            visible: root.font !== "shell"
            ShellSelect {
                focusOnTab: true
                Layout.fillWidth: true
                options: root.fontFamilies
                current: root.font
                previewFonts: true
                onSelected: value => SettingsService.set("login.font", value)
            }
        }
        SettingRow {
            label: "Date"
            hint: "Above the clock"
            SegmentedControl {
                focusOnTab: true
                Layout.fillWidth: true
                current: SettingsService.value("login.dateFormat")
                options: [{ value: "dddd, d MMMM", label: "Friday, 18 September" },
                          { value: "dddd, d MMM", label: "Friday, 18 Sept" },
                          { value: "d MMMM yyyy", label: "18 September 2026" },
                          { value: "dd.MM.yyyy", label: "18.09.2026" }]
                onSelected: value => SettingsService.set("login.dateFormat", value)
            }
        }
    }

    SettingsSection {
        Layout.fillWidth: true
        title: "Apply"
        description: "The greeter runs as the sddm user and cannot read your settings, so they are copied into the installed theme. That needs root, so it stays a step you run yourself."

        // The copy button beside the command, as a code block has it: the
        // installer's absolute path wraps the line, and a button in a row of
        // its own under it ended below the card's edge.
        RowLayout {
            Layout.fillWidth: true
            spacing: Metrics.spaceSm
            ShellText {
                Layout.fillWidth: true
                Layout.alignment: Qt.AlignVCenter
                text: root.command
                font.family: Typography.monoFamily
                wrapMode: Text.Wrap
            }
            ShellButton {
                Layout.alignment: Qt.AlignTop
                focusOnTab: true
                icon: Icons.copy
                variant: "ghost"
                compact: true
                toolTip: "Copy command"
                onClicked: Quickshell.clipboardText = root.command
            }
        }
        // The way back is a command too, copied the same way, rather than a
        // flag to be typed onto the line above by hand.
        ShellText {
            Layout.fillWidth: true
            text: "To undo it, run this; it puts the previous theme and display manager back. From a TTY you can also remove /etc/sddm.conf.d/buchhwin-theme.conf."
            role: "caption"
            wrapMode: Text.Wrap
        }
        RowLayout {
            Layout.fillWidth: true
            spacing: Metrics.spaceSm
            ShellText {
                Layout.fillWidth: true
                Layout.alignment: Qt.AlignVCenter
                text: root.removeCommand
                font.family: Typography.monoFamily
                wrapMode: Text.Wrap
            }
            ShellButton {
                Layout.alignment: Qt.AlignTop
                focusOnTab: true
                icon: Icons.copy
                variant: "ghost"
                compact: true
                toolTip: "Copy undo command"
                onClicked: Quickshell.clipboardText = root.removeCommand
            }
        }
    }
}
