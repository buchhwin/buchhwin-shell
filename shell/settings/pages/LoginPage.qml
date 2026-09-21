import Quickshell
import QtQuick
import QtQuick.Layouts
import qs.theme
import qs.services
import qs.shell.components
import Quickshell.Io
import "../../../services/wallpaper/WallpaperLogic.js" as WallpaperLogic

// Settings > Login Screen: how the SDDM greeter looks. The greeter runs as
// another user and cannot read these settings, so installing them copies them
// into the theme - which needs root and stays an explicit step.
ColumnLayout {
    id: root
    spacing: Metrics.spaceLg

    // The wallpaper the greeter will get. Empty is "the one this session has",
    // which is what the installer already falls back to; a path pins it.
    readonly property string wallpaper: SettingsService.expandHome(SettingsService.value("login.wallpaper"))
    readonly property string command: "sudo install/system-install.sh --sddm-theme"
        + (root.wallpaper.length ? " --wallpaper '" + root.wallpaper + "'" : "")

    // What the greeter is showing *now*, which is a copy made the last time
    // that command was run. Reading it is the point of this page: a stale copy
    // is invisible, which is why a wallpaper that had been changed weeks ago
    // read as one that could not be changed at all. Read only while the page
    // is open, the way the terminal page previews its prompt.
    property string installedAt: ""
    Process {
        running: root.visible
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

        SettingRow {
            Layout.fillWidth: true
            labelFills: true
            label: "It follows what you arranged on the lock screen"
            // Said plainly rather than implied: this screen is a separate
            // application that cannot load the shell's blocks, so it has the
            // clock, the date and the keyboard layout and nothing else. A
            // lock screen arranged with weather and a player shows neither
            // here, and that is not a bug to go looking for.
            hint: "The clock, the date and the keyboard layout, in that order - the rest of the lock screen's blocks do not exist here"
        }

        SettingRow {
            label: "Wallpaper"
            hint: "The greeter runs as its own user and cannot read your home directory, so whichever picture you choose is copied into the installed theme by the command below. Until you run it, the login screen keeps the copy it already has - which is why one that was changed long ago can look as though it cannot be changed at all."
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
        SettingRow {
            label: "Accent color"
            visible: root.accent !== "shell"
            ShellTextField {
                focusOnTab: true
                Layout.fillWidth: true
                icon: "󰏘"
                placeholder: "#4f8ff7" // style: an example in a placeholder, not a colour the shell uses
                text: root.accent === "shell" ? "" : root.accent
                onAccepted: SettingsService.set("login.accent", text)
            }
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

        ShellText {
            Layout.fillWidth: true
            text: root.command
            font.family: Typography.monoFamily
            wrapMode: Text.Wrap
        }
        RowLayout {
            Layout.fillWidth: true
            spacing: Metrics.spaceSm
            ShellButton {
                focusOnTab: true
                icon: "󰆏"
                text: "Copy command"
                onClicked: Quickshell.clipboardText = root.command
            }
        }
        ShellText {
            Layout.fillWidth: true
            text: "Undo is the same script with --sddm-theme-remove. From a TTY you can also remove /etc/sddm.conf.d/buchhwin-theme.conf."
            role: "caption"
            wrapMode: Text.Wrap
        }
    }
}
