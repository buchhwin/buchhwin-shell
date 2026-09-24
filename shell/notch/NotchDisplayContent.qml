import QtQuick
import QtQuick.Layouts
import qs.theme
import qs.services
import qs.shell.components

// What the notch shows while it *is* the display: a glyph on the left and,
// depending on the kind, a level track or two lines of text on the right.
//
// It is deliberately one row the height of the notch rather than a card: the
// notch is a strip, and a display that made it as tall as the overview would
// be the overview with different content in it - which is the thing this was
// meant to replace, not to imitate.
Item {
    id: display
    required property var content
    readonly property string kind: content && content.kind ? content.kind : ""
    readonly property bool levelled: kind === "osd" && content.level !== undefined

    implicitHeight: Metrics.notchHeight
    implicitWidth: row.implicitWidth + Metrics.notchPadding * 2

    RowLayout {
        id: row
        anchors.centerIn: parent
        spacing: Metrics.spaceSm

        ShellIcon {
            glyph: display.content && display.content.icon ? display.content.icon : ""
            visible: glyph.length > 0
            size: Metrics.iconSm
            color: Colors.notchText
        }

        // An app icon, for a notification that brought one.
        Image {
            Layout.preferredWidth: Metrics.iconSm
            Layout.preferredHeight: Metrics.iconSm
            visible: source.toString().length > 0
            source: display.content && display.content.iconSource ? display.content.iconSource : ""
            sourceSize.width: Metrics.iconSm * 2
            sourceSize.height: Metrics.iconSm * 2
            fillMode: Image.PreserveAspectFit
            asynchronous: true
        }

        // A level, for the on-screen displays. The stepped keyboard light gets
        // its boxes here too, because a stepped light on a plain track is the
        // lie that was already fixed once.
        Item {
            Layout.preferredWidth: Metrics.notchLevelWidth
            Layout.preferredHeight: Metrics.meterHeight
            Layout.alignment: Qt.AlignVCenter
            visible: display.levelled

            Rectangle {
                anchors.fill: parent
                visible: !display.content.segments
                radius: height / 2
                color: Colors.notchTrack
                Rectangle {
                    width: parent.width * Math.max(0, Math.min(1, display.content.level || 0))
                    height: parent.height
                    radius: parent.radius
                    color: display.content.muted ? Colors.notchMutedText : Colors.accent
                }
            }

            Row {
                anchors.fill: parent
                visible: display.content.segments > 0
                spacing: Metrics.spaceXxs
                Repeater {
                    model: display.content.segments || 0
                    Rectangle {
                        required property int index
                        width: Math.max(1, (parent.width - Metrics.spaceXxs * (display.content.segments - 1))
                                           / Math.max(1, display.content.segments))
                        height: parent.height
                        radius: height / 2
                        color: index < Math.round((display.content.level || 0) * display.content.segments)
                            ? Colors.accent : Colors.notchTrack
                    }
                }
            }
        }

        // The words: a value for an OSD, a title and a line under it for a
        // notification or a track.
        ColumnLayout {
            spacing: 0
            visible: (display.content && display.content.title !== undefined && String(display.content.title).length > 0)
                || (display.content && display.content.value !== undefined && String(display.content.value).length > 0)

            ShellText {
                Layout.maximumWidth: Metrics.notchDisplayTextWidth
                text: display.content && display.content.title !== undefined && String(display.content.title).length
                    ? display.content.title : (display.content ? display.content.value || "" : "")
                role: "small"
                color: Colors.notchText
                elide: Text.ElideRight
            }
            ShellText {
                Layout.maximumWidth: Metrics.notchDisplayTextWidth
                visible: text.length > 0
                text: display.content && display.content.subtitle ? display.content.subtitle : ""
                role: "caption"
                color: Colors.notchMutedText
                elide: Text.ElideRight
            }
        }
    }
}
