import QtQuick
import QtQuick.Layouts
import qs.theme
import qs.services
import qs.shell.components

// Removable drives: one card per drive with its volumes (open, mount, unmount,
// unlock and lock for encrypted volumes) and Eject, which unmounts and locks
// everything and powers the drive off. MTP phones follow in their own card.
ColumnLayout {
    id: root
    spacing: Metrics.panelGap

    readonly property bool empty: DrivesService.drives.length === 0 && DrivesService.phones.length === 0

    ShellCard {
        Layout.fillWidth: true
        visible: root.empty
        implicitHeight: emptyRow.implicitHeight + Metrics.spaceLg * 2
        EmptyState {
            id: emptyRow
            anchors.fill: parent
            anchors.margins: Metrics.spaceLg
            row: true
            icon: "󰋊"
            title: DrivesService.available ? "No removable drives" : "Drives are unavailable"
            description: DrivesService.available ? "USB sticks, SD cards, external disks and phones appear here when you connect them"
                : "UDisks2 is not running, so drives cannot be listed"
        }
    }

    ScrollList {
        Layout.fillWidth: true
        visible: !root.empty
        card: false
        maxHeight: 460

        Repeater {
            model: DrivesService.drives
            ShellCard {
                id: card
                required property var modelData
                readonly property bool busy: DrivesService.isBusy(modelData)
                width: parent.width
                implicitHeight: cardColumn.implicitHeight + Metrics.spaceMd * 2

                ColumnLayout {
                    id: cardColumn
                    anchors.fill: parent
                    anchors.margins: Metrics.spaceMd
                    spacing: Metrics.spaceXs

                    RowLayout {
                        Layout.fillWidth: true
                        Layout.leftMargin: Metrics.spaceXs
                        spacing: Metrics.spaceMd
                        ShellIcon {
                            glyph: DrivesService.icon(card.modelData)
                            size: Metrics.iconLg
                            color: DrivesService.anyMounted(card.modelData) ? Colors.accentForeground : Colors.mutedText
                        }
                        ColumnLayout {
                            Layout.fillWidth: true
                            spacing: 0
                            ShellText { Layout.fillWidth: true; text: DrivesService.driveTitle(card.modelData); role: "bodyLarge" }
                            ShellText { Layout.fillWidth: true; text: DrivesService.driveSubtitle(card.modelData); role: "small"; muted: true }
                        }
                        ShellButton {
                            icon: "󰇪"
                            text: card.busy ? DrivesService.busy[card.modelData.id] : "Eject"
                            compact: true
                            enabledState: !card.busy
                            toolTip: "Unmount and power off, then unplug"
                            onClicked: DrivesService.eject(card.modelData)
                        }
                    }

                    Repeater {
                        model: card.modelData.volumes
                        ListRow {
                            id: row
                            required property var modelData
                            readonly property bool isMounted: DrivesService.mounted(modelData)
                            readonly property bool isLocked: DrivesService.locked(modelData)
                            Layout.fillWidth: true
                            icon: row.isLocked ? "󰌾" : isMounted ? "󰉖" : Icons.folder
                            active: isMounted
                            title: DrivesService.volumeTitle(modelData)
                            subtitle: DrivesService.volumeSubtitle(modelData)
                            onClicked: DrivesService.openVolume(card.modelData, modelData)

                            RowLayout {
                                spacing: Metrics.spaceXs
                                ShellButton {
                                    visible: !row.isLocked
                                    text: row.isMounted ? "Unmount" : "Mount"
                                    compact: true; variant: "ghost"
                                    enabledState: !card.busy
                                    onClicked: row.isMounted ? DrivesService.unmountVolume(card.modelData, row.modelData)
                                        : DrivesService.mountVolume(card.modelData, row.modelData)
                                }
                                ShellButton {
                                    visible: row.modelData.encrypted && !row.isLocked
                                    text: "Lock"
                                    compact: true; variant: "ghost"
                                    enabledState: !card.busy
                                    toolTip: "Unmount and close the encrypted volume"
                                    onClicked: DrivesService.lockVolume(card.modelData, row.modelData)
                                }
                                ShellButton {
                                    icon: row.isLocked ? "󰌿" : "󰝰"
                                    text: row.isLocked ? "Unlock …" : "Open"
                                    compact: true; variant: "accent"
                                    enabledState: !card.busy
                                    onClicked: DrivesService.openVolume(card.modelData, row.modelData)
                                }
                            }
                        }
                    }
                }
            }
        }

        // MTP phones: gvfs mounts them, UDisks2 never sees them.
        Repeater {
            model: DrivesService.phones
            ShellCard {
                id: phoneCard
                required property var modelData
                readonly property bool busy: DrivesService.isBusy(modelData)
                width: parent.width
                implicitHeight: phoneRow.implicitHeight + Metrics.spaceMd * 2

                RowLayout {
                    id: phoneRow
                    anchors.fill: parent
                    anchors.margins: Metrics.spaceMd
                    anchors.leftMargin: Metrics.spaceMd + Metrics.spaceXs
                    spacing: Metrics.spaceMd
                    ShellIcon {
                        glyph: DrivesService.phoneIcon()
                        size: Metrics.iconLg
                        color: phoneCard.modelData.mounted ? Colors.accentForeground : Colors.mutedText
                    }
                    ColumnLayout {
                        Layout.fillWidth: true
                        spacing: 0
                        ShellText { Layout.fillWidth: true; text: DrivesService.phoneTitle(phoneCard.modelData); role: "bodyLarge" }
                        ShellText {
                            Layout.fillWidth: true
                            text: DrivesService.phoneSubtitle(phoneCard.modelData)
                            role: "small"; muted: true; wrapMode: Text.Wrap
                        }
                    }
                    ShellButton {
                        visible: phoneCard.modelData.mounted
                        text: "Unmount"; compact: true; variant: "ghost"
                        enabledState: !phoneCard.busy
                        onClicked: DrivesService.unmountPhone(phoneCard.modelData)
                    }
                    ShellButton {
                        icon: "󰝰"; text: "Open"; compact: true; variant: "accent"
                        enabledState: !phoneCard.busy
                        onClicked: DrivesService.openPhone(phoneCard.modelData)
                    }
                }
            }
        }
    }

    // gvfs-mtp is what makes phones visible at all.
    ShellText {
        Layout.fillWidth: true
        Layout.leftMargin: Metrics.spaceSm
        visible: !DrivesService.mtpAvailable
        text: "Phones are not listed: the gvfs-mtp package is missing."
        role: "caption"; color: Colors.warning
        wrapMode: Text.Wrap
    }

    ShellText {
        Layout.fillWidth: true
        Layout.leftMargin: Metrics.spaceSm
        visible: DrivesService.message.length > 0
        text: DrivesService.message
        role: "caption"
        color: DrivesService.messageError ? Colors.danger : Colors.mutedText
        wrapMode: Text.Wrap
    }

    ShellButton {
        icon: Icons.settings; text: "Drive settings"; variant: "ghost"; compact: true
        onClicked: PanelService.open("settings", { page: "desktop" })
    }
}
