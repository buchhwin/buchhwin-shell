import Quickshell
import QtQuick
import QtQuick.Effects
import QtQuick.Layouts
import qs.theme
import qs.services
import qs.shell.components
import "../../services/arrange/ArrangeLogic.js" as Arrange
import "../../services/LayoutLogic.js" as LayoutLogic
import "../../services/notch/NotchLogic.js" as NotchLogic

// One screen of the lock screen (macOS style): the blurred capture of this
// screen, date and a large clock at the top, avatar, name and password at the
// bottom. Optional extras (Settings > Lock Screen): media, battery and keyboard
// layout, power buttons. Keys go to the shared state in LockScreen.
Item {
    id: root
    required property var lockState
    required property string screenName
    focus: true

    // Staggered entrance: backdrop, then date and clock, then the login block.
    // Unlocking reverses everything at once.
    readonly property real topIn: Math.max(0, Math.min(1, (lockState.fade * (1 + staggerSpan) - stagger(1)) ))
    readonly property real bottomIn: Math.max(0, Math.min(1, (lockState.fade * (1 + staggerSpan) - stagger(2)) ))
    readonly property real staggerSpan: Animations.lockEnter > 0 ? 2 * Animations.lockStagger / Animations.lockEnter : 0
    function stagger(step) { return lockState.unlocking ? 0 : step * Animations.lockStagger / Math.max(1, Animations.lockEnter) }
    readonly property real travel: Animations.motionEnabled ? Metrics.spaceXl * 2 : 0

    readonly property string backdrop: lockState.dir.length && screenName.length
        ? "file://" + lockState.dir + "/" + screenName.replace(/[^A-Za-z0-9._-]/g, "_") + ".png" : ""
    property string confirmAction: ""

    Keys.onPressed: event => {
        lockState.keyActivity()
        if (event.key === Qt.Key_Return || event.key === Qt.Key_Enter) lockState.submit()
        else if (event.key === Qt.Key_Backspace) lockState.erase(event.modifiers & Qt.ControlModifier)
        else if (event.key === Qt.Key_Escape) lockState.clear()
        else if (event.text.length && event.text.charCodeAt(0) >= 32) lockState.type(event.text)
        event.accepted = true
    }

    // Background: a tiny blurred capture scaled up and smoothed, slightly darker
    // and more saturated. The base colour of the surface shows until it loads.
    Image {
        id: shot
        anchors.fill: parent
        visible: false
        asynchronous: true
        cache: false
        fillMode: Image.PreserveAspectCrop
        source: root.backdrop
    }
    MultiEffect {
        anchors.fill: parent
        source: shot
        visible: shot.status === Image.Ready
        opacity: Math.min(1, root.lockState.fade * 1.6)
        scale: Animations.motionEnabled ? 1 + Effects.lockZoom * (1 - root.lockState.fade) : 1
        autoPaddingEnabled: false
        blurEnabled: true
        blur: 1
        blurMax: Effects.lockBlurMax
        saturation: Effects.lockSaturation
        brightness: Effects.lockBrightness
    }
    Rectangle { anchors.fill: parent; color: Colors.lockShade }

    Item {
        id: content
        anchors.fill: parent

        SystemClock { id: clock; precision: SystemClock.Minutes }

        // What the user arranged, above the login block. A grid like the
        // notch's and the dashboard's, on the same ArrangeArea - but never
        // dragged here: it is arranged in Settings, on a preview.
        //
        // The whole grid yields to the login block when it comes to the
        // centre, which is the rule the media pill used to carry on its own.
        ArrangeArea {
            id: lockGrid
            anchors.horizontalCenter: parent.horizontalCenter
            anchors.top: parent.top
            anchors.topMargin: Metrics.lockClockTop
            width: Math.min(parent.width - Metrics.spaceXl * 2, Metrics.lockGridWidth)
            height: implicitHeight
            columns: Arrange.columnsFor(width, Metrics.lockGridCell, Metrics.lockGridColumns)
            unit: Metrics.lockGridUnit
            gap: Metrics.spaceLg
            maxRows: LayoutLogic.GRID_MAX_H
            editing: false
            model: root.lockState.lockItems.map(item => ({ id: item.id, w: item.w, h: item.h }))

            opacity: root.topIn * (root.lockState.engaged ? Effects.lockYieldOpacity : 1)
            Behavior on opacity { NumberAnimation { duration: Animations.lockExit; easing.type: Animations.easing } }
            transform: Translate { y: -root.travel * (1 - root.topIn) }

            Repeater {
                model: root.lockState.lockItems
                LockSlot {
                    required property var modelData
                    area: lockGrid
                    blockId: modelData.id
                    type: modelData.type
                    content: root.blockFor(modelData.type)
                }
            }
        }

        RowLayout {
            anchors.top: parent.top
            anchors.right: parent.right
            anchors.margins: Metrics.spaceXl
            opacity: root.topIn
            visible: root.lockState.showStatus
            spacing: Metrics.spaceLg
            ShellText { visible: root.lockState.layout.length > 0; text: root.lockState.layout; color: Colors.lockText; font.weight: Typography.medium }
            RowLayout {
                visible: PowerService.hasBattery
                spacing: Metrics.spaceXs
                ShellText { text: PowerService.percent + "%"; color: Colors.lockText }
                ShellIcon { glyph: PowerService.icon; size: Metrics.iconMd; color: PowerService.charging ? Colors.successOnDark : Colors.lockText }
            }
        }

        // Avatar, name, password and status.
        ColumnLayout {
            id: loginBlock
            anchors.horizontalCenter: parent.horizontalCenter
            anchors.bottom: parent.bottom
            // Glides to the middle of the screen while typing.
            anchors.bottomMargin: root.lockState.engaged ? (parent.height - implicitHeight) / 2 : Metrics.lockBottomMargin
            Behavior on anchors.bottomMargin {
                NumberAnimation {
                    duration: Animations.move(Animations.lockEnter)
                    easing.type: Animations.easingControl
                    easing.overshoot: Animations.overshootSoft
                }
            }
            scale: root.lockState.engaged && Animations.motionEnabled ? Effects.lockEngagedScale : 1
            Behavior on scale { NumberAnimation { duration: Animations.move(Animations.lockEnter); easing.type: Animations.easing } }
            spacing: Metrics.spaceMd
            opacity: root.bottomIn
            transform: Translate { y: root.travel * (1 - root.bottomIn) }

            Item {
                id: avatarItem
                Layout.alignment: Qt.AlignHCenter
                visible: root.lockState.showAvatar
                implicitWidth: Metrics.lockAvatarSize
                implicitHeight: Metrics.lockAvatarSize
                // Gentle pulse while the password is checked.
                SequentialAnimation on scale {
                    running: root.lockState.busy && Animations.motionEnabled
                    loops: Animation.Infinite
                    NumberAnimation { to: 1.05; duration: Animations.lockPulse / 2; easing.type: Easing.InOutSine }
                    NumberAnimation { to: 1; duration: Animations.lockPulse / 2; easing.type: Easing.InOutSine }
                    onRunningChanged: if (!running) avatarItem.scale = 1
                }
                layer.enabled: true
                layer.effect: MultiEffect { shadowEnabled: true; shadowColor: Colors.lockBase; shadowOpacity: Effects.lockClockShadow; shadowBlur: 0.8; shadowVerticalOffset: Effects.shadowOffset / 2 }
                Rectangle {
                    anchors.fill: parent
                    radius: width / 2
                    color: Colors.accent
                    visible: avatar.status !== Image.Ready
                    ShellText { anchors.centerIn: parent; text: root.lockState.initial; color: Colors.accentText; font.pixelSize: Typography.avatarInitialSize; font.weight: Typography.semibold }
                }
                RoundedImage {
                    id: avatar
                    anchors.fill: parent
                    radius: width / 2
                    sourceWidth: Metrics.lockAvatarSize * 2
                    source: root.lockState.avatar.length ? "file://" + root.lockState.avatar : ""
                    visible: status === Image.Ready
                }
            }
            ShellText {
                Layout.alignment: Qt.AlignHCenter
                text: root.lockState.displayName
                color: Colors.lockText
                font.pixelSize: Typography.lockNameSize
                font.weight: Typography.semibold
            }
            PasswordField {
                Layout.alignment: Qt.AlignHCenter
                lockState: root.lockState
            }
            // Status: errors and Caps Lock, or the fingerprint hint (pam_fprintd).
            ShellText {
                Layout.alignment: Qt.AlignHCenter
                Layout.maximumWidth: Metrics.lockMediaWidth
                visible: root.lockState.fingerprint.length === 0
                horizontalAlignment: Text.AlignHCenter
                wrapMode: Text.Wrap
                text: root.lockState.status.length ? root.lockState.status : root.lockState.capsLock ? "Caps Lock is on" : " "
                color: root.lockState.statusIsError ? Colors.lockError : Colors.lockMuted
                role: "small"
            }
            RowLayout {
                Layout.alignment: Qt.AlignHCenter
                visible: root.lockState.fingerprint.length > 0
                spacing: Metrics.spaceXs
                FingerprintGlyph {
                    Layout.preferredWidth: implicitWidth
                    Layout.preferredHeight: implicitHeight
                    size: Metrics.fingerprintLockGlyph
                    mode: root.lockState.fingerprintStage ? "scanning" : "idle"
                    progress: root.lockState.fingerprintStage ? 1 : 0
                    retries: root.lockState.fingerprintMisses
                    color: root.lockState.fingerprint === "mismatch" ? Colors.lockError : Colors.lockText
                    trackColor: Colors.lockMuted
                    errorColor: Colors.lockError
                    // After a timeout a click starts the reader again.
                    MouseArea {
                        anchors.fill: parent
                        enabled: !root.lockState.fingerprintStage
                        cursorShape: enabled ? Qt.PointingHandCursor : Qt.ArrowCursor
                        onClicked: root.lockState.retryFingerprint()
                    }
                }
                ShellText {
                    Layout.maximumWidth: Metrics.lockMediaWidth - Metrics.fingerprintLockGlyph * 2
                    elide: Text.ElideRight
                    text: root.lockState.status
                    color: root.lockState.statusIsError ? Colors.lockError : Colors.lockMuted
                    role: "small"
                }
            }
        }

        // Power buttons (optional): a second click confirms.
        RowLayout {
            anchors.right: parent.right
            anchors.bottom: parent.bottom
            anchors.margins: Metrics.spaceXl
            opacity: root.bottomIn
            visible: root.lockState.showPowerButtons
            spacing: Metrics.spaceLg
            Repeater {
                model: [
                    { id: "suspend", glyph: "󰤄", label: "Sleep" },
                    { id: "reboot", glyph: "󰜉", label: "Restart" },
                    { id: "poweroff", glyph: "󰐥", label: "Shut down" }
                ]
                ColumnLayout {
                    id: powerButton
                    required property var modelData
                    readonly property bool confirming: root.confirmAction === modelData.id
                    spacing: Metrics.spaceXs
                    Rectangle {
                        Layout.alignment: Qt.AlignHCenter
                        implicitWidth: Metrics.controlHeight + Metrics.spaceSm
                        implicitHeight: implicitWidth
                        radius: width / 2
                        color: powerButton.confirming ? Colors.accent : powerMouse.containsMouse ? Colors.lockButton : Colors.lockField
                        Behavior on color { ColorAnimation { duration: Animations.hover; easing.type: Animations.easing } }
                        ShellIcon { anchors.centerIn: parent; glyph: powerButton.modelData.glyph; size: Metrics.iconMd; color: powerButton.confirming ? Colors.accentText : Colors.lockText }
                        MouseArea {
                            id: powerMouse
                            anchors.fill: parent
                            hoverEnabled: true
                            cursorShape: Qt.PointingHandCursor
                            onClicked: {
                                if (powerButton.confirming) { root.confirmAction = ""; root.lockState.power(powerButton.modelData.id) }
                                else { root.confirmAction = powerButton.modelData.id; confirmReset.restart() }
                            }
                        }
                    }
                    ShellText {
                        Layout.alignment: Qt.AlignHCenter
                        text: powerButton.confirming ? "Click again" : powerButton.modelData.label
                        color: Colors.lockMuted
                        role: "caption"
                    }
                }
            }
        }
        Timer { id: confirmReset; interval: 4000; onTriggered: root.confirmAction = "" }
    }

    // ---- the blocks the grid can draw -------------------------------------
    // One per catalogue type, and each draws for the cell it was given rather
    // than being cut off at its edge. Nothing here is interactive except the
    // player, which is the one exception the lock screen already made.

    function blockFor(type) {
        switch (type) {
        case "clock": return clockBlock
        case "date": return dateBlock
        case "weather": return weatherBlock
        case "media": return mediaBlock
        case "events": return eventsBlock
        case "battery": return batteryBlock
        case "keyboard": return keyboardBlock
        }
        return null
    }

    component LockLabel: ShellText {
        color: Colors.lockText
        layer.enabled: true
        layer.effect: MultiEffect {
            shadowEnabled: true
            shadowColor: Colors.lockBase
            shadowOpacity: Effects.lockClockShadow
            shadowBlur: 0.5
            shadowVerticalOffset: Effects.shadowOffset / 3
        }
    }

    Component {
        id: clockBlock
        Item {
            // The digits, and only the digits. The date used to sit above them
            // because there was one block for both; there is a date block now,
            // and a thing drawn in two places is a thing that disagrees with
            // itself - the default arrangement showed the date twice.
            LockClock {
                anchors.centerIn: parent
                time: clock.date
            }
        }
    }

    Component {
        id: dateBlock
        Item {
            LockLabel {
                anchors.centerIn: parent
                width: parent.width
                horizontalAlignment: Text.AlignHCenter
                elide: Text.ElideRight
                text: SettingsService.locale.toString(clock.date,
                    gridW >= 2 ? "dddd, d MMMM" : "ddd, d MMM")
                font.pixelSize: Typography.lockDateSize
                font.weight: Typography.semibold
            }
        }
    }

    Component {
        id: weatherBlock
        Item {
            readonly property var current: WeatherService.current
            Component.onCompleted: WeatherService.track()
            Component.onDestruction: WeatherService.untrack()
            Column {
                anchors.centerIn: parent
                spacing: Metrics.spaceXxs
                Row {
                    anchors.horizontalCenter: parent.horizontalCenter
                    spacing: Metrics.spaceSm
                    ShellIcon {
                        anchors.verticalCenter: parent.verticalCenter
                        glyph: current ? current.icon : ""
                        size: Metrics.iconLg
                        color: Colors.lockText
                    }
                    LockLabel {
                        anchors.verticalCenter: parent.verticalCenter
                        text: current ? WeatherService.formatTemperature(current.temperature) : ""
                        font.pixelSize: Typography.lockDateSize
                    }
                }
                // The condition is the line a short cell does without.
                LockLabel {
                    anchors.horizontalCenter: parent.horizontalCenter
                    visible: gridH >= 2 && text.length > 0
                    text: current ? current.label : ""
                    role: "small"
                    color: Colors.lockMuted
                }
            }
        }
    }

    Component {
        id: eventsBlock
        Item {
            id: eventBody
            // The same "what is next" the notch asks for, from the same pure
            // function, so the two never disagree about which event that is.
            readonly property var event: NotchLogic.nextEvent(CalendarService.eventsFor(clock.date), clock.date)
            Column {
                anchors.centerIn: parent
                width: parent.width
                spacing: 0
                LockLabel {
                    width: parent.width
                    horizontalAlignment: Text.AlignHCenter
                    elide: Text.ElideRight
                    text: eventBody.event ? eventBody.event.title : "Nothing scheduled"
                    color: eventBody.event ? Colors.lockText : Colors.lockMuted
                    role: "bodyLarge"
                }
                // When it is, once the cell has a second row for it.
                LockLabel {
                    width: parent.width
                    horizontalAlignment: Text.AlignHCenter
                    visible: gridH >= 2 && eventBody.event !== null
                    text: eventBody.event ? NotchLogic.eventWhen(eventBody.event, clock.date) : ""
                    color: Colors.lockMuted
                    role: "small"
                }
            }
        }
    }

    Component {
        id: mediaBlock
        Item {
            // The one interactive thing on the lock screen, and it was already
            // here before the grid was: a lock screen may skip a track, it may
            // not be a way around the lock.
            readonly property bool playing: MprisService.hasPlayer
            Rectangle {
                anchors.fill: parent
                radius: Metrics.radiusCard
                color: Colors.lockField
                visible: parent.playing
            }
            LockLabel {
                anchors.centerIn: parent
                visible: !parent.playing
                text: "Nothing playing"
                color: Colors.lockMuted
                role: "small"
            }
            RowLayout {
                id: mediaRow
                anchors.left: parent.left
                anchors.right: parent.right
                anchors.verticalCenter: parent.verticalCenter
                anchors.margins: Metrics.spaceMd
                visible: parent.playing
                spacing: Metrics.spaceMd
                RoundedImage {
                    Layout.preferredWidth: Metrics.iconXl + Metrics.spaceSm
                    Layout.preferredHeight: Metrics.iconXl + Metrics.spaceSm
                    radius: Metrics.radiusInner
                    source: MprisService.artUrl
                    visible: MprisService.artUrl.length > 0
                }
                ColumnLayout {
                    Layout.fillWidth: true
                    spacing: 0
                    ShellText { Layout.fillWidth: true; text: MprisService.title; color: Colors.lockText; elide: Text.ElideRight }
                    ShellText { Layout.fillWidth: true; text: MprisService.artist; role: "small"; color: Colors.lockMuted; elide: Text.ElideRight; visible: text.length > 0 }
                }
                Repeater {
                    // Three buttons need the width; a narrow cell keeps the
                    // one that matters.
                    model: gridW >= 2
                        ? [{ glyph: Icons.previous, run: () => MprisService.previous() },
                           { glyph: MprisService.playing ? Icons.pause : Icons.play, run: () => MprisService.togglePlaying() },
                           { glyph: Icons.next, run: () => MprisService.next() }]
                        : [{ glyph: MprisService.playing ? Icons.pause : Icons.play, run: () => MprisService.togglePlaying() }]
                    Rectangle {
                        id: mediaButton
                        required property var modelData
                        implicitWidth: Metrics.iconLg + Metrics.spaceSm
                        implicitHeight: implicitWidth
                        radius: width / 2
                        color: mediaMouse.containsMouse ? Colors.lockGlyphHover : "transparent"
                        Behavior on color { ColorAnimation { duration: Animations.hover; easing.type: Animations.easing } }
                        ShellIcon { anchors.centerIn: parent; glyph: mediaButton.modelData.glyph; size: Metrics.iconMd; color: Colors.lockText }
                        MouseArea {
                            id: mediaMouse
                            anchors.fill: parent
                            hoverEnabled: true
                            cursorShape: Qt.PointingHandCursor
                            onClicked: mediaButton.modelData.run()
                        }
                    }
                }
            }
        }
    }

    Component {
        id: batteryBlock
        Item {
            Row {
                anchors.centerIn: parent
                spacing: Metrics.spaceXs
                ShellIcon {
                    anchors.verticalCenter: parent.verticalCenter
                    glyph: PowerService.icon
                    size: Metrics.iconMd
                    color: PowerService.charging ? Colors.successOnDark : Colors.lockText
                }
                LockLabel {
                    anchors.verticalCenter: parent.verticalCenter
                    visible: PowerService.hasBattery
                    text: PowerService.percent + "%"
                    role: "bodyLarge"
                }
            }
        }
    }

    Component {
        id: keyboardBlock
        Item {
            LockLabel {
                anchors.centerIn: parent
                visible: root.lockState.layout.length > 0
                text: root.lockState.layout
                role: "bodyLarge"
            }
        }
    }
}
