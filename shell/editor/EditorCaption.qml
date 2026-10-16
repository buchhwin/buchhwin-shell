import QtQuick
import qs.theme
import qs.shell.components

// A caption the editor draws over the wallpaper: the hint lines, the zone
// labels, an empty widget's name. Each was the scrim's white ink with a 1 px
// outline, straight on the image, and on a bright one that read at 1.2-1.7:1
// (worst in the light theme, whose scrim is the lighter one). Now it sits on a
// small plate of the pill's surface in the theme's own ink, as the dragged
// pill's ghost does - readable on any wallpaper, in either theme.
//
// Sized by its text: given a width it wraps inside it, and the plate hugs the
// lines as laid out, so a short line is not a wide bar.
Item {
    id: caption
    property alias text: label.text
    property alias role: label.role
    property bool muted: false
    property alias horizontalAlignment: label.horizontalAlignment
    property alias wrapMode: label.wrapMode

    implicitWidth: label.implicitWidth + Metrics.spaceSm * 2
    implicitHeight: label.implicitHeight + Metrics.spaceXs * 2

    Rectangle {
        // Where the lines are: centred text lies in the middle of its box,
        // the rest at its start.
        x: label.x - Metrics.spaceSm + (label.horizontalAlignment === Text.AlignHCenter
            ? (label.width - label.contentWidth) / 2
            : label.horizontalAlignment === Text.AlignRight ? label.width - label.contentWidth : 0)
        y: label.y - Metrics.spaceXs
        width: label.contentWidth + Metrics.spaceSm * 2
        height: label.contentHeight + Metrics.spaceXs * 2
        radius: Metrics.radiusInner
        color: Colors.pill
        border.width: Metrics.borderWidth
        border.color: Colors.pillBorder
    }

    ShellText {
        id: label
        anchors.fill: parent
        anchors.leftMargin: Metrics.spaceSm
        anchors.rightMargin: Metrics.spaceSm
        anchors.topMargin: Metrics.spaceXs
        anchors.bottomMargin: Metrics.spaceXs
        // A caption wraps or takes its size; it never ends in "…".
        elide: Text.ElideNone
        color: caption.muted ? Colors.mutedText : Colors.text
    }
}
