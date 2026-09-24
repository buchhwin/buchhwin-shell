import QtQuick
import QtQuick.Layouts
import qs.theme
import qs.shell.components

// Popup title row: round icon tile (accent while active), heading, status
// line and an optional switch, with a divider below.
ColumnLayout {
    id: root
    property string heading: ""
    property string detail: ""
    property string glyph: ""
    property bool active: false
    property bool hasToggle: false
    property bool checked: false
    property bool toggleEnabled: true
    signal toggled(bool checked)
    spacing: Metrics.panelGap

    RowLayout {
        Layout.fillWidth: true
        spacing: Metrics.spaceMd

        Rectangle {
            Layout.preferredWidth: Metrics.popupIconTile
            Layout.preferredHeight: Metrics.popupIconTile
            radius: width / 2
            color: root.active ? Colors.accent : Colors.elevatedSurface
            Behavior on color { ColorAnimation { duration: Animations.hover } }
            ShellIcon {
                anchors.centerIn: parent
                glyph: root.glyph
                size: Metrics.iconMd
                color: root.active ? Colors.accentText : Colors.text
            }
        }

        ColumnLayout {
            Layout.fillWidth: true
            spacing: 0
            ShellText { Layout.fillWidth: true; text: root.heading; role: "title" }
            ShellText { Layout.fillWidth: true; text: root.detail; role: "small"; muted: true; visible: text.length > 0 }
        }

        ShellToggle {
            focusOnTab: true
            visible: root.hasToggle
            checked: root.checked
            enabledState: root.toggleEnabled
            onToggled: value => root.toggled(value)
        }
    }

    Rectangle { Layout.fillWidth: true; implicitHeight: Metrics.borderWidth; color: Colors.border }
}
