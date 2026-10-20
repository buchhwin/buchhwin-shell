import Quickshell
import QtQuick
import QtQuick.Layouts
import qs.theme
import qs.services
import qs.shell.components
import "../../../services/kdeconnect/KdeConnectLogic.js" as Logic

// Settings > Phone: KDE Connect daemon, this device, pair requests, paired
// phones with their actions and phones that can be paired. Every device shows
// only what its plugins support: battery and cellular signal, ping, ring,
// files, link or text, clipboard, the SMS app, lock, the phone's media player
// and a read-only list of its notifications. Refreshes every 10 s while the
// page is shown.
ColumnLayout {
    id: root
    spacing: Metrics.pageGap

    readonly property var status: KdeConnectService.status
    // Rows are keyed by the device's id, and each reads its device here. The
    // 10-s poll brings a new snapshot whenever a battery level, the signal,
    // a notification count or the media title changes, and a Repeater on the
    // device list itself built every row again: an open "Send link or text"
    // field lost what was typed, a reply its draft, and the keyboard the
    // button it stood on (testing.md pitfall 76, the string-key way).
    readonly property var deviceById: {
        const table = {}
        for (const item of KdeConnectService.status.devices) table[item.id] = item
        return table
    }
    // A row whose device went in the same turn reads an empty one rather
    // than nothing, until the model takes the row away.
    function device(id) { return root.deviceById[id] || Logic.device({ id: id, name: "" }) }

    PageActivity {
        onOpened: KdeConnectService.track()
        onClosed: KdeConnectService.untrack()
    }

    SettingsSection {
        Layout.fillWidth: true
        title: "KDE Connect"
        description: KdeConnectService.summary
        hint: "Install the KDE Connect app on your phone (Google Play, F-Droid or the App Store) and open it in the same network. Pairing can start on either device."

        ListRow {
            interactive: false
            Layout.fillWidth: true
            icon: "󰄜"
            active: KdeConnectService.running
            title: KdeConnectService.running ? "KDE Connect is running" : KdeConnectService.known ? "KDE Connect is not running" : "Checking …"
            subtitle: KdeConnectService.running ? "Visible to phones in this network"
                : "Starts by itself when you log in"
            ShellButton {
                focusOnTab: true
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
            interactive: false
            Layout.fillWidth: true
            visible: KdeConnectService.running
            icon: "󰌢"
            title: root.status.name || "This computer"
            subtitle: "Name shown on your phone"
        }
        Flow {
            Layout.fillWidth: true
            spacing: Metrics.spaceSm
            ShellButton {
                focusOnTab: true
                icon: Icons.refresh
                text: KdeConnectService.loading ? "Refreshing …" : "Refresh"
                compact: true
                onClicked: KdeConnectService.discover()
            }
            ShellButton {
                focusOnTab: true
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
        // Said where the buttons are rather than behind the mark: it is what
        // to check before pressing Accept.
        description: "Accept only if the key matches the one on the phone."
        hint: "Requests also appear as notifications."

        Repeater {
            model: ScriptModel { values: KdeConnectService.requests.map(item => item.id) }
            ListRow {
                id: requestRow
                required property string modelData
                readonly property var device: root.device(modelData)
                interactive: false
                Layout.fillWidth: true
                icon: KdeConnectService.deviceIcon(requestRow.device)
                active: true
                title: requestRow.device.name
                subtitle: requestRow.device.verificationKey.length ? "Key " + requestRow.device.verificationKey
                    : KdeConnectService.stateText(requestRow.device)
                Row {
                    spacing: Metrics.spaceSm
                    ShellButton {
                        focusOnTab: true
                        text: "Reject"
                        compact: true
                        onClicked: KdeConnectService.run("reject", requestRow.device)
                    }
                    ShellButton {
                        focusOnTab: true
                        text: "Accept"
                        compact: true
                        variant: "accent"
                        onClicked: KdeConnectService.run("accept", requestRow.device)
                    }
                }
            }
        }
    }

    SettingsSection {
        Layout.fillWidth: true
        visible: KdeConnectService.running
        title: "My devices"
        hint: "Paired phones and tablets. Their actions need the device to be connected."

        EmptyState { Layout.fillWidth: true; visible: KdeConnectService.paired.length === 0; row: true; icon: "󰄜"; title: "No paired devices" }
        Repeater {
            model: ScriptModel { values: KdeConnectService.paired.map(item => item.id) }
            ColumnLayout {
                id: deviceItem
                required property string modelData
                readonly property var device: root.device(modelData)
                readonly property bool connected: device.reachable
                readonly property var player: device.media
                readonly property bool notificationsOpen: KdeConnectService.notificationsId === modelData
                property bool commandsOpen: false
                // Indent everything below the row under the device name.
                readonly property real indent: Metrics.spaceMd + Metrics.iconLg + Metrics.spaceMd
                property bool shareOpen: false
                Layout.fillWidth: true
                spacing: Metrics.spaceXxs

                function sendShare() {
                    KdeConnectService.sendText(deviceItem.device, shareField.text)
                    shareField.text = ""
                }

                ListRow {
                    interactive: false
                    Layout.fillWidth: true
                    icon: KdeConnectService.deviceIcon(deviceItem.device)
                    active: deviceItem.connected
                    title: deviceItem.device.name
                    subtitle: KdeConnectService.stateText(deviceItem.device)
                    trailingText: KdeConnectService.batteryText(deviceItem.device)
                    Row {
                        spacing: Metrics.spaceXs
                        readonly property string signalLabel: KdeConnectService.signalText(deviceItem.device)
                        ShellIcon {
                            anchors.verticalCenter: parent.verticalCenter
                            visible: parent.signalLabel.length > 0
                            glyph: KdeConnectService.signalIcon(deviceItem.device)
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
                            focusOnTab: true
                            anchors.verticalCenter: parent.verticalCenter
                            icon: Icons.remove
                            compact: true
                            variant: "ghost"
                            // The pairing is gone; it has to be accepted on
                            // the phone again. Two clicks, as Bluetooth's Remove.
                            confirm: true
                            confirmText: "Unpair?"
                            toolTip: "Unpair"
                            onClicked: KdeConnectService.run("unpair", deviceItem.device)
                        }
                    }
                }
                Flow {
                    Layout.fillWidth: true
                    Layout.leftMargin: deviceItem.indent
                    visible: deviceItem.connected
                    spacing: Metrics.spaceSm
                    ShellButton {
                        focusOnTab: true
                        icon: Icons.send
                        text: "Ping"
                        compact: true
                        enabledState: KdeConnectService.supports(deviceItem.device, "ping")
                        onClicked: KdeConnectService.run("ping", deviceItem.device)
                    }
                    ShellButton {
                        focusOnTab: true
                        icon: "󰂞"
                        text: "Find my phone"
                        compact: true
                        enabledState: KdeConnectService.supports(deviceItem.device, "findmyphone")
                        onClicked: KdeConnectService.run("ring", deviceItem.device)
                    }
                    ShellButton {
                        focusOnTab: true
                        icon: "󰈔"
                        text: "Send files …"
                        compact: true
                        enabledState: KdeConnectService.supports(deviceItem.device, "share")
                        onClicked: KdeConnectService.sendFiles(deviceItem.device)
                    }
                    ShellButton {
                        focusOnTab: true
                        icon: "󰌷"
                        text: "Send link or text …"
                        compact: true
                        variant: deviceItem.shareOpen ? "accent" : "surface"
                        enabledState: KdeConnectService.supports(deviceItem.device, "share")
                        onClicked: {
                            deviceItem.shareOpen = !deviceItem.shareOpen
                            if (deviceItem.shareOpen) shareField.focusInput()
                        }
                    }
                    ShellButton {
                        focusOnTab: true
                        icon: "󰅍"
                        text: "Send clipboard"
                        compact: true
                        enabledState: KdeConnectService.supports(deviceItem.device, "clipboard")
                        onClicked: KdeConnectService.run("clipboard", deviceItem.device)
                    }
                    ShellButton {
                        focusOnTab: true
                        icon: "󰍡"
                        text: "Messages"
                        compact: true
                        visible: KdeConnectService.supports(deviceItem.device, "sms")
                        toolTip: "Open the KDE Connect SMS app"
                        onClicked: KdeConnectService.openSms(deviceItem.device)
                    }
                    ShellButton {
                        focusOnTab: true
                        // What the button does: the open padlock to unlock,
                        // the shut one to lock (Icons.unlock, Icons.lock).
                        icon: deviceItem.device.locked ? Icons.unlock : Icons.lock
                        text: deviceItem.device.locked ? "Unlock phone" : "Lock phone"
                        compact: true
                        visible: KdeConnectService.supports(deviceItem.device, "lockdevice")
                        onClicked: KdeConnectService.run(deviceItem.device.locked ? "unlock" : "lock", deviceItem.device)
                    }
                    ShellButton {
                        focusOnTab: true
                        icon: "󰂚"
                        text: deviceItem.notificationsOpen ? "Hide notifications"
                            : KdeConnectService.notificationCountText(deviceItem.device.notificationCount)
                        compact: true
                        variant: deviceItem.notificationsOpen ? "accent" : "surface"
                        visible: KdeConnectService.supports(deviceItem.device, "notifications")
                            && deviceItem.device.notificationCount > 0
                        onClicked: KdeConnectService.toggleNotifications(deviceItem.device)
                    }
                    // The daemon mounts the phone over SFTP and opens the file
                    // manager itself, so this is one button and no path.
                    ShellButton {
                        focusOnTab: true
                        icon: Icons.folder
                        text: deviceItem.device.mounted ? "Browse files" : "Browse files …"
                        compact: true
                        toolTip: "Mounts the phone and opens it in the file manager"
                        visible: KdeConnectService.supports(deviceItem.device, "sftp")
                        onClicked: KdeConnectService.browseFiles(deviceItem.device)
                    }
                    ShellButton {
                        focusOnTab: true
                        icon: "󰆍"
                        text: deviceItem.commandsOpen ? "Hide commands"
                            : deviceItem.device.commands.length + (deviceItem.device.commands.length === 1
                                ? " command" : " commands")
                        compact: true
                        variant: deviceItem.commandsOpen ? "accent" : "surface"
                        visible: KdeConnectService.supports(deviceItem.device, "runcommand")
                            && deviceItem.device.commands.length > 0
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
                    // By key as well: the device is new with every poll that
                    // changes it, and so is its list of commands.
                    Repeater {
                        model: ScriptModel { values: deviceItem.commandsOpen ? deviceItem.device.commands.map(entry => entry.key) : [] }
                        ListRow {
                            id: commandRow
                            required property string modelData
                            readonly property var command: deviceItem.device.commands.find(entry => entry.key === modelData)
                                || ({ key: modelData, name: "" })
                            interactive: false
                            Layout.fillWidth: true
                            icon: "󰆍"
                            title: commandRow.command.name
                            ShellButton {
                                focusOnTab: true
                                text: "Run"
                                compact: true
                                variant: "ghost"
                                onClicked: KdeConnectService.runCommand(deviceItem.device, commandRow.command)
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
                        focusOnTab: true
                        id: shareField
                        Layout.fillWidth: true
                        icon: "󰌷"
                        placeholder: "Link or text to send to the phone"
                        onAccepted: deviceItem.sendShare()
                        onEscapePressed: deviceItem.shareOpen = false
                    }
                    ShellButton {
                        focusOnTab: true
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
                    visible: deviceItem.connected && KdeConnectService.hasMedia(deviceItem.device)
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
                                text: KdeConnectService.mediaTitle(deviceItem.device)
                                elide: Text.ElideRight
                            }
                            ShellText {
                                Layout.fillWidth: true
                                text: KdeConnectService.mediaSubtitle(deviceItem.device)
                                role: "small"
                                muted: true
                                elide: Text.ElideRight
                            }
                        }
                        ShellButton {
                            focusOnTab: true
                            icon: Icons.previous; compact: true; variant: "ghost"; toolTip: "Previous"
                            onClicked: KdeConnectService.media(deviceItem.device, "previous")
                        }
                        ShellButton {
                            focusOnTab: true
                            icon: deviceItem.player && deviceItem.player.playing ? Icons.pause : Icons.play
                            compact: true
                            variant: "accent"
                            toolTip: deviceItem.player && deviceItem.player.playing ? "Pause" : "Play"
                            onClicked: KdeConnectService.media(deviceItem.device, "play")
                        }
                        ShellButton {
                            focusOnTab: true
                            icon: Icons.next; compact: true; variant: "ghost"; toolTip: "Next"
                            onClicked: KdeConnectService.media(deviceItem.device, "next")
                        }
                    }
                    RowLayout {
                        Layout.fillWidth: true
                        visible: deviceItem.player !== null && deviceItem.player.volume >= 0
                        spacing: Metrics.spaceMd
                        ShellIcon { glyph: "󰕾"; size: Metrics.iconSm; color: Colors.mutedText }
                        ShellSlider {
                            focusOnTab: true
                            Layout.fillWidth: true
                            from: 0
                            to: 100
                            value: deviceItem.player ? deviceItem.player.volume : 0
                            onReleased: volume => KdeConnectService.setMediaVolume(deviceItem.device, volume)
                        }
                    }
                    ShellSelect {
                        focusOnTab: true
                        Layout.fillWidth: true
                        visible: deviceItem.player !== null && deviceItem.player.players.length > 1
                        options: deviceItem.player
                            ? deviceItem.player.players.map(name => ({ value: name, label: name })) : []
                        current: deviceItem.player ? deviceItem.player.player : ""
                        placeholder: "Player on the phone"
                        onSelected: name => KdeConnectService.setMediaPlayer(deviceItem.device, name)
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

                    EmptyState {
                        Layout.fillWidth: true
                        visible: KdeConnectService.notifications.length === 0
                        row: true
                        icon: KdeConnectService.notificationsLoading ? Icons.busy : "󰂚"
                        title: KdeConnectService.notificationsLoading ? "Reading notifications …" : "No notifications right now"
                    }
                    // By the notification's id: a dismissed one takes its own
                    // row and leaves an answer being typed under another.
                    Repeater {
                        model: ScriptModel { values: deviceItem.notificationsOpen ? KdeConnectService.notifications.map(note => note.id) : [] }
                        ColumnLayout {
                            id: noteRow
                            required property string modelData
                            readonly property var note: KdeConnectService.notifications.find(item => item.id === modelData)
                                || ({ id: modelData, appName: "", title: "", text: "", dismissable: false, replyId: "" })
                            Layout.fillWidth: true
                            spacing: Metrics.spaceXxs
                            // The answer field opens under the notification it
                            // belongs to, so it is never unclear which one is
                            // being answered.
                            property bool answering: false

                            ListRow {
                                interactive: false
                                Layout.fillWidth: true
                                icon: "󰂚"
                                title: noteRow.note.title.length ? noteRow.note.title : noteRow.note.appName
                                subtitle: noteRow.note.appName.length && noteRow.note.text.length
                                    ? noteRow.note.appName + " · " + noteRow.note.text
                                    : noteRow.note.text.length ? noteRow.note.text : noteRow.note.appName
                                // The trailing slot is a plain Item: two
                                // buttons put straight into it sit on top of
                                // each other, so they go in a Row like the
                                // other rows on this page.
                                Row {
                                    spacing: Metrics.spaceSm
                                    ShellButton {
                                        focusOnTab: true
                                        text: noteRow.answering ? "Cancel" : "Reply"
                                        compact: true
                                        variant: "ghost"
                                        // Only where the phone says an answer is
                                        // possible: it refuses the rest.
                                        visible: noteRow.note.replyId.length > 0
                                        onClicked: {
                                            noteRow.answering = !noteRow.answering
                                            if (noteRow.answering) Qt.callLater(replyField.focusInput)
                                        }
                                    }
                                    ShellButton {
                                        focusOnTab: true
                                        text: "Dismiss"
                                        compact: true
                                        variant: "ghost"
                                        visible: noteRow.note.dismissable
                                        onClicked: KdeConnectService.dismissNotification(deviceItem.device, noteRow.note)
                                    }
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
                                    onAccepted: if (KdeConnectService.replyToNotification(deviceItem.device, noteRow.note, text)) {
                                        text = ""
                                        noteRow.answering = false
                                    }
                                }
                                ShellButton {
                                    focusOnTab: true
                                    text: "Send"
                                    variant: "accent"
                                    compact: true
                                    enabledState: replyField.text.trim().length > 0
                                    onClicked: if (KdeConnectService.replyToNotification(deviceItem.device, noteRow.note, replyField.text)) {
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
        hint: "Devices in the same network with KDE Connect open that are not paired yet."

        EmptyState {
            Layout.fillWidth: true
            visible: KdeConnectService.available.length === 0
            row: true
            icon: "󰄜"
            title: "No devices found"
            description: "Open KDE Connect on the phone and press Refresh"
        }
        Repeater {
            model: ScriptModel { values: KdeConnectService.available.map(item => item.id) }
            ListRow {
                id: availableRow
                required property string modelData
                readonly property var device: root.device(modelData)
                interactive: false
                Layout.fillWidth: true
                icon: KdeConnectService.deviceIcon(availableRow.device)
                title: availableRow.device.name
                subtitle: KdeConnectService.stateText(availableRow.device)
                ShellButton {
                    focusOnTab: true
                    text: availableRow.device.requested ? "Requested" : "Pair"
                    compact: true
                    variant: "accent"
                    enabledState: availableRow.device.reachable && !availableRow.device.requested
                    onClicked: KdeConnectService.run("pair", availableRow.device)
                }
            }
        }
    }
}
