import QtQuick
import qs.theme
import qs.shell.components

// One round colour swatch on a settings page: the accent, the panel colour and
// the terminal's prompt and error colours. Those were a Rectangle with a
// MouseArea in four places, which Tab walked past and a screen reader found no
// name for. This one is a stop for Tab like every other control on the page,
// Return or Space chooses it as a click does, and it says what it is - in a
// tooltip and to a screen reader - which the circle alone never did.
Rectangle {
    id: root
    property color fill: "transparent"
    property string label: ""
    property bool selected: false
    // A mark while not selected (the shell's accent, the theme's colours);
    // the selected one shows the check.
    property string mark: ""
    property color markColor: Colors.textOn(root.fill)
    // Always a hairline, and the accent line when selected: for the panel
    // colours, some of which are the panel's own colour and vanish without.
    property bool outlined: false
    property bool focusOnTab: true
    signal activated()

    readonly property bool hovered: mouse.containsMouse
    width: Metrics.controlHeight
    height: width
    radius: width / 2
    color: root.fill
    border.width: root.selected ? Metrics.focusBorderWidth + 1
        : root.outlined ? (root.hovered ? Metrics.focusBorderWidth : Metrics.borderWidth)
        : root.hovered ? Metrics.borderWidth : 0
    border.color: root.selected ? (root.outlined ? Colors.accentLine : Colors.text)
        : root.outlined && root.hovered ? Colors.text : Colors.borderStrong
    scale: mouse.pressed ? Effects.pressScale : 1
    Behavior on scale { NumberAnimation { duration: Animations.move(Animations.press); easing.type: Animations.easing } }

    activeFocusOnTab: root.focusOnTab
    Keys.onReturnPressed: root.choose()
    Keys.onEnterPressed: root.choose()
    Keys.onSpacePressed: root.choose()
    Accessible.role: Accessible.Button
    Accessible.name: root.label
    Accessible.checkable: true
    Accessible.checked: root.selected
    Accessible.onPressAction: root.choose()
    FocusRing { active: root.activeFocus; controlRadius: root.radius }

    ShellIcon {
        anchors.centerIn: parent
        visible: root.selected || root.mark.length > 0
        glyph: root.selected ? Icons.check : root.mark
        size: Metrics.iconSm
        color: root.markColor
    }

    function choose() {
        tip.release()
        root.activated()
    }

    MouseArea {
        id: mouse
        anchors.fill: parent
        hoverEnabled: true
        cursorShape: Qt.PointingHandCursor
        onClicked: root.choose()
        onEntered: tip.arm()
        onExited: tip.release()
    }

    ToolTipHost {
        id: tip
        anchorItem: root
        text: root.label
    }
}
