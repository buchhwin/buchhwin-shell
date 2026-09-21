import Quickshell
import Quickshell.Io
import QtQuick
import QtQuick.Layouts
import qs.theme
import qs.services
import qs.shell.components

ColumnLayout {
    id: root
    spacing: Metrics.spaceLg
    property var info: ({})

    Process {
        running: true
        command: ["sh", "-c", [
            ". /etc/os-release 2>/dev/null; echo \"os=$PRETTY_NAME\"",
            "echo \"kernel=$(uname -r)\"",
            "echo \"host=$(cat /etc/hostname 2>/dev/null || uname -n)\"",
            "echo \"hyprland=$(Hyprland --version 2>/dev/null | head -n1 | cut -d' ' -f2)\"",
            "echo \"quickshell=$(quickshell --version 2>/dev/null | head -n1 | sed 's/^quickshell //; s/,.*//')\"",
            "echo \"cpu=$(grep -m1 'model name' /proc/cpuinfo | cut -d: -f2- | sed 's/^ //')\"",
            "echo \"gpu=$(lspci 2>/dev/null | grep -Ei 'vga|3d|display' | head -n1 | cut -d: -f3- | sed 's/^ //')\"",
            "echo \"ram=$(awk '/MemTotal/ {printf \"%.1f GiB\", $2/1048576}' /proc/meminfo)\"",
            "echo \"session=${XDG_SESSION_DESKTOP:-unknown}\""
        ].join("; ")]
        stdout: StdioCollector {
            onStreamFinished: {
                const result = {}
                for (const line of text.split("\n")) {
                    const index = line.indexOf("=")
                    if (index > 0) result[line.slice(0, index)] = line.slice(index + 1)
                }
                root.info = result
            }
        }
    }

    SettingsSection {
        Layout.fillWidth: true
        title: "buchhwin-shell"
        description: "Custom desktop shell on Fedora, Hyprland and Quickshell"

        SettingRow {
            Layout.fillWidth: true
            labelFills: true
            label: "Show the tour again"
            hint: "The six keys this desktop is built on"
            ShellButton {
                icon: Icons.forward
                text: "Start"
                variant: "surface"
                compact: true
                focusOnTab: true
                onClicked: PanelService.open("welcome")
            }
        }

        Repeater {
            model: [
                { key: "os", label: "System" }, { key: "hyprland", label: "Hyprland" }, { key: "quickshell", label: "Quickshell" },
                { key: "kernel", label: "Kernel" }, { key: "cpu", label: "Processor" }, { key: "gpu", label: "Graphics" },
                { key: "ram", label: "Memory" }, { key: "host", label: "Device name" }, { key: "session", label: "Session" }
            ]
            SettingRow {
                required property var modelData
                Layout.fillWidth: true
                label: modelData.label
                ShellText { Layout.fillWidth: true; text: root.info[modelData.key] || " …"; muted: true; wrapMode: Text.Wrap }
            }
        }
    }
}
