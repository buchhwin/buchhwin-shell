import Quickshell
import QtQuick
import QtQuick.Layouts
import qs.theme
import qs.services
import qs.shell.components
import "../../../services/lock/LockCatalogue.js" as Lock

// Settings > Lock Screen: what the macOS-style lock screen shows (changes apply
// the next time the screen locks) and fingerprints (fprintd): enrolled fingers
// with Delete and a guided enrollment.
ColumnLayout {
    id: root
    spacing: Metrics.spaceLg

    // Finger selector shown before an enrollment starts.
    property bool enrollOpen: false
    property string enrollFinger: FingerprintService.defaultFinger()
    readonly property var enrollment: FingerprintService.enrollment

    PageActivity {
        onOpened: FingerprintService.track()
        onClosed: FingerprintService.untrack()
    }

    SettingsSection {
        Layout.fillWidth: true
        title: "Lock screen"
        description: "The screen behind the lock is blurred so nothing on it can be read. When to lock automatically is set under Power."

        RowLayout {
            ShellIcon { glyph: "󰌾"; size: Metrics.iconLg; color: Colors.accentForeground }
            ShellText { Layout.fillWidth: true; text: "Super+L locks the screen"; muted: true }
            ShellButton {
                focusOnTab: true
                text: "Lock now"
                icon: "󰌾"
                variant: "accent"
                compact: true
                onClicked: { PanelService.close(); SessionService.run("lock") }
            }
        }
    }

    SettingsSection {
        Layout.fillWidth: true
        title: "What the lock screen shows"
        description: "Drag to arrange, pull a corner to size. Applies the next time the screen locks"

        LockPreview {
            Layout.fillWidth: true
        }

        // What is not on the preview: the picker, and the way back.
        Flow {
            Layout.fillWidth: true
            spacing: Metrics.spaceXs
            Repeater {
                model: Lock.missing(LayoutService.lockTypes)
                ShellButton {
                    focusOnTab: true
                    required property var modelData
                    icon: modelData.icon
                    text: modelData.label
                    compact: true
                    variant: "surface"
                    onClicked: LayoutService.lockAdd(modelData.type)
                }
            }
        }
        SettingRow {
            Layout.fillWidth: true
            labelFills: true
            label: "Back to the default arrangement"
            hint: "Time, date and the player, as the lock screen started out"
            ShellButton {
                focusOnTab: true
                text: "Reset"
                variant: "danger"
                confirm: true
                confirmText: "Click again"
                onClicked: LayoutService.lockResetLayout()
            }
        }
    }

    SettingsSection {
        Layout.fillWidth: true
        title: "The corners"
        description: "Applies the next time the screen locks"

        Repeater {
            model: [
                { key: "lock.showAvatar", label: "Profile picture", hint: "The Fastfetch image from Settings > Terminal, otherwise your initial" },
                { key: "lock.showStatus", label: "Battery and keyboard layout", hint: "Top right corner" },
                { key: "lock.showPowerButtons", label: "Sleep, restart and shut down", hint: "Bottom right corner; a second click confirms" }
            ]
            SettingRow {
                id: optionRow
                required property var modelData
                Layout.fillWidth: true
                labelFills: true
                label: optionRow.modelData.label
                hint: optionRow.modelData.hint
                ShellToggle {
                    focusOnTab: true
                    checked: SettingsService.value(optionRow.modelData.key)
                    onToggled: value => SettingsService.set(optionRow.modelData.key, value)
                }
            }
        }
    }

    SettingsSection {
        Layout.fillWidth: true
        title: "Fingerprint"
        description: "Unlock the lock screen with a finger. Typing your password always works too."

        ListRow {
            Layout.fillWidth: true
            icon: "󰈷"
            active: FingerprintService.available && FingerprintService.fingers.length > 0
            title: !FingerprintService.known ? "Looking for a fingerprint reader …"
                : FingerprintService.available ? (FingerprintService.reader.device || "Fingerprint reader")
                : FingerprintService.reader.error || "No fingerprint reader found"
            subtitle: !FingerprintService.available ? ""
                : (FingerprintService.fingers.length === 0 ? "No fingers enrolled"
                   : FingerprintService.fingers.length === 1 ? "1 finger enrolled"
                   : FingerprintService.fingers.length + " fingers enrolled")
                  + (FingerprintService.preview ? " · preview data" : "")
            ShellButton {
                focusOnTab: true
                icon: Icons.refresh
                compact: true
                variant: "ghost"
                toolTip: "Refresh"
                enabledState: !FingerprintService.loading && !FingerprintService.preview
                onClicked: FingerprintService.refresh()
            }
        }

        // Unlock mode: on a dock the closed lid hides the sensor.
        ColumnLayout {
            Layout.fillWidth: true
            spacing: Metrics.spaceSm
            SettingRow {
                Layout.fillWidth: true
                label: "Use fingerprint"
                SegmentedControl {
                    focusOnTab: true
                    Layout.fillWidth: true
                    current: FingerprintService.mode
                    options: [
                        { value: "auto", label: "Automatic", icon: "󰌢" },
                        { value: "on", label: "On", icon: "󰈷" },
                        { value: "off", label: "Off", icon: "󰌾" }
                    ]
                    onSelected: value => FingerprintService.setMode(value)
                }
            }
            ShellText {
                Layout.fillWidth: true
                text: "Automatic turns it off while the lid is closed, for example on a dock. This is the lock screen's setting."
                role: "caption"
                wrapMode: Text.Wrap
            }
            // "Off" here and still being asked for a finger is not a broken
            // button: the login screen, sudo and every polkit dialog go
            // through PAM's system-auth, where authselect puts the reader.
            // Turning that off is one host command and the user's to run.
            ShellCard {
                Layout.fillWidth: true
                visible: FingerprintService.systemOnly
                implicitHeight: systemNote.implicitHeight + Metrics.spaceMd * 2
                ColumnLayout {
                    id: systemNote
                    anchors.fill: parent
                    anchors.margins: Metrics.spaceMd
                    spacing: Metrics.spaceXs
                    ShellText {
                        Layout.fillWidth: true
                        text: "The reader is still on for the rest of the system"
                        wrapMode: Text.Wrap
                    }
                    ShellText {
                        Layout.fillWidth: true
                        text: "Off applies to this lock screen. The login screen, sudo and password dialogs "
                            + "authenticate through PAM, where the reader is enabled system-wide, so they keep asking. "
                            + "To turn it off everywhere, run this once and log in again:"
                        role: "caption"
                        wrapMode: Text.Wrap
                    }
                    ShellText {
                        Layout.fillWidth: true
                        text: "sudo authselect disable-feature with-fingerprint"
                        font.family: Typography.monoFamily
                        wrapMode: Text.Wrap
                    }
                    ShellButton {
                        focusOnTab: true
                        icon: Icons.copy
                        text: "Copy command"
                        onClicked: Quickshell.clipboardText = "sudo authselect disable-feature with-fingerprint"
                    }
                }
            }
            ShellText {
                Layout.fillWidth: true
                text: FingerprintService.modeState
                role: "caption"
                color: FingerprintService.enabledNow ? Colors.accentForeground : Colors.mutedText
                wrapMode: Text.Wrap
            }
        }

        Repeater {
            model: FingerprintService.fingers
            ListRow {
                id: fingerRow
                required property string modelData
                Layout.fillWidth: true
                icon: "󰈷"
                title: FingerprintService.fingerLabel(modelData)
                subtitle: FingerprintService.deleting === modelData ? "Deleting …" : "Unlocks the lock screen"
                ShellButton {
                    focusOnTab: true
                    text: "Delete"
                    icon: Icons.remove
                    compact: true
                    // An enrolled finger cannot be brought back; the button
                    // asks twice, the way every destructive one does.
                    confirm: true
                    confirmText: "Click again to delete"
                    enabledState: FingerprintService.actionsAllowed
                    onClicked: FingerprintService.remove(fingerRow.modelData)
                }
            }
        }

        // Enroll: pick a finger, then follow the reader.
        ShellButton {
            focusOnTab: true
            visible: FingerprintService.available && !root.enrollOpen && root.enrollment === null
            text: "Enroll finger …"
            icon: Icons.add
            variant: "accent"
            compact: true
            enabledState: FingerprintService.actionsAllowed
            onClicked: {
                root.enrollFinger = FingerprintService.defaultFinger()
                root.enrollOpen = true
            }
        }

        ColumnLayout {
            Layout.fillWidth: true
            visible: root.enrollOpen && root.enrollment === null
            spacing: Metrics.spaceSm
            SettingRow {
                Layout.fillWidth: true
                label: "Finger"
                ShellSelect {
                    focusOnTab: true
                    Layout.fillWidth: true
                    options: FingerprintService.fingerOptions
                    current: root.enrollFinger
                    onSelected: value => root.enrollFinger = value
                }
            }
            ShellText {
                Layout.fillWidth: true
                text: "Your password may be asked for before the reader starts. Place the finger on the reader several times, moving it slightly each time."
                role: "caption"
                wrapMode: Text.Wrap
            }
            RowLayout {
                spacing: Metrics.spaceSm
                ShellButton {
                    focusOnTab: true
                    text: "Start"
                    icon: "󰈷"
                    variant: "accent"
                    compact: true
                    enabledState: FingerprintService.actionsAllowed
                    onClicked: FingerprintService.enroll(root.enrollFinger)
                }
                ShellButton {
                    focusOnTab: true
                    text: "Cancel"
                    compact: true
                    onClicked: root.enrollOpen = false
                }
            }
        }

        // A card inside the section: the enrollment in progress.
        ShellCard {
            Layout.fillWidth: true
            level: 2
            visible: root.enrollment !== null
            implicitHeight: enrollColumn.implicitHeight + Metrics.spaceXl * 2

            ColumnLayout {
                id: enrollColumn
                anchors.left: parent.left
                anchors.right: parent.right
                anchors.top: parent.top
                anchors.margins: Metrics.spaceXl
                spacing: Metrics.spaceMd

                FingerprintGlyph {
                    Layout.alignment: Qt.AlignHCenter
                    mode: !root.enrollment ? "idle"
                        : root.enrollment.phase === "done" ? "done"
                        : root.enrollment.phase === "failed" ? "failed"
                        : root.enrollment.phase === "cancelled" ? "idle" : "scanning"
                    progress: root.enrollment ? FingerprintService.progress() : 0
                    retries: root.enrollment ? root.enrollment.retries : 0
                }
                ShellText {
                    Layout.alignment: Qt.AlignHCenter
                    text: root.enrollment ? FingerprintService.fingerLabel(root.enrollment.finger) : ""
                    role: "title"
                }
                ShellText {
                    Layout.fillWidth: true
                    horizontalAlignment: Text.AlignHCenter
                    wrapMode: Text.Wrap
                    text: root.enrollment ? root.enrollment.message : ""
                    color: root.enrollment && root.enrollment.error ? Colors.danger : Colors.mutedText
                }
                // Stage progress.
                Rectangle {
                    Layout.alignment: Qt.AlignHCenter
                    Layout.preferredWidth: Metrics.lockFieldWidth
                    visible: root.enrollment !== null && root.enrollment.stages > 0 && root.enrollment.phase !== "failed"
                    implicitHeight: Metrics.meterHeight
                    radius: height / 2
                    color: Colors.track
                    Rectangle {
                        anchors.left: parent.left
                        anchors.top: parent.top
                        anchors.bottom: parent.bottom
                        radius: height / 2
                        width: parent.width * (root.enrollment ? FingerprintService.progress() : 0)
                        color: root.enrollment && root.enrollment.success ? Colors.success : Colors.accent
                        Behavior on width { NumberAnimation { duration: Animations.move(Animations.fingerprintFill); easing.type: Animations.easing } }
                    }
                }
                RowLayout {
                    Layout.alignment: Qt.AlignHCenter
                    spacing: Metrics.spaceSm
                    ShellButton {
                        focusOnTab: true
                        visible: FingerprintService.enrolling
                        text: FingerprintService.cancelling ? "Cancelling …" : "Cancel"
                        compact: true
                        onClicked: FingerprintService.cancel()
                    }
                    ShellButton {
                        focusOnTab: true
                        visible: root.enrollment !== null && root.enrollment.finished && !root.enrollment.success
                        text: "Try again"
                        compact: true
                        onClicked: {
                            root.enrollFinger = root.enrollment.finger
                            FingerprintService.dismiss()
                            root.enrollOpen = true
                        }
                    }
                    ShellButton {
                        focusOnTab: true
                        visible: root.enrollment !== null && root.enrollment.finished
                        text: "Done"
                        variant: "accent"
                        compact: true
                        onClicked: {
                            FingerprintService.dismiss()
                            root.enrollOpen = false
                        }
                    }
                }
            }
        }

        ShellText {
            Layout.fillWidth: true
            visible: FingerprintService.message.length > 0
            text: FingerprintService.message
            role: "caption"
            color: FingerprintService.messageError ? Colors.danger : Colors.mutedText
            wrapMode: Text.Wrap
        }
        ShellText {
            Layout.fillWidth: true
            visible: FingerprintService.available && FingerprintService.blockedReason.length > 0
            text: FingerprintService.blockedReason + "."
            role: "caption"
            wrapMode: Text.Wrap
        }
    }
}
