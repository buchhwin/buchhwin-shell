import QtQuick
import QtQuick.Layouts
import qs.theme
import qs.services
import qs.shell.components

// Settings > Phone: KDE Connect daemon, this device, pair requests, paired
// phones with their actions and phones that can be paired. Every device shows
// only what its plugins support: battery and cellular signal, ping, ring,
// files, link or text, clipboard, the SMS app, lock, the phone's media player
// and a read-only list of its notifications. Refreshes every 10 s while the
// page is shown.
ColumnLayout {
    id: root
    spacing: Metrics.spaceLg

    readonly property var status: KdeConnectService.status

    Component.onCompleted: KdeConnectService.track()
    Component.onDestruction: KdeConnectService.untrack()

    SettingsSection {
        Layout.fillWidth: true
        title: "KDE Connect"
        description: KdeConnectService.summary

        ListRow {
            Layout.fillWidth: true
            icon: "󰄜"
            active: KdeConnectService.running
            title: KdeConnectService.running ? "KDE Connect is running" : KdeConnectService.known ? "KDE Connect is not running" : "Checking …"
            subtitle: KdeConnectService.running ? "Phones in the same network can find this computer"
                : "The service starts automatically when you log in"
            ShellButton {
                visible: KdeConnectService.known && !KdeConnectService.running
                text: "Start KDE Connect"
                compact: true
                variant: "accent"
                enabledState: KdeConnectService.realSession
                toolTip: KdeConnectService.realSession ? "" : "Only available in the buchhwin-shell session"
                onClicked: KdeConnectService.startDaemon()
            }
        }
        ShellText {
            Layout.fillWidth: true
            visible: KdeConnectService.known && !KdeConnectService.running && !KdeConnectService.realSession
            text: "Starting KDE Connect is only available in the buchhwin-shell session."
            role: "caption"
            wrapMode: Text.Wrap
        }
        ListRow {
            Layout.fillWidth: true
            visible: KdeConnectService.running
            icon: "󰌢"
            title: root.status.name || "This computer"
            subtitle: "Name shown on your phone"
        }
        ShellText {
            Layout.fillWidth: true
            text: "Install the KDE Connect app on your phone (Android: Google Play or F-Droid, iPhone: App Store) and open it while the phone is in the same network. Pairing can start on either device."
            role: "caption"
            wrapMode: Text.Wrap
        }
        Flow {
            Layout.fillWidth: true
            spacing: Metrics.spaceSm
            ShellButton {
                icon: Icons.refresh
                text: KdeConnectService.loading ? "Refreshing …" : "Refresh"
                compact: true
                onClicked: KdeConnectService.discover()
            }
            ShellButton {
                icon: Icons.settings
                text: "Open KDE Connect"
                compact: true
                onClicked: KdeConnectService.openApp()
            }
        }
        ShellText {
            Layout.fillWidth: true
            visible: KdeConnectService.message.length > 0
            text: KdeConnectService.message
            role: "caption"
            color: KdeConnectService.messageError ? Colors.danger : Colors.mutedText
            wrapMode: Text.Wrap
        }
    }

    SettingsSection {
        Layout.fillWidth: true
        visible: KdeConnectService.requests.length > 0
        title: "Pair requests"
        description: "Accept only if the key matches the one shown on the phone. Requests also appear as notifications."

        Repeater {
            model: KdeConnectService.requests
            ListRow {
                required property var modelData
                Layout.fillWidth: true
                icon: KdeConnectService.deviceIcon(modelData)
                active: true
                title: modelData.name
                subtitle: modelData.verificationKey.length ? "Key " + modelData.verificationKey : KdeConnectService.stateText(modelData)
                Row {
                    spacing: Metrics.spaceSm
                    ShellButton {
                        text: "Reject"
                        compact: true
                        onClicked: KdeConnectService.run("reject", modelData)
                    }
                    ShellButton {
                        text: "Accept"
                        compact: true
                        variant: "accent"
                        onClicked: KdeConnectService.run("accept", modelData)
                    }
                }
            }
        }
    }

    SettingsSection {
        Layout.fillWidth: true
        visible: KdeConnectService.running
        title: "My devices"
        description: "Paired phones and tablets. Actions need the device to be connected."

        EmptyState { Layout.fillWidth: true; visible: KdeConnectService.paired.length === 0; icon: "󰄜"; title: "No paired devices" }
        Repeater {
            model: KdeConnectService.paired
            ColumnLayout {
                id: deviceItem
                required property var modelData
                readonly property bool connected: modelData.reachable
                readonly property var player: modelData.media
                readonly property bool notificationsOpen: KdeConnectService.notificationsId === modelData.id
                property bool commandsOpen: false
                // Indent everything below the row under the device name.
                readonly property real indent: Metrics.spaceMd + Metrics.iconLg + Metrics.spaceMd
                property bool shareOpen: false
                Layout.fillWidth: true
                spacing: Metrics.spaceXxs

                function sendShare() {
                    KdeConnectService.sendText(deviceItem.modelData, shareField.text)
                    shareField.text = ""
                }

                ListRow {
                    Layout.fillWidth: true
                    icon: KdeConnectService.deviceIcon(deviceItem.modelData)
                    active: deviceItem.connected
                    title: deviceItem.modelData.name
                    subtitle: KdeConnectService.stateText(deviceItem.modelData)
                    trailingText: KdeConnectService.batteryText(deviceItem.modelData)
                    Row {
                        spacing: Metrics.spaceXs
                        readonly property string signalLabel: KdeConnectService.signalText(deviceItem.modelData)
                        ShellIcon {
                            anchors.verticalCenter: parent.verticalCenter
                            visible: parent.signalLabel.length > 0
                            glyph: KdeConnectService.signalIcon(deviceItem.modelData)
                            size: Metrics.iconSm
                            color: Colors.mutedText
                        }
                        ShellText {
                            anchors.verticalCenter: parent.verticalCenter
                            visible: parent.signalLabel.length > 0
                            text: parent.signalLabel
                            rightPadding: Metrics.spaceXs
                            role: "small"
                            muted: true
                        }
                        ShellButton {
                            anchors.verticalCenter: parent.verticalCenter
                            icon: Icons.remove
                            compact: true
                            variant: "ghost"
                            toolTip: "Unpair"
                            onClicked: KdeConnectService.run("unpair", deviceItem.modelData)
                        }
                    }
                }
                Flow {
                    Layout.fillWidth: true
                    Layout.leftMargin: deviceItem.indent
                    visible: deviceItem.connected
                    spacing: Metrics.spaceSm
                    ShellButton {
                        icon: "󰒊"
                        text: "Ping"
                        compact: true
                        enabledState: KdeConnectService.supports(deviceItem.modelData, "ping")
                        onClicked: KdeConnectService.run("ping", deviceItem.modelData)
                    }
                    ShellButton {
                        icon: "󰂞"
                        text: "Find my phone"
                        compact: true
                        enabledState: KdeConnectService.supports(deviceItem.modelData, "findmyphone")
                        onClicked: KdeConnectService.run("ring", deviceItem.modelData)
                    }
                    ShellButton {
                        icon: "󰈔"
                        text: "Send files …"
                        compact: true
                        enabledState: KdeConnectService.supports(deviceItem.modelData, "share")
                        onClicked: KdeConnectService.sendFiles(deviceItem.modelData)
                    }
                    ShellButton {
                        icon: "󰌷"
                        text: "Send link or text …"
                        compact: true
                        variant: deviceItem.shareOpen ? "accent" : "surface"
                        enabledState: KdeConnectService.supports(deviceItem.modelData, "share")
                        onClicked: {
                            deviceItem.shareOpen = !deviceItem.shareOpen
                            if (deviceItem.shareOpen) shareField.focusInput()
                        }
                    }
                    ShellButton {
                        icon: "󰅍"
                        text: "Send clipboard"
                        compact: true
                        enabledState: KdeConnectService.supports(deviceItem.modelData, "clipboard")
                        onClicked: KdeConnectService.run("clipboard", deviceItem.modelData)
                    }
                    ShellButton {
                        icon: "󰍡"
                        text: "Messages"
                        compact: true
                        visible: KdeConnectService.supports(deviceItem.modelData, "sms")
                        toolTip: "Open the KDE Connect SMS app"
                        onClicked: KdeConnectService.openSms(deviceItem.modelData)
                    }
                    ShellButton {
                        icon: deviceItem.modelData.locked ? "󰍁" : "󰌾"
                        text: deviceItem.modelData.locked ? "Unlock phone" : "Lock phone"
                        compact: true
                        visible: KdeConnectService.supports(deviceItem.modelData, "lockdevice")
                        onClicked: KdeConnectService.run(deviceItem.modelData.locked ? "unlock" : "lock", deviceItem.modelData)
                    }
                    ShellButton {
                        icon: "󰂚"
                        text: deviceItem.notificationsOpen ? "Hide notifications"
                            : KdeConnectService.notificationCountText(deviceItem.modelData.notificationCount)
                        compact: true
                        variant: deviceItem.notificationsOpen ? "accent" : "surface"
                        visible: KdeConnectService.supports(deviceItem.modelData, "notifications")
                            && deviceItem.modelData.notificationCount > 0
                        onClicked: KdeConnectService.toggleNotifications(deviceItem.modelData)
                    }
                    // The daemon mounts the phone over SFTP and opens the file
                    // manager itself, so this is one button and no path.
                    ShellButton {
                        icon: Icons.folder
                        text: deviceItem.modelData.mounted ? "Browse files" : "Browse files …"
                        compact: true
                        toolTip: "Mounts the phone and opens it in the file manager"
                        visible: KdeConnectService.supports(deviceItem.modelData, "sftp")
                        onClicked: KdeConnectService.browseFiles(deviceItem.modelData)
                    }
                    ShellButton {
                        icon: "󰆍"
                        text: deviceItem.commandsOpen ? "Hide commands"
                            : deviceItem.modelData.commands.length + (deviceItem.modelData.commands.length === 1
                                ? " command" : " commands")
                        compact: true
                        variant: deviceItem.commandsOpen ? "accent" : "surface"
                        visible: KdeConnectService.supports(deviceItem.modelData, "runcommand")
                            && deviceItem.modelData.commands.length > 0
                        onClicked: deviceItem.commandsOpen = !deviceItem.commandsOpen
                    }
                }

                // The commands the phone offers. Only their names: the command
                // line itself stays on the phone, where it runs.
                ColumnLayout {
                    Layout.fillWidth: true
                    Layout.leftMargin: deviceItem.indent
                    Layout.topMargin: Metrics.spaceXs
                    visible: deviceItem.connected && deviceItem.commandsOpen
                    spacing: Metrics.spaceXxs
                    Repeater {
                        model: deviceItem.commandsOpen ? deviceItem.modelData.commands : []
                        ListRow {
                            required property var modelData
                            Layout.fillWidth: true
                            icon: "󰆍"
                            title: modelData.name
                            ShellButton {
                                text: "Run"
                                compact: true
                                variant: "ghost"
                                onClicked: KdeConnectService.runCommand(deviceItem.modelData, modelData)
                            }
                        }
                    }
                }

                // Link or text for the share plugin; a web address opens on
                // the phone, anything else arrives as text.
                RowLayout {
                    Layout.fillWidth: true
                    Layout.leftMargin: deviceItem.indent
                    Layout.topMargin: Metrics.spaceXs
                    visible: deviceItem.connected && deviceItem.shareOpen
                    spacing: Metrics.spaceSm
                    ShellTextField {
                        id: shareField
                        Layout.fillWidth: true
                        icon: "󰌷"
                        placeholder: "Link or text to send to the phone"
                        onAccepted: deviceItem.sendShare()
                        onEscapePressed: deviceItem.shareOpen = false
                    }
                    ShellButton {
                        text: "Send"
                        compact: true
                        variant: "accent"
                        enabledState: shareField.text.trim().length > 0
                        onClicked: deviceItem.sendShare()
                    }
                }

                // The phone's media player (mprisremote plugin).
                ColumnLayout {
                    Layout.fillWidth: true
                    Layout.leftMargin: deviceItem.indent
                    Layout.topMargin: Metrics.spaceXs
                    visible: deviceItem.connected && KdeConnectService.hasMedia(deviceItem.modelData)
                    spacing: Metrics.spaceXs

                    RowLayout {
                        Layout.fillWidth: true
                        spacing: Metrics.spaceMd
                        ShellIcon { glyph: "󰝚"; size: Metrics.iconMd; color: Colors.accentForeground }
                        ColumnLayout {
                            Layout.fillWidth: true
                            spacing: 0
                            ShellText {
                                Layout.fillWidth: true
                                text: KdeConnectService.mediaTitle(deviceItem.modelData)
                                elide: Text.ElideRight
                            }
                            ShellText {
                                Layout.fillWidth: true
                                text: KdeConnectService.mediaSubtitle(deviceItem.modelData)
                                role: "small"
                                muted: true
                                elide: Text.ElideRight
                            }
                        }
                        ShellButton {
                            icon: Icons.previous; compact: true; variant: "ghost"; toolTip: "Previous"
                            onClicked: KdeConnectService.media(deviceItem.modelData, "previous")
                        }
                        ShellButton {
                            icon: deviceItem.player && deviceItem.player.playing ? Icons.pause : Icons.play
                            compact: true
                            variant: "accent"
                            toolTip: deviceItem.player && deviceItem.player.playing ? "Pause" : "Play"
                            onClicked: KdeConnectService.media(deviceItem.modelData, "play")
                        }
                        ShellButton {
                            icon: Icons.next; compact: true; variant: "ghost"; toolTip: "Next"
                            onClicked: KdeConnectService.media(deviceItem.modelData, "next")
                        }
                    }
                    RowLayout {
                        Layout.fillWidth: true
                        visible: deviceItem.player !== null && deviceItem.player.volume >= 0
                        spacing: Metrics.spaceMd
                        ShellIcon { glyph: "󰕾"; size: Metrics.iconSm; color: Colors.mutedText }
                        ShellSlider {
                            Layout.fillWidth: true
                            from: 0
                            to: 100
                            value: deviceItem.player ? deviceItem.player.volume : 0
                            onReleased: volume => KdeConnectService.setMediaVolume(deviceItem.modelData, volume)
                        }
                    }
                    ShellSelect {
                        Layout.fillWidth: true
                        visible: deviceItem.player !== null && deviceItem.player.players.length > 1
                        options: deviceItem.player
                            ? deviceItem.player.players.map(name => ({ value: name, label: name })) : []
                        current: deviceItem.player ? deviceItem.player.player : ""
                        placeholder: "Player on the phone"
                        onSelected: name => KdeConnectService.setMediaPlayer(deviceItem.modelData, name)
                    }
                }

                // Read-only mirror of the phone's notifications; texts are
                // never logged and never leave this process.
                ColumnLayout {
                    Layout.fillWidth: true
                    Layout.leftMargin: deviceItem.indent
                    Layout.topMargin: Metrics.spaceXs
                    visible: deviceItem.connected && deviceItem.notificationsOpen
                    spacing: Metrics.spaceXxs

                    ShellText {
                        Layout.fillWidth: true
                        visible: KdeConnectService.notifications.length === 0
                        text: KdeConnectService.notificationsLoading ? "Reading notifications …" : "No notifications right now"
                        role: "caption"
                        muted: true
                    }
                    Repeater {
                        model: deviceItem.notificationsOpen ? KdeConnectService.notifications : []
                        ColumnLayout {
                            id: noteRow
                            required property var modelData
                            Layout.fillWidth: true
                            spacing: Metrics.spaceXxs
                            // The answer field opens under the notification it
                            // belongs to, so it is never unclear which one is
                            // being answered.
                            property bool answering: false

                            ListRow {
                                Layout.fillWidth: true
                                icon: "󰂚"
                                title: noteRow.modelData.title.length ? noteRow.modelData.title : noteRow.modelData.appName
                                subtitle: noteRow.modelData.appName.length && noteRow.modelData.text.length
                                    ? noteRow.modelData.appName + " · " + noteRow.modelData.text
                                    : noteRow.modelData.text.length ? noteRow.modelData.text : noteRow.modelData.appName
                                ShellButton {
                                    text: noteRow.answering ? "Cancel" : "Reply"
                                    compact: true
                                    variant: "ghost"
                                    // Only where the phone says an answer is
                                    // possible: it refuses the rest.
                                    visible: noteRow.modelData.replyId.length > 0
                                    onClicked: {
                                        noteRow.answering = !noteRow.answering
                                        if (noteRow.answering) Qt.callLater(replyField.focusInput)
                                    }
                                }
                                ShellButton {
                                    text: "Dismiss"
                                    compact: true
                                    variant: "ghost"
                                    visible: noteRow.modelData.dismissable
                                    onClicked: KdeConnectService.dismissNotification(deviceItem.modelData, noteRow.modelData)
                                }
                            }

                            RowLayout {
                                Layout.fillWidth: true
                                Layout.leftMargin: Metrics.spaceLg
                                visible: noteRow.answering
                                spacing: Metrics.spaceSm
                                ShellTextField {
                                    id: replyField
                                    Layout.fillWidth: true
                                    focusOnTab: true
                                    icon: "󰍡"
                                    placeholder: "Answer …"
                                    onAccepted: if (KdeConnectService.replyToNotification(deviceItem.modelData, noteRow.modelData, text)) {
                                        text = ""
                                        noteRow.answering = false
                                    }
                                }
                                ShellButton {
                                    text: "Send"
                                    variant: "accent"
                                    compact: true
                                    enabledState: replyField.text.trim().length > 0
                                    onClicked: if (KdeConnectService.replyToNotification(deviceItem.modelData, noteRow.modelData, replyField.text)) {
                                        replyField.text = ""
                                        noteRow.answering = false
                                    }
                                }
                            }
                        }
                    }
                }
            }
        }
    }

    SettingsSection {
        Layout.fillWidth: true
        visible: KdeConnectService.running
        title: "Available devices"
        description: "Devices in the same network with KDE Connect open that are not paired yet."

        EmptyState {
            Layout.fillWidth: true
            visible: KdeConnectService.available.length === 0
            row: true
            icon: "󰄜"
            title: "No devices found"
            description: "Open KDE Connect on the phone and press Refresh"
        }
        Repeater {
            model: KdeConnectService.available
            ListRow {
                required property var modelData
                Layout.fillWidth: true
                icon: KdeConnectService.deviceIcon(modelData)
                title: modelData.name
                subtitle: KdeConnectService.stateText(modelData)
                ShellButton {
                    text: modelData.requested ? "Requested" : "Pair"
                    compact: true
                    variant: "accent"
                    enabledState: modelData.reachable && !modelData.requested
                    onClicked: KdeConnectService.run("pair", modelData)
                }
            }
        }
    }
}
