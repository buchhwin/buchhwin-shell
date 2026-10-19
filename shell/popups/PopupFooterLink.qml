import QtQuick
import QtQuick.Layouts
import qs.theme
import qs.shell.components

// Last popup row: divider and a link to the full settings page or panel.
ColumnLayout {
    id: root
    property string text: ""
    property string glyph: Icons.settings
    // The link takes the user out of this popup - to Settings, to an app - and
    // its mark says so, as the tiles and chips that open Settings do
    // (Icons.leavesPanel). The forward chevron is for more of the same thing,
    // in a panel of the shell's own.
    property bool leaves: true
    signal clicked()
    spacing: Metrics.spaceXs

    Divider {}

    // A control like every other: the panel's keys reach it (focusOnTab is
    // what NavLogic looks for), Return/Enter/Space follow it, a press dips.
    Rectangle {
        id: link
        property bool focusOnTab: false
        Layout.fillWidth: true
        implicitHeight: Metrics.controlHeight
        radius: Metrics.radiusCard
        activeFocusOnTab: focusOnTab
        color: mouse.pressed && mouse.containsMouse ? Colors.pressed : mouse.containsMouse ? Colors.hover : "transparent"
        Behavior on color { ColorAnimation { duration: Animations.hover; easing.type: Animations.easing } }
        Keys.onReturnPressed: root.clicked()
        Keys.onEnterPressed: root.clicked()
        Keys.onSpacePressed: root.clicked()
        Accessible.role: Accessible.Link
        Accessible.name: root.text
        Accessible.onPressAction: root.clicked()
        FocusRing { active: link.activeFocus; controlRadius: link.radius }

        RowLayout {
            anchors.fill: parent
            anchors.leftMargin: Metrics.spaceSm
            anchors.rightMargin: Metrics.spaceSm
            spacing: Metrics.spaceSm
            ShellIcon { glyph: root.glyph; size: Metrics.iconSm; color: Colors.mutedText }
            ShellText { Layout.fillWidth: true; text: root.text }
            ShellIcon { glyph: root.leaves ? Icons.leavesPanel : Icons.forward; size: Metrics.iconXs; color: Colors.mutedText }
        }

        MouseArea {
            id: mouse
            anchors.fill: parent
            hoverEnabled: true
            cursorShape: Qt.PointingHandCursor
            onClicked: root.clicked()
        }
    }
}
