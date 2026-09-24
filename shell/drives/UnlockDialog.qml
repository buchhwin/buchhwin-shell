import QtQuick
import QtQuick.Layouts
import qs.theme
import qs.services
import qs.shell.components

// Passphrase dialog for encrypted (LUKS) volumes, modelled on WifiDialog.
// PanelService args: { drive: DRIVE_ID, volume: VOLUME_ID }. The passphrase
// goes straight to DrivesService, which writes it to `udisksctl unlock
// --key-file /dev/stdin`; nothing keeps it, and the field is cleared as soon
// as it has been handed over or the dialog closes.
ShellPanel {
    id: root
    keyForward: secretField
    panelId: "driveUnlock"
    placement: "center"
    cardWidth: Metrics.notificationCenterWidth
    scrimColor: Colors.scrim

    readonly property var target: DrivesService.findVolume(PanelService.args.volume || "")
    readonly property var drive: target ? target.drive : null
    readonly property var volume: target ? target.volume : null
    readonly property bool busy: volume !== null && DrivesService.unlockingId === volume.id
    property bool showSecret: false
    property bool openAfter: true

    function submit() {
        if (root.busy || !root.volume || secretField.text.length === 0) return
        DrivesService.unlockVolume(root.drive, root.volume, secretField.text, root.openAfter)
        secretField.text = ""
    }

    onWantedChanged: {
        if (wanted) {
            DrivesService.unlockError = ""
            showSecret = false
            openAfter = true
            secretField.text = ""
        } else {
            secretField.text = ""
        }
    }

    // A volume that vanished (unplugged) leaves nothing to unlock.
    onVolumeChanged: if (wanted && volume === null) PanelService.close("driveUnlock")

    ColumnLayout {
        width: parent.width
        spacing: Metrics.spaceMd

        PanelHeader {
            Layout.fillWidth: true
            role: "title"
            icon: "󰌾"
            title: root.volume ? DrivesService.volumeTitle(root.volume) : "Encrypted volume"
            subtitle: root.drive ? "Encrypted · " + DrivesService.driveTitle(root.drive) : "Encrypted volume"
        }

        CardSection {
            Layout.fillWidth: true
            spacing: Metrics.spaceMd

            RowLayout {
                Layout.fillWidth: true
                spacing: Metrics.spaceSm
                ShellTextField {
                    focusOnTab: true
                    id: secretField
                    Layout.fillWidth: true
                    icon: "󰌆"
                    placeholder: "Passphrase"
                    echoMode: root.showSecret ? TextInput.Normal : TextInput.Password
                    onAccepted: root.submit()
                    onEscapePressed: if (!text.length) PanelService.close("driveUnlock")
                }
                ShellButton {
                    focusOnTab: true
                    icon: root.showSecret ? Icons.conceal : Icons.reveal
                    variant: "ghost"
                    toolTip: root.showSecret ? "Hide" : "Show"
                    onClicked: root.showSecret = !root.showSecret
                }
            }

            SettingRow {
                Layout.fillWidth: true
                labelFills: true
                label: "Open after unlocking"
                hint: "Mount the volume and show it in the file manager"
                ShellToggle { focusOnTab: true; checked: root.openAfter; onToggled: value => root.openAfter = value }
            }

            ShellText {
                Layout.fillWidth: true
                text: "The passphrase is not saved anywhere."
                role: "small"; muted: true; wrapMode: Text.Wrap
            }
        }

        ShellText {
            Layout.fillWidth: true
            visible: DrivesService.unlockError.length > 0
            text: DrivesService.unlockError
            color: Colors.danger
            wrapMode: Text.Wrap
        }

        RowLayout {
            Layout.fillWidth: true
            spacing: Metrics.spaceSm
            ShellText { visible: root.busy; text: "Unlocking …"; role: "small"; muted: true }
            Item { Layout.fillWidth: true }
            ShellButton { focusOnTab: true; text: "Cancel"; variant: "ghost"; onClicked: PanelService.close("driveUnlock") }
            ShellButton {
                focusOnTab: true
                text: "Unlock"
                variant: "accent"
                enabledState: !root.busy && secretField.text.length > 0 && root.volume !== null
                onClicked: root.submit()
            }
        }
    }
}
