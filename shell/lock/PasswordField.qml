import QtQuick
import QtQuick.Layouts
import qs.theme
import qs.shell.components

// macOS-style password pill: dots for the typed characters, an arrow button
// once something is typed, a shake on a wrong password. The text itself lives
// in LockScreen so every screen shows the same field.
Item {
    id: root
    required property var lockState
    implicitWidth: Metrics.lockFieldWidth
    implicitHeight: Metrics.lockFieldHeight

    readonly property int length: Array.from(lockState.password).length

    Connections {
        target: root.lockState
        // Movement only in the moving modes; Reduced and Off keep the field
        // still and leave the message to say what happened.
        function onShakesChanged() {
            if (Animations.motionEnabled) shake.restart()
            else offset.x = 0
        }
    }

    Rectangle {
        id: pill
        anchors.fill: parent
        radius: height / 2
        color: Colors.lockField
        border.width: Metrics.borderWidth
        border.color: Colors.lockFieldBorder
        transform: Translate { id: offset }

        ShellText {
            anchors.left: parent.left
            anchors.leftMargin: Metrics.spaceLg
            anchors.verticalCenter: parent.verticalCenter
            visible: root.length === 0
            text: root.lockState.busy ? "Checking …" : "Enter Password"
            color: Colors.lockMuted
        }

        ShellText {
            anchors.left: parent.left
            anchors.right: button.left
            anchors.leftMargin: Metrics.spaceLg
            anchors.rightMargin: Metrics.spaceSm
            anchors.verticalCenter: parent.verticalCenter
            visible: root.length > 0
            text: "•".repeat(Math.min(root.length, 24))
            color: Colors.lockText
            font.letterSpacing: Typography.captionTracking
            elide: Text.ElideLeft
            opacity: root.lockState.busy ? Effects.mutedOpacity : 1
        }

        Rectangle {
            id: button
            anchors.right: parent.right
            anchors.rightMargin: Metrics.spaceXs
            anchors.verticalCenter: parent.verticalCenter
            width: parent.height - Metrics.spaceXs * 2
            height: width
            radius: width / 2
            // It had a pointing hand but no hover at all, while the same
            // control on the login screen (session/sddm PasswordPill) has one.
            color: submitMouse.containsMouse ? Colors.lockButtonHover : Colors.lockButton
            scale: Animations.motionEnabled && submitMouse.pressed ? Effects.pressScale : 1
            opacity: root.length > 0 && !root.lockState.busy ? 1 : 0
            visible: opacity > 0
            Behavior on opacity { NumberAnimation { duration: Animations.hover } }
            Behavior on color { ColorAnimation { duration: Animations.hover; easing.type: Animations.easing } }
            Behavior on scale { NumberAnimation { duration: Animations.move(Animations.press); easing.type: Animations.easing } }
            ShellIcon { anchors.centerIn: parent; glyph: "󰁔"; size: Metrics.iconSm; color: Colors.lockText }
            MouseArea {
                id: submitMouse
                anchors.fill: parent
                hoverEnabled: true
                cursorShape: Qt.PointingHandCursor
                onClicked: root.lockState.submit()
            }
        }
    }

    // Three fast swings at full amplitude, then back to rest (~0.4 s).
    SequentialAnimation {
        id: shake
        NumberAnimation { target: offset; property: "x"; to: Metrics.shakeOffset; duration: Animations.shakeOut; easing.type: Animations.easingShake }
        NumberAnimation { target: offset; property: "x"; to: -Metrics.shakeOffset; duration: Animations.shakeSwing; easing.type: Animations.easingShake }
        NumberAnimation { target: offset; property: "x"; to: Metrics.shakeOffset; duration: Animations.shakeSwing; easing.type: Animations.easingShake }
        NumberAnimation { target: offset; property: "x"; to: 0; duration: Animations.shakeSwing; easing.type: Animations.easingShake }
    }
}
