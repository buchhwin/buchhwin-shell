import Quickshell
import QtQuick
import QtQuick.Layouts
import qs.theme
import qs.services
import qs.shell.components
import "../../../services/lock/LockCatalogue.js" as Lock
import "../../../services/fingerprint/FingerprintLogic.js" as FingerprintLogic

// Settings > Lock Screen: what the macOS-style lock screen shows (changes apply
// the next time the screen locks) and fingerprints (fprintd): enrolled fingers
// with Delete and a guided enrollment.
ColumnLayout {
    id: root
    spacing: Metrics.pageGap

    // Finger selector shown before an enrollment starts.
    property bool enrollOpen: false
    property string enrollFinger: FingerprintService.defaultFinger()
    readonly property var enrollment: FingerprintService.enrollment
    // Arch with no pam_fprintd in the lock's PAM file (nor in system-auth):
    // the lock cannot offer the reader whatever the mode says
    // (FingerprintLogic.pamLineMissing).
    readonly property bool pamLineMissing: FingerprintLogic.pamLineMissing(DistroService.family, FingerprintService.lockEnabled)

    PageActivity {
        onOpened: FingerprintService.track()
        onClosed: FingerprintService.untrack()
    }

    SettingsSection {
        Layout.fillWidth: true
        title: "Lock screen"
        hint: "The screen behind the lock is blurred so nothing on it can be read. When to lock automatically is set under Power."

        RowLayout {
            ShellIcon { glyph: Icons.lock; size: Metrics.iconLg; color: Colors.accentForeground }
            ShellText { Layout.fillWidth: true; text: ShortcutService.keyHint("SUPER + L", true) + " locks the screen"; muted: true }
            ShellButton {
                focusOnTab: true
                text: "Lock now"
                icon: Icons.lock
                variant: "accent"
                compact: true
                onClicked: { PanelService.close(); SessionService.run("lock") }
            }
        }
    }

    SettingsSection {
        Layout.fillWidth: true
        title: "What the lock screen shows"
        hint: "Drag to arrange, pull a corner to size. Applies the next time the screen locks."

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
                confirmText: "Reset?"
                onClicked: LayoutService.lockResetLayout()
            }
        }
    }

    SettingsSection {
        Layout.fillWidth: true
        title: "The corners"
        hint: "Applies the next time the screen locks."

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
        scope: "lock.fingerprint"
        // While the card for password dialogs offers a command, the hint
        // says what it changes; the card keeps only the command.
        hint: "Unlock the lock screen with a finger; typing your password always works too."
            + (FingerprintService.available && ["on", "off"].indexOf(FingerprintService.polkitState) >= 0
               ? " A password dialog that takes the finger waits ten seconds for it, then asks for the password; the login screen and sudo stay as they are." : "")

        ListRow {
            Layout.fillWidth: true
            interactive: false
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
            // While one of the two PAM cards below is shown, its why is said
            // here: the card keeps only the command and its copy button.
            SettingRow {
                Layout.fillWidth: true
                label: "Use fingerprint"
                hint: "Automatic turns it off while the lid is closed, as on a docking station. It applies to this lock screen only."
                    + (FingerprintService.systemOnly ? " The login screen, sudo and password dialogs go through PAM, where the reader is on system-wide." : "")
                    + (root.pamLineMissing ? " On Arch the reader goes into the lock screen's own PAM file: in system-auth the login screen and sudo would wait for the finger, and a finger login cannot open the wallet." : "")
                SegmentedControl {
                    focusOnTab: true
                    Layout.fillWidth: true
                    current: FingerprintService.mode
                    options: [
                        { value: "auto", label: "Automatic", icon: "󰌢" },
                        { value: "on", label: "On", icon: "󰈷" },
                        { value: "off", label: "Off", icon: Icons.lock }
                    ]
                    onSelected: value => FingerprintService.setMode(value)
                }
            }
            // "Off" here and still being asked for a finger is not a broken
            // button: the login screen, sudo and every polkit dialog go
            // through the system-wide PAM stack, where authselect (Fedora),
            // pam-config (openSUSE) or a hand-made line in system-auth (Arch)
            // puts the reader.
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
                        text: "To turn it off everywhere, run this once and log in again:"
                        role: "caption"
                        wrapMode: Text.Wrap
                    }
                    ShellText {
                        Layout.fillWidth: true
                        text: DistroService.fingerprintOffCommand
                        font.family: Typography.monoFamily
                        wrapMode: Text.Wrap
                    }
                    ShellButton {
                        focusOnTab: true
                        icon: Icons.copy
                        text: "Copy command"
                        onClicked: Quickshell.clipboardText = DistroService.fingerprintOffCommand
                    }
                }
            }
            // Arch turns the reader on by hand, and until the line is in the
            // lock's own /etc/pam.d/buchhwin-lock the lock has no reader to
            // offer. Not in system-auth, which SDDM and sudo include as well
            // (DistroLogic.fingerprintOnCommand). The command is the user's
            // to run, with sudo.
            ShellCard {
                Layout.fillWidth: true
                visible: root.pamLineMissing
                implicitHeight: pamNote.implicitHeight + Metrics.spaceMd * 2
                ColumnLayout {
                    id: pamNote
                    anchors.fill: parent
                    anchors.margins: Metrics.spaceMd
                    spacing: Metrics.spaceXs
                    ShellText {
                        Layout.fillWidth: true
                        text: "The reader is not in the lock screen's PAM file yet"
                        wrapMode: Text.Wrap
                    }
                    ShellText {
                        Layout.fillWidth: true
                        text: "Run this once, then the lock screen offers the finger:"
                        role: "caption"
                        wrapMode: Text.Wrap
                    }
                    ShellText {
                        Layout.fillWidth: true
                        text: DistroService.fingerprintOnCommand
                        font.family: Typography.monoFamily
                        wrapMode: Text.Wrap
                    }
                    ShellButton {
                        focusOnTab: true
                        icon: Icons.copy
                        text: "Copy command"
                        onClicked: Quickshell.clipboardText = DistroService.fingerprintOnCommand
                    }
                }
            }
            ShellText {
                Layout.fillWidth: true
                text: FingerprintLogic.modeState(FingerprintService.mode, FingerprintService.lidClosed, root.pamLineMissing)
                role: "caption"
                color: FingerprintService.enabledNow && !root.pamLineMissing ? Colors.accentForeground : Colors.mutedText
                wrapMode: Text.Wrap
            }
            // The reader for polkit's password dialogs and nothing else
            // (FingerprintLogic, "the reader for admin prompts only"): a
            // line in /etc/pam.d/polkit-1, put there and taken out again by
            // a command the user runs. The login screen and sudo stay
            // password-only. Both commands are shown while it is off, so
            // the way back is known before the way in is taken.
            ShellCard {
                Layout.fillWidth: true
                visible: FingerprintService.available && ["on", "off", "system"].indexOf(FingerprintService.polkitState) >= 0
                implicitHeight: polkitNote.implicitHeight + Metrics.spaceMd * 2
                ColumnLayout {
                    id: polkitNote
                    anchors.fill: parent
                    anchors.margins: Metrics.spaceMd
                    spacing: Metrics.spaceXs
                    readonly property string answer: FingerprintService.polkitState
                    readonly property string onCommand: FingerprintLogic.polkitOnCommand(DistroService.family)
                    readonly property string offCommand: FingerprintLogic.polkitOffCommand(DistroService.family)
                    ShellText {
                        Layout.fillWidth: true
                        text: "Password dialogs"
                        wrapMode: Text.Wrap
                    }
                    ShellText {
                        Layout.fillWidth: true
                        text: FingerprintLogic.polkitText(polkitNote.answer)
                            + (polkitNote.answer === "off" ? " Run this once to let them take the finger as well:"
                               : polkitNote.answer === "on" ? " This takes the line out of /etc/pam.d/polkit-1 again:" : "")
                        role: "caption"
                        wrapMode: Text.Wrap
                    }
                    ShellText {
                        Layout.fillWidth: true
                        visible: polkitNote.answer === "off"
                        text: polkitNote.onCommand
                        font.family: Typography.monoFamily
                        wrapMode: Text.Wrap
                    }
                    ShellButton {
                        focusOnTab: true
                        visible: polkitNote.answer === "off"
                        icon: Icons.copy
                        text: "Copy command"
                        onClicked: Quickshell.clipboardText = polkitNote.onCommand
                    }
                    ShellText {
                        Layout.fillWidth: true
                        visible: polkitNote.answer === "off"
                        text: "The way back, should you want it:"
                        role: "caption"
                        wrapMode: Text.Wrap
                    }
                    ShellText {
                        Layout.fillWidth: true
                        visible: polkitNote.answer !== "system"
                        text: polkitNote.offCommand
                        font.family: Typography.monoFamily
                        wrapMode: Text.Wrap
                    }
                    ShellButton {
                        focusOnTab: true
                        visible: polkitNote.answer !== "system"
                        icon: Icons.copy
                        text: polkitNote.answer === "on" ? "Copy command" : "Copy the way back"
                        onClicked: Quickshell.clipboardText = polkitNote.offCommand
                    }
                }
            }
        }

        Repeater {
            model: FingerprintService.fingers
            ListRow {
                id: fingerRow
                required property string modelData
                Layout.fillWidth: true
                interactive: false
                icon: "󰈷"
                title: FingerprintService.fingerLabel(modelData)
                subtitle: FingerprintService.deleting === modelData ? "Deleting …"
                    : root.pamLineMissing ? "Enrolled" : "Unlocks the lock screen"
                ShellButton {
                    focusOnTab: true
                    text: "Delete"
                    icon: Icons.remove
                    compact: true
                    // An enrolled finger cannot be brought back; the button
                    // asks twice, the way every destructive one does.
                    confirm: true
                    confirmText: "Delete?"
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
                hint: "Settings steps aside while the system asks for your password. Place the finger on the reader several times, moving it slightly each time."
                ShellSelect {
                    focusOnTab: true
                    Layout.fillWidth: true
                    options: FingerprintService.fingerOptions
                    current: root.enrollFinger
                    onSelected: value => root.enrollFinger = value
                }
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
                        color: root.enrollment && root.enrollment.success ? Colors.positiveFill : Colors.accentFill
                        Behavior on width { NumberAnimation { duration: Animations.move(Animations.fingerprintFill); easing.type: Animations.easing } }
                    }
                }
                RowLayout {
                    Layout.alignment: Qt.AlignHCenter
                    spacing: Metrics.spaceSm
                    ShellButton {
                        focusOnTab: true
                        visible: FingerprintService.enrolling
                        text: FingerprintService.cancelling ? "Canceling …" : "Cancel"
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
