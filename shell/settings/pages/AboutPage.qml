import Quickshell
import QtQuick
import QtQuick.Layouts
import qs.theme
import qs.services
import qs.shell.components

ColumnLayout {
    id: root
    spacing: Metrics.pageGap
    // Read once per session and kept by the service: the page is built
    // again on every visit, the versions and the hardware are not.
    readonly property var info: SystemInfoService.info
    Component.onCompleted: SystemInfoService.load()

    SettingsSection {
        Layout.fillWidth: true
        title: "buchhwin-shell"
        description: "Custom desktop shell on Hyprland and Quickshell, for Fedora, openSUSE Leap and Arch Linux"

        SettingRow {
            Layout.fillWidth: true
            labelFills: true
            label: "Show the tour again"
            hint: "The six keys this desktop is built on"
            // The chevron after the word, where it reads as going on.
            ShellButton {
                trailingIcon: Icons.forward
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
