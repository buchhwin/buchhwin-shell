import QtQuick
import QtQuick.Layouts
import qs.theme
import qs.services
import "../../services/media/MediaLogic.js" as MediaLogic

// What is playing, as a card sized by the cell it is given: the control
// center's media tile and the dashboard's "Playing" card are this file at two
// different start sizes. It lived beside the control center's own pages until
// the dashboard wanted it too - a card two surfaces draw is shared vocabulary,
// and reaching into another surface's folder for it is how a folder stops
// meaning anything.
ShellCard {
    id: root
    implicitHeight: coreHeight + (chipsWanted ? chipsHeight : 0) + (seekWanted ? seekHeight : 0)
        + Metrics.spaceLg * 2

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

    // What fits, in the height the cell really has. The shape is a step of
    // the grid, and a tall cell is not tall enough for everything: the
    // control center's five-row tile is 198 px, and with two players the
    // cover, the seek bar, the transport and a second row of chips needed
    // 230 - centred, the cover and the chips were cut at both edges.
    // So each optional part asks for its room, and the seek bar is the first
    // to give it up: with several players, which one this card is about is
    // the question a small card has to answer; where in the track can wait
    // for the popup. Measured from the parts' own implicit heights, which do
    // not change with whether they are shown, so none of this depends on
    // itself - and the card's natural height is all of it at once.
    readonly property real coreHeight: idle ? idleState.implicitHeight
        : topRow.implicitHeight + (tight ? 0 : column.spacing + transport.implicitHeight)
    readonly property real seekHeight: column.spacing + seek.implicitHeight
    readonly property real chipsHeight: column.spacing + chips.implicitHeight
    // A live stream has no length (MprisService.trackLength), so no bar.
    readonly property bool seekWanted: !tight && MprisService.hasLength
    readonly property bool chipsWanted: !tight && MprisService.players.length > 1
    readonly property real room: height - Metrics.spaceLg * 2
    readonly property bool chipsShown: chipsWanted && coreHeight + chipsHeight <= room
    readonly property bool seekShown: seekWanted
        && coreHeight + seekHeight + (chipsShown ? chipsHeight : 0) <= room

    // A click anywhere the card is not already a control. The transport
    // buttons, the seek bar and the player chips are declared after this, so
    // they are above it and keep their own clicks - pressing play must not
    // also open a window.
    signal clicked()
    property bool clickOpens: false

    // Nothing playing: the empty state the media popup shows, in the middle
    // of the card, rather than a grey cover, "Nothing playing" and three
    // transport buttons that cannot do anything.
    readonly property bool idle: !MprisService.hasPlayer

    // Each transport button says for itself whether it can act, as the media
    // popup's do. The row used to fade as a whole with no player while its
    // buttons still hovered, took the focus and clicked.
    readonly property bool canPrevious: MprisService.hasPlayer && MprisService.active.canGoPrevious
    readonly property bool canNext: MprisService.hasPlayer && MprisService.active.canGoNext

    MouseArea {
        anchors.fill: parent
        enabled: root.clickOpens
        cursorShape: Qt.PointingHandCursor
        onClicked: root.clicked()
    }
    FocusRing { active: nowPlaying.activeFocus || idleState.activeFocus; controlRadius: root.radius }

    ColumnLayout {
        id: column
        // Centred in the cell rather than stretched across it. The cell decides
        // the height now, and a layout that fills it hands every spare pixel to
        // whichever child happens to be a layout itself - which is how a tall
        // tile ended up with its text pinned to the top and a growing empty
        // band under it. Centred, a cell that is too short overflows instead,
        // and TileSlot clips that to the cell's own edge.
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.verticalCenter: parent.verticalCenter
        anchors.leftMargin: Metrics.spaceLg
        anchors.rightMargin: Metrics.spaceLg
        spacing: Metrics.spaceMd

        // The same stop for the keys as what is playing below: the card's
        // click opens the media popup with nothing playing too.
        EmptyState {
            id: idleState
            Layout.fillWidth: true
            visible: root.idle
            // A short card has room for the two lines, not for the glyph.
            icon: root.tight ? "" : "󰎆"
            title: "Nothing playing"
            description: "Music and videos show up here"
            property bool focusOnTab: false
            readonly property bool available: root.clickOpens
            activeFocusOnTab: focusOnTab && root.clickOpens
            Keys.onReturnPressed: root.clicked()
            Keys.onEnterPressed: root.clicked()
            Keys.onSpacePressed: root.clicked()
            Accessible.role: Accessible.Button
            Accessible.ignored: !root.clickOpens
            Accessible.name: title
            Accessible.description: description
            Accessible.onPressAction: if (root.clickOpens) root.clicked()
        }

        RowLayout {
            id: topRow
            Layout.fillWidth: true
            visible: !root.idle
            spacing: Metrics.spaceMd

            // The cover is masked rather than clipped: `clip` on a Rectangle
            // cuts the bounding box, not the radius, so a square-cornered
            // picture sat inside a rounded frame. This card is drawn on two
            // surfaces, so it was the same corner wrong twice.
            Rectangle {
                Layout.preferredWidth: Metrics.coverSize
                Layout.preferredHeight: Metrics.coverSize
                radius: Metrics.radiusInner
                color: Colors.surface2
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
                id: nowPlaying
                Layout.fillWidth: true
                spacing: Metrics.spaceXxs
                // The card's click from the keys: a stop for the panel's keys
                // (NavLogic stops on `focusOnTab`), Return or Space opens what
                // the click opens. On what is playing rather than on the card,
                // because NavLogic does not look inside a stop and the
                // transport buttons in the card have to stay reachable; the
                // ring goes round the card, which is what opens.
                property bool focusOnTab: false
                readonly property bool available: root.clickOpens
                activeFocusOnTab: focusOnTab && root.clickOpens
                Keys.onReturnPressed: root.clicked()
                Keys.onEnterPressed: root.clicked()
                Keys.onSpacePressed: root.clicked()
                Accessible.role: Accessible.Button
                Accessible.ignored: !root.clickOpens
                Accessible.name: MprisService.hasPlayer ? MprisService.title : "Nothing playing"
                Accessible.description: MprisService.artist
                Accessible.onPressAction: if (root.clickOpens) root.clicked()
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
                toolTip: "Previous"
                visible: root.tight && root.roomForTransport
                icon: Icons.previous; variant: "ghost"; iconSize: Metrics.iconSm
                enabledState: root.canPrevious
                onClicked: MprisService.previous()
            }
            ShellButton {
                toolTip: MprisService.playing ? "Pause" : "Play"
                visible: root.tight
                icon: MprisService.playing ? Icons.pause : Icons.play
                variant: "ghost"; iconSize: Metrics.iconMd
                enabledState: MprisService.hasPlayer
                onClicked: MprisService.togglePlaying()
            }
            ShellButton {
                toolTip: "Next"
                visible: root.tight && root.roomForTransport
                icon: Icons.next; variant: "ghost"; iconSize: Metrics.iconSm
                enabledState: root.canNext
                onClicked: MprisService.next()
            }
        }

        ShellSlider {
            id: seek
            Layout.fillWidth: true
            // Named on the slider, as everywhere outside a SettingRow: the
            // times beside it are siblings, and a screen reader said "slider".
            accessibleName: "Position"
            // The position moves on by a second's worth every second; a spring
            // on that redrew the open control center for a sixth of each one.
            glide: false
            visible: root.seekShown
            enabledState: MprisService.active !== null && MprisService.active.canSeek
            value: MprisService.hasLength ? Math.min(1, MprisService.active.position / MprisService.trackLength) : 0
            onReleased: value => MprisService.seekTo(value)
        }

        RowLayout {
            id: transport
            Layout.fillWidth: true
            Layout.alignment: Qt.AlignHCenter
            spacing: Metrics.spaceLg
            visible: !root.tight && !root.idle
            Item { Layout.fillWidth: true }
            ShellButton { toolTip: "Previous"; icon: Icons.previous; variant: "ghost"; iconSize: Metrics.iconMd; enabledState: root.canPrevious; onClicked: MprisService.previous() }
            ShellButton { toolTip: MprisService.playing ? "Pause" : "Play"; icon: MprisService.playing ? Icons.pause : Icons.play; variant: "ghost"; iconSize: Metrics.iconLg; enabledState: MprisService.hasPlayer; onClicked: MprisService.togglePlaying() }
            ShellButton { toolTip: "Next"; icon: Icons.next; variant: "ghost"; iconSize: Metrics.iconMd; enabledState: root.canNext; onClicked: MprisService.next() }
            Item { Layout.fillWidth: true }
        }

        // The players, in one row. A Flow wrapped them onto a second row the
        // cell had no room for; now the chips that fit are shown and the rest
        // fold into a "+N" chip, which picks the next of them on each press
        // (and is lit while the playing one is among them). The media popup,
        // which the card opens, lists every player.
        Item {
            id: chips
            Layout.fillWidth: true
            implicitHeight: Metrics.controlHeightSm
            visible: root.chipsShown
            readonly property var players: MprisService.players
            readonly property int activeIndex: players.indexOf(MprisService.active)
            // From each chip's implicit width, which a hidden chip keeps, and
            // the "+N" chip at its widest count (`moreProbe`), so the answer
            // cannot change what it was measured from. Against the column's
            // width rather than this row's own: a layout leaves a hidden
            // child's width where it was, and the row's first frame would
            // have been measured against nothing.
            readonly property int fitting: {
                const widths = []
                for (let index = 0; index < chipRepeater.count; ++index) {
                    const chip = chipRepeater.itemAt(index)
                    widths.push(chip ? chip.implicitWidth : 0)
                }
                return MediaLogic.chipsThatFit(widths, column.width, chipRow.spacing, moreProbe.implicitWidth)
            }
            readonly property int hiddenCount: Math.max(0, players.length - fitting)

            ShellButton { id: moreProbe; visible: false; compact: true; text: "+" + chips.players.length }

            Row {
                id: chipRow
                spacing: Metrics.spaceXs
                Repeater {
                    id: chipRepeater
                    model: chips.players
                    ShellButton {
                        required property var modelData
                        required property int index
                        visible: index < chips.fitting
                        compact: true
                        text: modelData.identity
                        variant: modelData === MprisService.active ? "accent" : "surface"
                        onClicked: MprisService.select(modelData)
                    }
                }
                ShellButton {
                    visible: chips.hiddenCount > 0
                    compact: true
                    text: "+" + chips.hiddenCount
                    variant: chips.activeIndex >= chips.fitting ? "accent" : "surface"
                    toolTip: chips.players.slice(chips.fitting).map(player => player.identity).join(", ")
                    onClicked: {
                        const index = MediaLogic.nextHiddenIndex(chips.players.length, chips.fitting, chips.activeIndex)
                        if (index >= 0) MprisService.select(chips.players[index])
                    }
                }
            }
        }
    }
}
