import QtQuick
import QtQuick.Layouts
import qs.theme

// The inside of a row, a tile and a chip: a glyph in a fixed slot, the gap,
// then a title over a muted second line. ListRow, QuickTile and ChipButton
// each laid this out on their own - glyphs of 20 and 26, titles of 13, 14 and
// 15, gaps of 8 and 12 - so a tile, the chip under it and a row on the page
// behind it never quite lined up. One layout now, the row's, because the row
// is the one on every surface: what differs between the three is the frame
// around it (height, padding, what trails it), not what is inside.
RowLayout {
    id: root
    property string icon: ""
    // A picture instead of a glyph (an application's own icon).
    property string iconSource: ""
    property string title: ""
    property string subtitle: ""
    property color iconColor: Colors.mutedText
    property color titleColor: Colors.text
    // The title alone: a chip one grid row tall has no room for the second
    // line, and half of it cut off is worse than none.
    property bool singleLine: false

    spacing: Metrics.spaceMd

    Image {
        visible: root.iconSource.length > 0
        Layout.preferredWidth: Metrics.iconLg
        Layout.preferredHeight: Metrics.iconLg
        source: root.iconSource
        sourceSize.width: Metrics.iconLg * 2
        sourceSize.height: Metrics.iconLg * 2
        fillMode: Image.PreserveAspectFit
        // Theme icons (image://icon) must load on the GUI thread.
        asynchronous: !String(source).startsWith("image://")
    }
    ShellIcon {
        visible: root.icon.length > 0 && root.iconSource.length === 0
        Layout.preferredWidth: Metrics.iconLg
        glyph: root.icon
        size: Metrics.iconMd
        color: root.iconColor
    }
    ColumnLayout {
        Layout.fillWidth: true
        spacing: 0
        ShellText { Layout.fillWidth: true; text: root.title; color: root.titleColor }
        ShellText { Layout.fillWidth: true; text: root.subtitle; role: "small"; muted: true; visible: text.length > 0 && !root.singleLine }
    }
}
