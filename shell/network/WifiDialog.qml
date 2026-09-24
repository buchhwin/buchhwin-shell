import Quickshell
import QtQuick
import QtQuick.Layouts
import qs.theme
import qs.services
import qs.shell.components

// Password dialog for secured Wi-Fi networks, hidden networks and the hotspot.
// PanelService args: { ssid, security } | { hidden: true } | { hotspot: true }.
ShellPanel {
    id: root
    keyForward: root.hotspot || root.hidden ? nameField : secretField
    panelId: "wifiPassword"
    placement: "center"
    cardWidth: Metrics.notificationCenterWidth
    scrimColor: Colors.scrim

    readonly property bool hotspot: PanelService.args.hotspot === true
    readonly property bool hidden: PanelService.args.hidden === true
    readonly property bool busy: NetworkService.helperState.length > 0
    property bool showSecret: false

    function submit() {
        const name = root.hotspot || root.hidden ? nameField.text.trim() : (PanelService.args.ssid || "")
        if (!name.length || secretField.text.length < 8 || root.busy) return
        if (root.hotspot) NetworkService.startHotspot(name, secretField.text)
        else NetworkService.connectWithPassword(name, secretField.text, root.hidden)
    }

    onWantedChanged: {
        if (wanted) {
            NetworkService.helperError = ""
            showSecret = false
            nameField.text = hotspot ? "buchhwin-hotspot" : ""
            secretField.text = ""
        } else {
            secretField.text = ""
        }
    }

    ColumnLayout {
        width: parent.width
        spacing: Metrics.spaceMd

        PanelHeader {
            Layout.fillWidth: true
            role: "title"
            icon: root.hotspot ? "󰀂" : "󰤪"
            title: root.hotspot ? "Start hotspot" : root.hidden ? "Hidden network" : (PanelService.args.ssid || "")
            subtitle: root.hotspot ? "Shares the internet connection over Wi-Fi"
                : root.hidden ? "Network name and password"
                : "Password required · " + (PanelService.args.security || "WPA2")
        }

        CardSection {
            Layout.fillWidth: true
            spacing: Metrics.spaceSm

            ShellTextField {
                focusOnTab: true
                id: nameField
                Layout.fillWidth: true
                visible: root.hotspot || root.hidden
                icon: "󰖩"
                placeholder: root.hotspot ? "Hotspot name" : "Network name (SSID)"
                onAccepted: secretField.focusInput()
            }

            RowLayout {
                Layout.fillWidth: true
                spacing: Metrics.spaceSm
                ShellTextField {
                    focusOnTab: true
                    id: secretField
                    Layout.fillWidth: true
                    icon: "󰌾"
                    placeholder: "Password (at least 8 characters)"
                    echoMode: root.showSecret ? TextInput.Normal : TextInput.Password
                    onAccepted: root.submit()
                }
                ShellButton {
                    focusOnTab: true
                    icon: root.showSecret ? Icons.conceal : Icons.reveal
                    variant: "ghost"
                    toolTip: root.showSecret ? "Hide" : "Show"
                    onClicked: root.showSecret = !root.showSecret
                }
            }

            ShellText {
                Layout.fillWidth: true
                visible: root.hotspot
                text: "While the hotspot is running, this device is not connected to any other Wi-Fi network."
                role: "small"; color: Colors.warning; wrapMode: Text.Wrap
            }
        }

        ShellText {
            Layout.fillWidth: true
            visible: NetworkService.helperError.length > 0
            text: NetworkService.helperError
            color: Colors.danger
            wrapMode: Text.Wrap
        }

        RowLayout {
            Layout.fillWidth: true
            spacing: Metrics.spaceSm
            ShellText {
                visible: root.busy
                text: root.hotspot ? "Starting hotspot …" : "Connecting …"
                role: "small"; muted: true
            }
            Item { Layout.fillWidth: true }
            ShellButton { focusOnTab: true; text: "Cancel"; variant: "ghost"; onClicked: PanelService.close("wifiPassword") }
            ShellButton {
                focusOnTab: true
                text: root.hotspot ? "Start" : "Connect"
                variant: "accent"
                enabledState: !root.busy && secretField.text.length >= 8 && (!(root.hotspot || root.hidden) || nameField.text.trim().length > 0)
                onClicked: root.submit()
            }
        }
    }
}
