import QtQuick
import qs.theme

// One UI switch: a large soft capsule with a big round knob that glides and
// stretches slightly while it is pressed.
Item {
    id: root
    property bool checked: false
    property bool enabledState: true
    property bool focusOnTab: false
    signal toggled(bool checked)

    readonly property bool down: mouse.pressed && mouse.containsMouse
    readonly property int inset: (Metrics.toggleHeight - Metrics.toggleKnob) / 2

    activeFocusOnTab: focusOnTab && enabledState
    implicitWidth: Metrics.toggleWidth
    implicitHeight: Metrics.toggleHeight
    opacity: enabledState ? 1 : Effects.disabledOpacity

    Rectangle {
        id: track
        anchors.fill: parent
        radius: Metrics.pillRadius(height)
        color: root.checked ? (root.down ? Colors.accentPressed : Colors.accent) : Colors.track
        Behavior on color { ColorAnimation { duration: Animations.hover; easing.type: Animations.easing } }

        Rectangle {
            id: knob
            width: Metrics.toggleKnob
            height: Metrics.toggleKnob
            radius: width / 2
            anchors.verticalCenter: parent.verticalCenter
            x: root.checked ? parent.width - width - root.inset : root.inset
            color: Colors.knob
            border.width: Metrics.borderWidth
            border.color: Colors.knobBorder
            scale: root.down ? Effects.knobPressScale : 1
            Behavior on x {
                NumberAnimation {
                    duration: Animations.move(Animations.control)
                    easing.type: Animations.easingControl
                    easing.overshoot: Animations.overshoot
                }
            }
            Behavior on scale { NumberAnimation { duration: Animations.move(Animations.press); easing.type: Animations.easing } }
        }
    }

    FocusRing { active: root.activeFocus; controlRadius: Metrics.pillRadius(root.height) }

    Keys.onReturnPressed: root.toggled(!root.checked)
    Keys.onSpacePressed: root.toggled(!root.checked)

    MouseArea {
        id: mouse
        anchors.fill: parent
        // One UI keeps a generous hit area around the small switch.
        anchors.margins: -Metrics.spaceSm
        hoverEnabled: true
        enabled: root.enabledState
        cursorShape: Qt.PointingHandCursor
        onClicked: root.toggled(!root.checked)
    }
}
