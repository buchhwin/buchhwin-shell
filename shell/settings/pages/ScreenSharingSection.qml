import Quickshell
import Quickshell.Io
import QtQuick
import QtQuick.Layouts
import qs.theme
import qs.services
import qs.shell.components
import "../../../services/sharepicker/SharePickerLogic.js" as Logic

// Settings > Desktop extras > Screen sharing: the shell's share picker
// (shell/sharepicker/SharePickerPanel.qml) in place of the portal's plain
// dialog. The portal runs whatever its own configuration names, a file of
// the user's outside this repository - the section reads it (only while on
// screen) and says whether it names the shell's picker, and if not, the
// lines to put there. It never writes the file: restarting the portal ends
// a share that is running, which is the user's moment to choose.
SettingsSection {
    id: section
    title: "Screen sharing"
    scope: "sharePicker.enabled"
    hint: "When an app asks to share the screen, the shell asks which screen, window or region, with live previews, on the screen you are looking at. On any error the portal's own picker opens instead."

    readonly property string configPath: (Quickshell.env("XDG_CONFIG_HOME") || Paths.home + "/.config") + "/hypr/xdph.conf"
    readonly property string scriptPath: Paths.script("share-picker.sh")
    readonly property string snippet: Logic.configSnippet(scriptPath)
    readonly property string restartCommand: "systemctl --user restart xdg-desktop-portal-hyprland"
    // "" until read, then the picker the portal's configuration names ("" for
    // its own).
    property bool configRead: false
    property string configured: ""
    readonly property bool usesShell: Logic.isShellPicker(configured)

    function readConfig() {
        if (!reader.running) reader.running = true
    }
    PageActivity { onOpened: section.readConfig() }
    Process {
        id: reader
        command: ["sh", "-c", "test -f \"$1\" && cat -- \"$1\"", "sh", section.configPath]
        stdout: StdioCollector { id: readerOut }
        onExited: {
            section.configured = Logic.configuredPicker(readerOut.text)
            section.configRead = true
        }
    }

    SettingRow {
        Layout.fillWidth: true
        labelFills: true
        label: "Use the shell's picker"
        hint: "Off, the portal's own picker opens every time. Restarting the portal ends a share that is running."
        ShellToggle {
            focusOnTab: true
            accessibleName: "Use the shell's picker"
            checked: SettingsService.value("sharePicker.enabled") !== false
            onToggled: value => SettingsService.set("sharePicker.enabled", value)
        }
    }

    ShellText {
        Layout.fillWidth: true
        visible: section.configRead
        text: section.usesShell ? "The portal uses the shell's picker."
            : section.configured.length ? "The portal uses another picker (" + section.configured + "). For the shell's, put these lines in " + section.configPath + " instead, then restart the portal:"
            : "The portal uses its own picker. For the shell's, put these lines in " + section.configPath + ", then restart the portal:"
        role: "small"
        muted: true
        wrapMode: Text.Wrap
    }

    Repeater {
        model: section.configRead && !section.usesShell ? [section.snippet.trim(), section.restartCommand] : []
        Rectangle {
            id: block
            required property string modelData
            Layout.fillWidth: true
            implicitHeight: Math.max(lines.implicitHeight, copy.implicitHeight) + Metrics.spaceSm * 2
            radius: Metrics.radiusInner
            color: Colors.sunken
            border.width: Metrics.borderWidth
            border.color: Colors.borderInner
            TextEdit {
                id: lines
                anchors.left: parent.left
                anchors.right: copy.left
                anchors.verticalCenter: parent.verticalCenter
                anchors.margins: Metrics.spaceSm
                text: block.modelData
                textFormat: TextEdit.PlainText
                readOnly: true
                selectByMouse: true
                wrapMode: TextEdit.WrapAnywhere
                color: Colors.text
                selectionColor: Colors.accentSoft
                selectedTextColor: Colors.text
                font.family: Typography.monoFamily
                font.pixelSize: Typography.smallSize
                renderType: Typography.renderType
            }
            ShellButton {
                id: copy
                anchors.right: parent.right
                anchors.verticalCenter: parent.verticalCenter
                anchors.rightMargin: Metrics.spaceXs
                focusOnTab: true
                icon: Icons.copy
                compact: true
                variant: "ghost"
                toolTip: "Copy"
                onClicked: Quickshell.clipboardText = block.modelData
            }
        }
    }

    RowLayout {
        spacing: Metrics.spaceSm
        ShellButton {
            focusOnTab: true
            icon: Icons.share
            text: "Preview"
            toolTip: "The picker as it looks now; choosing in it shares nothing"
            onClicked: SharePickerService.openPreview()
        }
        ShellButton {
            focusOnTab: true
            icon: Icons.refresh
            text: "Check again"
            variant: "ghost"
            onClicked: section.readConfig()
        }
    }
}
