import QtQuick
import QtQuick.Layouts
import qs.theme
import qs.services

// The top line of a panel: an optional back button, the title with an optional
// second line, a slot for the actions on the right and, after them, the key
// that opens the panel. One header for every panel - control center,
// dashboard, session menu, notification centre, emoji, shortcuts, settings -
// and the dialogs, so a title is the same size and sits at the same place
// wherever it appears. The dashboard and the session menu used to draw their
// own rows, each with its key as a line of text.
RowLayout {
    id: root
    property string icon: ""
    // The accent as ink by default; a dialog about a thing that has a colour
    // of its own (an event's calendar) hands that colour in.
    property color iconColor: Colors.accentForeground
    // The popups' form: the icon on a round tile that fills with the accent
    // while `iconActive`, because there the icon is also the state (Wi-Fi on,
    // sound muted) rather than a picture of the topic. The fill a switch that
    // is on wears (Colors.accentFill), so the tile and the switch beside it
    // are one colour: the raw teal was 1.3:1 on a light panel.
    property bool iconTile: false
    property bool iconActive: false
    property string title: ""
    property string subtitle: ""
    // "pageTitle" for a panel with its own page area (settings), "headline" for
    // a panel that is one page (control center, notification centre), "title"
    // for a dialog.
    property string role: "headline"
    property bool showBack: false
    // A popup's subtitle is a status that changes while it is open; it elides
    // rather than wraps, so a longer status cannot change the card's height.
    property bool wrap: true
    // The key that opens the panel, by the combination hyprland.lua starts it
    // on ("SUPER + K"), shown as key caps at the far end. Asked of
    // ShortcutService rather than written out, so a key moved in Settings >
    // Shortcuts shows where it sits now. Empty for none.
    property string shortcut: ""
    default property alias actions: actionSlot.data
    signal backPressed()

    spacing: Metrics.spaceSm

    ShellIcon {
        visible: root.icon.length > 0 && !root.iconTile
        glyph: root.icon
        size: Metrics.iconLg
        color: root.iconColor
    }
    Rectangle {
        visible: root.icon.length > 0 && root.iconTile
        Layout.preferredWidth: Metrics.popupIconTile
        Layout.preferredHeight: Metrics.popupIconTile
        radius: width / 2
        color: root.iconActive ? Colors.accentFill : Colors.surface2
        Behavior on color { ColorAnimation { duration: Animations.hover; easing.type: Animations.easing } }
        ShellIcon {
            anchors.centerIn: parent
            glyph: root.icon
            size: Metrics.iconMd
            color: root.iconActive ? Colors.accentFillText : Colors.text
        }
    }
    ShellButton {
        toolTip: "Back"
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
            wrapMode: root.wrap ? Text.Wrap : Text.NoWrap
        }
        ShellText {
            // Wrap: with a wide interface font the longest subtitles run past
            // the card instead of moving to a second line.
            Layout.fillWidth: true
            visible: text.length > 0
            text: root.subtitle
            muted: true
            wrapMode: root.wrap ? Text.Wrap : Text.NoWrap
        }
    }
    RowLayout {
        id: actionSlot
        Layout.alignment: Qt.AlignRight | Qt.AlignVCenter
        visible: children.length > 0
        spacing: Metrics.spaceXs
    }
    // After the actions rather than among them: it is not something to
    // click. The caps are lower than a button, so a key beside the actions
    // never makes the header taller than they do.
    KeyChips {
        Layout.alignment: Qt.AlignRight | Qt.AlignVCenter
        visible: keys.length > 0
        keys: root.shortcut.length > 0 ? ShortcutService.keyHintParts(root.shortcut) : []
    }
}
