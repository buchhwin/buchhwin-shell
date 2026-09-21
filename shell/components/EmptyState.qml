import QtQuick
import QtQuick.Layouts
import qs.theme

// The one way a surface says it has nothing to show. `icon` and `description`
// are optional, so the same component covers a bare line in a small popup and
// the centred block of a whole panel. Messages are written without a full stop:
// they are labels, not sentences.
ColumnLayout {
    id: root
    property string icon: ""
    property string title: ""
    property string description: ""
    // A row (an icon beside the text) fits a card inside a page; the column is
    // for an empty panel, where the block sits in the middle of the free space.
    property bool row: false
    default property alias action: actionSlot.data

    spacing: Metrics.spaceSm

    GridLayout {
        Layout.fillWidth: true
        Layout.alignment: root.row ? Qt.AlignLeft : Qt.AlignHCenter
        columns: root.row ? 2 : 1
        columnSpacing: Metrics.spaceMd
        rowSpacing: Metrics.spaceSm

        ShellIcon {
            Layout.alignment: root.row ? Qt.AlignTop : Qt.AlignHCenter
            visible: root.icon.length > 0
            glyph: root.icon
            size: root.row ? Metrics.iconLg : Metrics.iconXl
            color: Colors.subtleText
        }
        ColumnLayout {
            Layout.fillWidth: true
            spacing: 0
            ShellText {
                Layout.fillWidth: true
                Layout.alignment: root.row ? Qt.AlignLeft : Qt.AlignHCenter
                horizontalAlignment: root.row ? Text.AlignLeft : Text.AlignHCenter
                text: root.title
                role: root.row ? "bodyLarge" : "body"
                muted: !root.row
                wrapMode: Text.Wrap
            }
            ShellText {
                Layout.fillWidth: true
                Layout.alignment: root.row ? Qt.AlignLeft : Qt.AlignHCenter
                horizontalAlignment: root.row ? Text.AlignLeft : Text.AlignHCenter
                visible: text.length > 0
                text: root.description
                role: "small"
                muted: true
                wrapMode: Text.Wrap
            }
        }
    }
    RowLayout {
        id: actionSlot
        Layout.alignment: root.row ? Qt.AlignLeft : Qt.AlignHCenter
        visible: children.length > 0
        spacing: Metrics.spaceSm
    }
}
