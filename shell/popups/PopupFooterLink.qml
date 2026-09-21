import QtQuick
import QtQuick.Layouts
import qs.theme
import qs.shell.components

// Last popup row: divider and a link to the full settings page or panel.
ColumnLayout {
    id: root
    property string text: ""
    property string glyph: Icons.settings
    signal clicked()
    spacing: Metrics.spaceXs

    Rectangle { Layout.fillWidth: true; implicitHeight: Metrics.borderWidth; color: Colors.border }

    Rectangle {
        Layout.fillWidth: true
        implicitHeight: Metrics.controlHeight
        radius: Metrics.radiusCard
        color: mouse.containsMouse ? Colors.hover : "transparent"
        Behavior on color { ColorAnimation { duration: Animations.hover } }

        RowLayout {
            anchors.fill: parent
            anchors.leftMargin: Metrics.spaceSm
            anchors.rightMargin: Metrics.spaceSm
            spacing: Metrics.spaceSm
            ShellIcon { glyph: root.glyph; size: Metrics.iconSm; color: Colors.mutedText }
            ShellText { Layout.fillWidth: true; text: root.text }
            ShellIcon { glyph: Icons.forward; size: Metrics.iconXs; color: Colors.mutedText }
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
