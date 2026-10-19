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
    spacing: Metrics.pageGap

    readonly property bool empty: DrivesService.drives.length === 0 && DrivesService.phones.length === 0
    // At the control center's narrowest (360) Unmount, Lock and Open beside
    // a volume left its name one "…" wide. Below the compact width the
    // actions go under the name, where they have the row to themselves.
    readonly property bool narrow: width < Metrics.compactWidth
    // Under the name: the row's own inset, its icon column and the gap after
    // it (ListRow), so the buttons start where the title does.
    readonly property real underNameInset: Metrics.spaceLg + Metrics.iconLg + Metrics.spaceMd

    component VolumeActions: RowLayout {
        id: volumeActions
        required property var drive
        required property var volume
        property bool busy: false
        readonly property bool isMounted: DrivesService.mounted(volume)
        readonly property bool isLocked: DrivesService.locked(volume)
        spacing: Metrics.spaceXs
        ShellButton {
            visible: !volumeActions.isLocked
            text: volumeActions.isMounted ? "Unmount" : "Mount"
            compact: true; variant: "ghost"
            enabledState: !volumeActions.busy
            onClicked: volumeActions.isMounted ? DrivesService.unmountVolume(volumeActions.drive, volumeActions.volume)
                : DrivesService.mountVolume(volumeActions.drive, volumeActions.volume)
        }
        ShellButton {
            visible: volumeActions.volume.encrypted && !volumeActions.isLocked
            text: "Lock"
            compact: true; variant: "ghost"
            enabledState: !volumeActions.busy
            toolTip: "Unmount and close the encrypted volume"
            onClicked: DrivesService.lockVolume(volumeActions.drive, volumeActions.volume)
        }
        ShellButton {
            icon: volumeActions.isLocked ? "󰌿" : "󰝰"
            text: volumeActions.isLocked ? "Unlock …" : "Open"
            compact: true; variant: "accent"
            enabledState: !volumeActions.busy
            onClicked: DrivesService.openVolume(volumeActions.drive, volumeActions.volume)
        }
    }

    component PhoneActions: RowLayout {
        id: phoneActions
        required property var phone
        property bool busy: false
        spacing: Metrics.spaceXs
        ShellButton {
            visible: phoneActions.phone.mounted
            text: "Unmount"; compact: true; variant: "ghost"
            enabledState: !phoneActions.busy
            onClicked: DrivesService.unmountPhone(phoneActions.phone)
        }
        ShellButton {
            icon: "󰝰"; text: "Open"; compact: true; variant: "accent"
            enabledState: !phoneActions.busy
            onClicked: DrivesService.openPhone(phoneActions.phone)
        }
    }

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
                        ColumnLayout {
                            id: volumeEntry
                            required property var modelData
                            Layout.fillWidth: true
                            spacing: 0
                            ListRow {
                                id: row
                                level: 1
                                readonly property bool isMounted: DrivesService.mounted(volumeEntry.modelData)
                                readonly property bool isLocked: DrivesService.locked(volumeEntry.modelData)
                                Layout.fillWidth: true
                                icon: row.isLocked ? Icons.lock : isMounted ? "󰉖" : Icons.folder
                                active: isMounted
                                title: DrivesService.volumeTitle(volumeEntry.modelData)
                                subtitle: DrivesService.volumeSubtitle(volumeEntry.modelData)
                                onClicked: DrivesService.openVolume(card.modelData, volumeEntry.modelData)

                                // Loaded rather than hidden: a hidden child
                                // still counts in the row's trailing width
                                // (childrenRect) and kept the name squeezed.
                                Loader {
                                    active: !root.narrow
                                    sourceComponent: VolumeActions {
                                        drive: card.modelData
                                        volume: volumeEntry.modelData
                                        busy: card.busy
                                    }
                                }
                            }
                            VolumeActions {
                                visible: root.narrow
                                Layout.leftMargin: root.underNameInset
                                Layout.bottomMargin: Metrics.spaceXs
                                drive: card.modelData
                                volume: volumeEntry.modelData
                                busy: card.busy
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

                ColumnLayout {
                    id: phoneRow
                    anchors.fill: parent
                    anchors.margins: Metrics.spaceMd
                    anchors.leftMargin: Metrics.spaceMd + Metrics.spaceXs
                    spacing: Metrics.spaceSm
                    RowLayout {
                        Layout.fillWidth: true
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
                        PhoneActions { visible: !root.narrow; phone: phoneCard.modelData; busy: phoneCard.busy }
                    }
                    PhoneActions {
                        visible: root.narrow
                        Layout.leftMargin: Metrics.iconLg + Metrics.spaceMd
                        phone: phoneCard.modelData
                        busy: phoneCard.busy
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
        onClicked: PanelService.open("settings", { page: "desktop", section: "Removable drives" })
    }
}
