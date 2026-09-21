import QtQuick
import qs.theme

// Animated fingerprint: ripples while the reader waits for a finger, fills
// from the bottom with `progress`, shakes when `retries` grows, pops a check
// mark when done and turns red when it failed.
// mode: "idle", "scanning", "done", "failed".
Item {
    id: root
    property string mode: "idle"
    property real progress: 0
    property int retries: 0
    property int size: Metrics.fingerprintGlyph
    property color color: Colors.accentForeground
    property color trackColor: Colors.subtleText
    property color successColor: Colors.success
    property color errorColor: Colors.danger
    property color badgeTextColor: Colors.accentText

    implicitWidth: size * 1.5
    implicitHeight: size * 1.5

    readonly property color activeColor: mode === "failed" ? errorColor : mode === "done" ? successColor : color
    property real shown: 0
    Binding on shown { value: root.mode === "done" ? 1 : Math.max(0, Math.min(1, root.progress)) }
    Behavior on shown { NumberAnimation { duration: Animations.fingerprintFill; easing.type: Easing.OutCubic } }

    onRetriesChanged: if (retries > 0 && Animations.motionEnabled) shake.restart()

    // Ripples while scanning.
    Repeater {
        model: 2
        Rectangle {
            id: ripple
            required property int index
            anchors.centerIn: parent
            width: root.size
            height: width
            radius: width / 2
            color: "transparent"
            border.width: Metrics.focusBorderWidth
            border.color: root.activeColor
            opacity: 0
            scale: 0.8
            visible: root.mode === "scanning" && Animations.motionEnabled
            SequentialAnimation {
                running: ripple.visible
                loops: Animation.Infinite
                PauseAnimation { duration: ripple.index * Animations.fingerprintRipple / 2 }
                ParallelAnimation {
                    NumberAnimation { target: ripple; property: "scale"; from: 0.8; to: 1.45; duration: Animations.fingerprintRipple; easing.type: Easing.OutCubic }
                    NumberAnimation { target: ripple; property: "opacity"; from: 0.45; to: 0; duration: Animations.fingerprintRipple; easing.type: Easing.OutCubic }
                }
                onRunningChanged: if (!running) { ripple.opacity = 0; ripple.scale = 0.8 }
            }
        }
    }

    Item {
        id: glyphBox
        anchors.centerIn: parent
        width: base.implicitWidth
        height: base.implicitHeight
        transform: Translate { id: offset }

        ShellIcon {
            id: base
            anchors.fill: parent
            glyph: "󰈷"
            size: root.size
            color: root.mode === "failed" ? root.errorColor : root.trackColor
            Behavior on color { ColorAnimation { duration: Animations.fingerprintFill } }
        }
        // The filled part, clipped from the bottom.
        Item {
            anchors.left: parent.left
            anchors.right: parent.right
            anchors.bottom: parent.bottom
            height: parent.height * root.shown
            clip: true
            visible: root.mode !== "failed"
            ShellIcon {
                anchors.left: parent.left
                anchors.bottom: parent.bottom
                width: glyphBox.width
                height: glyphBox.height
                glyph: "󰈷"
                size: root.size
                color: root.activeColor
            }
        }
    }

    // Check mark or cross when finished.
    Rectangle {
        anchors.right: glyphBox.right
        anchors.bottom: glyphBox.bottom
        anchors.rightMargin: -width / 4
        width: root.size * 0.42
        height: width
        radius: width / 2
        color: root.activeColor
        visible: scale > 0
        scale: root.mode === "done" || root.mode === "failed" ? 1 : 0
        Behavior on scale { NumberAnimation { duration: Animations.lockPop * 2; easing.type: Easing.OutBack; easing.overshoot: 2 } }
        ShellIcon {
            anchors.centerIn: parent
            glyph: root.mode === "failed" ? Icons.close : Icons.check
            size: parent.width * 0.7
            color: root.badgeTextColor
        }
    }

    // The same three swings as the password field, so a rejected finger and a
    // rejected password read as one gesture.
    SequentialAnimation {
        id: shake
        NumberAnimation { target: offset; property: "x"; to: Metrics.shakeOffset; duration: Animations.shakeOut; easing.type: Animations.easingShake }
        NumberAnimation { target: offset; property: "x"; to: -Metrics.shakeOffset; duration: Animations.shakeSwing; easing.type: Animations.easingShake }
        NumberAnimation { target: offset; property: "x"; to: Metrics.shakeOffset; duration: Animations.shakeSwing; easing.type: Animations.easingShake }
        NumberAnimation { target: offset; property: "x"; to: 0; duration: Animations.shakeSwing; easing.type: Animations.easingShake }
    }
}
