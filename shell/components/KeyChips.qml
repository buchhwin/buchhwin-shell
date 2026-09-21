import QtQuick
import QtQuick.Layouts
import qs.theme

// Key combination as small key caps: ["Super", "Shift", "T"].
RowLayout {
    id: root
    property var keys: []
    property bool accent: false
    spacing: Metrics.spaceXxs

    Repeater {
        model: root.keys
        Rectangle {
            required property string modelData
            implicitHeight: Metrics.controlHeightSm - Metrics.spaceXs
            implicitWidth: Math.max(implicitHeight, label.implicitWidth + Metrics.spaceSm * 2)
            radius: Metrics.radiusTiny
            color: root.accent ? Colors.accentSoft : Colors.elevatedSurface
            border.width: Metrics.borderWidth
            border.color: Colors.border
            ShellText {
                id: label
                anchors.centerIn: parent
                text: modelData
                role: "small"
                color: root.accent ? Colors.accentForeground : Colors.text
            }
        }
    }
}
