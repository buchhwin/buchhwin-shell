import QtQuick
import QtQuick.Layouts
import QtQuick.Window
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
    // Waiting rather than empty - a scan, a list still loading: the glyph
    // turns, as a busy field's does, and a ten-second Wi-Fi scan no longer
    // sits under a still hourglass that reads as frozen. Every waiting state
    // already shows the hourglass (Icons.busy), so that is what turns it on.
    // Turning is Full's, as every endless animation is; Reduced and Off keep
    // the hourglass. And only while its window is on screen: a page kept in
    // a closed panel would turn for nobody.
    property bool busy: icon === Icons.busy
    readonly property bool spinning: busy && Animations.motionEnabled && visible
        && Window.visibility !== Window.Hidden
    onSpinningChanged: if (!spinning) mark.rotation = 0

    spacing: Metrics.spaceSm

    GridLayout {
        Layout.fillWidth: true
        Layout.alignment: root.row ? Qt.AlignLeft : Qt.AlignHCenter
        columns: root.row ? 2 : 1
        columnSpacing: Metrics.spaceMd
        rowSpacing: Metrics.spaceSm

        ShellIcon {
            id: mark
            Layout.alignment: root.row ? Qt.AlignTop : Qt.AlignHCenter
            visible: root.icon.length > 0
            glyph: root.spinning ? Icons.refresh : root.icon
            size: root.row ? Metrics.iconLg : Metrics.iconXl
            color: Colors.subtleText
            RotationAnimation on rotation {
                running: root.spinning
                from: 0
                to: 360
                loops: Animation.Infinite
                duration: Animations.spinner
            }
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
