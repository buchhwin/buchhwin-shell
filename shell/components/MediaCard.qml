import QtQuick
import QtQuick.Layouts
import qs.theme
import qs.services

// What is playing, as a card sized by the cell it is given: the control
// center's media tile and the dashboard's "Playing" card are this file at two
// different start sizes. It lived beside the control center's own pages until
// the dashboard wanted it too - a card two surfaces draw is shared vocabulary,
// and reaching into another surface's folder for it is how a folder stops
// meaning anything.
ShellCard {
    id: root
    implicitHeight: column.implicitHeight + Metrics.spaceLg * 2

    // The shape of the cell it was given, as FitLogic names it. Four blocks
    // stacked need five rows of the grid; below that the card keeps the one
    // block that is the point - the cover, what is playing, and a way to stop
    // it - and puts the controls into that row instead of under it. The seek
    // bar and the player chips are what a short card does without.
    property string shape: "small"
    readonly property bool tight: shape !== "tall" && shape !== "large"
    // Three transport buttons only fit beside the text when the cell has
    // columns to spare; one column gets play and pause alone.
    readonly property bool roomForTransport: shape === "wide" || shape === "large"

    ColumnLayout {
        id: column
        // Centred in the cell rather than stretched across it. The cell decides
        // the height now, and a layout that fills it hands every spare pixel to
        // whichever child happens to be a layout itself - which is how a tall
        // tile ended up with its text pinned to the top and a growing empty
        // band under it. Centred, a cell that is too short overflows instead,
        // and QuickSlot clips that to the cell's own edge.
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.verticalCenter: parent.verticalCenter
        anchors.leftMargin: Metrics.spaceLg
        anchors.rightMargin: Metrics.spaceLg
        spacing: Metrics.spaceMd

        RowLayout {
            Layout.fillWidth: true
            spacing: Metrics.spaceMd

            // The cover is masked rather than clipped: `clip` on a Rectangle
            // cuts the bounding box, not the radius, so a square-cornered
            // picture sat inside a rounded frame. This card is drawn on two
            // surfaces, so it was the same corner wrong twice.
            Rectangle {
                Layout.preferredWidth: Metrics.coverSize
                Layout.preferredHeight: Metrics.coverSize
                radius: Metrics.radiusInner
                color: Colors.elevatedSurface
                RoundedImage {
                    id: cover
                    anchors.fill: parent
                    radius: parent.radius
                    source: MprisService.artUrl
                    sourceWidth: Metrics.coverSize * 2
                    visible: status === Image.Ready
                }
                ShellIcon { anchors.centerIn: parent; visible: cover.status !== Image.Ready; glyph: "󰎆"; size: Metrics.iconLg; color: Colors.mutedText }
            }

            ColumnLayout {
                Layout.fillWidth: true
                spacing: Metrics.spaceXxs
                ShellText { Layout.fillWidth: true; text: MprisService.hasPlayer ? MprisService.title : "Nothing playing"; role: "bodyLarge" }
                ShellText { Layout.fillWidth: true; text: MprisService.artist; role: "small"; muted: true; visible: text.length > 0 }
                // The album is the third line, and the first to go: a short
                // card has room for what is playing and who by, not for where
                // it came from.
                ShellText { Layout.fillWidth: true; text: MprisService.album; role: "caption"
                            visible: text.length > 0 && !root.tight }
            }

            // The transport comes up into this row when there is no room for
            // a row of its own.
            ShellButton {
                visible: root.tight && root.roomForTransport
                icon: Icons.previous; variant: "ghost"; iconSize: Metrics.iconSm
                onClicked: MprisService.previous()
            }
            ShellButton {
                visible: root.tight
                icon: MprisService.playing ? Icons.pause : Icons.play
                variant: "ghost"; iconSize: Metrics.iconMd
                enabledState: MprisService.hasPlayer
                onClicked: MprisService.togglePlaying()
            }
            ShellButton {
                visible: root.tight && root.roomForTransport
                icon: Icons.next; variant: "ghost"; iconSize: Metrics.iconSm
                onClicked: MprisService.next()
            }
        }

        ShellSlider {
            Layout.fillWidth: true
            visible: !root.tight && MprisService.active !== null && MprisService.active.lengthSupported && MprisService.active.length > 0
            enabledState: MprisService.active !== null && MprisService.active.canSeek
            value: MprisService.active && MprisService.active.length > 0 ? MprisService.active.position / MprisService.active.length : 0
            onReleased: value => MprisService.seekTo(value)
        }

        RowLayout {
            Layout.fillWidth: true
            Layout.alignment: Qt.AlignHCenter
            spacing: Metrics.spaceLg
            visible: !root.tight
            opacity: MprisService.hasPlayer ? 1 : Effects.disabledOpacity
            Item { Layout.fillWidth: true }
            ShellButton { icon: Icons.previous; variant: "ghost"; iconSize: Metrics.iconMd; onClicked: MprisService.previous() }
            ShellButton { icon: MprisService.playing ? Icons.pause : Icons.play; variant: "ghost"; iconSize: Metrics.iconLg; onClicked: MprisService.togglePlaying() }
            ShellButton { icon: Icons.next; variant: "ghost"; iconSize: Metrics.iconMd; onClicked: MprisService.next() }
            Item { Layout.fillWidth: true }
        }

        Flow {
            Layout.fillWidth: true
            visible: !root.tight && MprisService.players.length > 1
            spacing: Metrics.spaceXs
            Repeater {
                model: MprisService.players
                ShellButton {
                    required property var modelData
                    compact: true
                    text: modelData.identity
                    variant: modelData === MprisService.active ? "accent" : "surface"
                    onClicked: MprisService.select(modelData)
                }
            }
        }
    }
}
