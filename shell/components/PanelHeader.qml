import QtQuick
import QtQuick.Layouts
import qs.theme

// The top line of a panel: an optional back button, the title with an optional
// second line, and a slot for the actions on the right. One header for the
// control center, settings, the notification centre and the dialogs, so a
// title is the same size and sits at the same place wherever it appears.
RowLayout {
    id: root
    property string icon: ""
    // The accent as ink by default; a dialog about a thing that has a colour
    // of its own (an event's calendar) hands that colour in.
    property color iconColor: Colors.accentForeground
    property string title: ""
    property string subtitle: ""
    // "pageTitle" for a panel with its own page area (settings), "headline" for
    // a panel that is one page (control center, notification centre), "title"
    // for a dialog.
    property string role: "headline"
    property bool showBack: false
    default property alias actions: actionSlot.data
    signal backPressed()

    spacing: Metrics.spaceSm

    ShellIcon {
        visible: root.icon.length > 0
        glyph: root.icon
        size: Metrics.iconLg
        color: root.iconColor
    }
    ShellButton {
        visible: root.showBack
        icon: Icons.back
        variant: "ghost"
        compact: true
        onClicked: root.backPressed()
    }
    ColumnLayout {
        Layout.fillWidth: true
        spacing: Metrics.spaceXxs
        ShellText {
            // Wrap: a dialog's title can be an event's, which is as long
            // as its author made it.
            Layout.fillWidth: true
            text: root.title
            role: root.role
            wrapMode: Text.Wrap
        }
        ShellText {
            // Wrap: with a wide interface font the longest subtitles run past
            // the card instead of moving to a second line.
            Layout.fillWidth: true
            visible: text.length > 0
            text: root.subtitle
            muted: true
            wrapMode: Text.Wrap
        }
    }
    RowLayout {
        id: actionSlot
        Layout.alignment: Qt.AlignRight | Qt.AlignVCenter
        visible: children.length > 0
        spacing: Metrics.spaceXs
    }
}
