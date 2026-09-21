import Quickshell
import QtQuick
import QtQuick.Layouts
import qs.theme
import qs.services
import qs.shell.components

// Bluetooth pairing requests from the shell's BlueZ agent: compare a code,
// enter a PIN or passkey, allow a connection or a service, or show a code to
// type on the other device. Closing the dialog declines the request.
ShellPanel {
    id: root
    keyForward: needsInput ? codeField : null
    panelId: "pairing"
    placement: "center"
    cardWidth: Metrics.notificationCenterWidth
    scrimColor: Colors.scrim

    readonly property var request: BluetoothService.request
    readonly property var display: BluetoothService.displayCode
    readonly property string kind: request ? request.kind : display ? "display" : ""
    readonly property string deviceName: request ? request.name : display ? display.name : ""
    readonly property bool needsInput: kind === "pin" || kind === "passkey"

    function accept() {
        if (kind === "display") { BluetoothService.displayCode = null; PanelService.close("pairing"); return }
        if (needsInput && !codeField.text.length) return
        BluetoothService.respond(true, codeField.text)
    }

    onWantedChanged: {
        if (wanted) {
            codeField.text = ""
        } else {
            // Closed by Escape or a click outside: decline what is still open.
            if (BluetoothService.request) BluetoothService.respond(false, "")
            BluetoothService.displayCode = null
        }
    }
    onKindChanged: {
        codeField.text = ""
    }

    ColumnLayout {
        width: parent.width
        spacing: Metrics.spaceMd

        PanelHeader {
            Layout.fillWidth: true
            role: "title"
            icon: "󰂱"
            title: "Bluetooth pairing"
            subtitle: root.deviceName
        }

        CardSection {
            Layout.fillWidth: true
            spacing: Metrics.spaceMd

            ShellText {
                Layout.fillWidth: true
                wrapMode: Text.Wrap
                text: root.kind === "confirm" ? "Does “" + root.deviceName + "” show the same code?"
                    : root.kind === "pin" ? "Enter the PIN for “" + root.deviceName + "” (often 0000 or 1234)."
                    : root.kind === "passkey" ? "Enter the six-digit code shown on “" + root.deviceName + "”."
                    : root.kind === "authorize" ? "“" + root.deviceName + "” wants to pair with this device."
                    : root.kind === "service" ? "“" + root.deviceName + "” wants to use a service on this device."
                    : root.kind === "display" ? "Enter this code on “" + root.deviceName + "” and confirm it there."
                    : ""
            }

            Text {
                Layout.alignment: Qt.AlignHCenter
                visible: (root.kind === "confirm" || root.kind === "display") && text.length > 0
                text: {
                    const code = root.kind === "display" ? (root.display ? root.display.passkey : "") : (root.request ? root.request.passkey || "" : "")
                    return code.length === 6 ? code.slice(0, 3) + " " + code.slice(3) : code
                }
                color: Colors.text
                font.family: Typography.monoFamily
                font.pixelSize: Typography.displaySize * 0.7
                font.weight: Typography.light
                font.letterSpacing: Typography.captionTracking * 2
                renderType: Typography.renderType
            }

            ShellTextField {
                id: codeField
                Layout.fillWidth: true
                visible: root.needsInput
                icon: "󰌆"
                placeholder: root.kind === "passkey" ? "Code" : "PIN"
                onAccepted: root.accept()
            }
        }

        RowLayout {
            Layout.fillWidth: true
            spacing: Metrics.spaceSm
            ShellText {
                visible: root.request !== null && root.request.preview === true
                text: "Preview"
                role: "caption"
            }
            Item { Layout.fillWidth: true }
            ShellButton {
                visible: root.kind !== "display"
                text: "Decline"; variant: "ghost"
                onClicked: BluetoothService.respond(false, "")
            }
            ShellButton {
                text: root.kind === "display" ? "Done" : root.kind === "confirm" ? "Pair" : root.kind === "authorize" || root.kind === "service" ? "Allow" : "Confirm"
                variant: "accent"
                enabledState: !root.needsInput || codeField.text.length > 0
                onClicked: root.accept()
            }
        }
    }
}
