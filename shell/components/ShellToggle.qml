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
        // On is the accent as a fill that has to stand off the card
        // (Colors.accentFill): the light teal on a light card was 1.08:1.
        color: root.checked ? (root.down ? Colors.accentFillPressed : mouse.containsMouse ? Colors.accentFillHover : Colors.accentFill)
            : mouse.containsMouse ? Colors.trackHover : Colors.track
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
            Behavior on x { enabled: Animations.motionEnabled; SpringMotion { kind: "fast" } }
            Behavior on scale { NumberAnimation { duration: Animations.move(Animations.press); easing.type: Animations.easing } }
        }
    }

    FocusRing { active: root.activeFocus; controlRadius: Metrics.pillRadius(root.height) }

    // Every way in asks `enabledState`, not only the mouse: a switch that is
    // disabled while it has the focus flipped on Return and Space anyway.
    function flip() { if (root.enabledState) root.toggled(!root.checked) }
    Keys.onReturnPressed: root.flip()
    Keys.onEnterPressed: root.flip()
    Keys.onSpacePressed: root.flip()

    // The row's label names it (SettingRow, ListRow); a switch outside a row
    // gets `accessibleName` from its caller, or a screen reader has only
    // "check box, checked" to say.
    property string accessibleName: ""
    Accessible.role: Accessible.CheckBox
    Accessible.name: root.accessibleName
    Accessible.checkable: true
    Accessible.checked: root.checked
    Accessible.onToggleAction: root.flip()

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
