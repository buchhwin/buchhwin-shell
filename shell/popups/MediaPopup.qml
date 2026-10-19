import Quickshell
import QtQuick
import QtQuick.Layouts
import qs.theme
import qs.services
import qs.shell.components
import "../../services/media/VisualizerLogic.js" as Visualizer

// Now playing pill/widget, laid out horizontally: cover on the left over a
// blurred copy of it; on the right title, artist and album, seek bar with
// times, shuffle / previous / play-pause / next / loop (where the player
// supports them) and the player's own volume; a player switcher below when
// several players are running. With Settings' switch on (off by default) and
// full motion, bars under the transport move with the sound while something
// plays - here only, never in the notch or the bar (VisualizerLogic).
PopupPanel {
    id: root
    panelId: "mediaPopup"
    backdropSource: MprisService.artUrl
    // Wide for a player beside its cover; with nothing playing a popup's own
    // width and a centred empty state, rather than a 580 px card with
    // "Nothing playing" and a dead transport in its top left corner.
    cardWidth: MprisService.hasPlayer ? Metrics.popupMediaWidth : Metrics.popupWidth

    // A transport control is the shell's ghost button; one that is switched
    // on (shuffle, loop) is the accent one, the way every other toggled
    // button in the shell says so.
    component ControlButton: ShellButton {
        property bool lit: false
        focusOnTab: true
        variant: lit ? "accent" : "ghost"
    }

    body: ColumnLayout {
        id: media
        spacing: Metrics.pageGap
        readonly property var player: MprisService.active
        // A real length (MprisService.lengthOf): a live stream has none, and
        // gets no seek bar and no remaining time rather than a dead bar and
        // "−153722867280:48".
        readonly property real trackLength: MprisService.trackLength
        readonly property bool seekable: player !== null && trackLength > 0
        readonly property real shownPosition: seekable
            ? Math.max(0, Math.min(trackLength, seek.pressed ? seek.liveValue * trackLength : player.position)) : 0
        readonly property var entry: player && player.desktopEntry ? DesktopEntries.byId(player.desktopEntry) : null
        Component.onCompleted: { MprisService.trackers += 1; syncVisualizer() }
        Component.onDestruction: {
            MprisService.trackers = Math.max(0, MprisService.trackers - 1)
            if (visualizerTracked) MprisService.visualizerTrackers = Math.max(0, MprisService.visualizerTrackers - 1)
        }

        // The body exists only while the popup is shown (PopupPanel), so
        // the bars are asked for from here: cava runs while this counts and
        // something plays.
        readonly property bool showsVisualizer: Visualizer.shown(SettingsService.value("desktop.mediaVisualizer"),
                                                                 Animations.motionEnabled, MprisService.hasPlayer)
        property bool visualizerTracked: false
        onShowsVisualizerChanged: syncVisualizer()
        function syncVisualizer() {
            if (showsVisualizer === visualizerTracked) return
            visualizerTracked = showsVisualizer
            if (visualizerTracked) MprisService.visualizerTrackers += 1
            else MprisService.visualizerTrackers = Math.max(0, MprisService.visualizerTrackers - 1)
        }

        EmptyState {
            Layout.fillWidth: true
            Layout.topMargin: Metrics.spaceLg
            Layout.bottomMargin: Metrics.spaceLg
            visible: !MprisService.hasPlayer
            icon: "󰎆"
            title: "Nothing playing"
            description: "Music and videos show up here"
        }

        // The player, its cover and its transport: only for a player. The
        // faded Play disc it showed without one read like the accent's
        // "selected" tint on a light card, not like a disabled button.
        RowLayout {
            Layout.fillWidth: true
            visible: MprisService.hasPlayer
            spacing: Metrics.spaceLg

            Rectangle {
                Layout.alignment: Qt.AlignVCenter
                Layout.preferredWidth: Metrics.popupMediaCover
                Layout.preferredHeight: Metrics.popupMediaCover
                radius: width / 2
                color: "transparent"
                VinylCover {
                    id: cover
                    anchors.fill: parent
                    source: MprisService.artUrl
                    spinning: MprisService.playing
                }
                ShellIcon {
                    anchors.centerIn: parent
                    visible: cover.status !== Image.Ready
                    glyph: "󰎆"
                    size: Metrics.coverFallbackGlyph
                    color: Colors.subtleText
                }
            }

            ColumnLayout {
                Layout.fillWidth: true
                Layout.alignment: Qt.AlignTop
                spacing: Metrics.spaceSm

                // Player name and how many players run.
                RowLayout {
                    Layout.fillWidth: true
                    visible: media.player !== null
                    spacing: Metrics.spaceSm
                    Image {
                        Layout.preferredWidth: Metrics.iconSm
                        Layout.preferredHeight: Metrics.iconSm
                        source: media.entry && media.entry.icon ? Quickshell.iconPath(media.entry.icon, true) : ""
                        sourceSize.width: Metrics.iconSm * 2
                        sourceSize.height: Metrics.iconSm * 2
                        visible: status === Image.Ready
                    }
                    SectionLabel { Layout.fillWidth: true; text: media.player ? media.player.identity : "" }
                    ShellText { visible: MprisService.players.length > 1; text: MprisService.players.length + " players"; role: "caption" }
                }

                ColumnLayout {
                    Layout.fillWidth: true
                    spacing: 0
                    ShellText {
                        Layout.fillWidth: true
                        text: MprisService.hasPlayer ? MprisService.title : "Nothing playing"
                        role: "title"
                        font.weight: Typography.medium
                    }
                    ShellText {
                        Layout.fillWidth: true
                        visible: text.length > 0
                        text: [MprisService.artist, MprisService.album].filter(part => part.length).join(" · ")
                        role: "small"; muted: true
                    }
                }

                RowLayout {
                    Layout.fillWidth: true
                    visible: media.seekable
                    spacing: Metrics.spaceSm
                    ShellText {
                        text: media.seekable ? MprisService.formatTime(media.shownPosition, media.trackLength) : ""
                        role: "caption"
                        font.features: { "tnum": 1 }
                    }
                    ShellSlider {
                        focusOnTab: true
                        id: seek
                        Layout.fillWidth: true
                        accessibleName: "Position"
                        // The position moves on a second at a time; a spring on
                        // that redrew the popup for a sixth of each second.
                        glide: false
                        enabledState: media.player !== null && media.player.canSeek
                        value: media.seekable ? Math.min(1, media.player.position / media.trackLength) : 0
                        onReleased: value => MprisService.seekTo(value)
                    }
                    ShellText {
                        text: media.seekable ? "−" + MprisService.formatTime(media.trackLength - media.shownPosition, media.trackLength) : ""
                        role: "caption"
                        font.features: { "tnum": 1 }
                    }
                }

                // Each button says for itself whether it can act. The row used
                // to fade as a whole while Play still took hover, focus and
                // clicks, and a disabled button inside it faded twice.
                RowLayout {
                    Layout.fillWidth: true
                    spacing: Metrics.spaceXs

                    ControlButton {
                        icon: media.player && media.player.shuffle ? "󰒟" : "󰒞"
                        lit: media.player !== null && media.player.shuffle
                        enabledState: MprisService.canShuffle
                        visible: MprisService.canShuffle
                        toolTip: "Shuffle"
                        onClicked: MprisService.toggleShuffle()
                    }
                    ControlButton {
                        icon: Icons.previous; iconSize: Metrics.iconLg
                        enabledState: media.player !== null && media.player.canGoPrevious
                        toolTip: "Previous"
                        onClicked: MprisService.previous()
                    }
                    ShellButton {
                        focusOnTab: true
                        implicitWidth: Metrics.popupPlayButton
                        implicitHeight: Metrics.popupPlayButton
                        variant: "accent"
                        icon: MprisService.playing ? Icons.pause : Icons.play
                        iconSize: Metrics.iconLg
                        enabledState: MprisService.hasPlayer
                        toolTip: MprisService.playing ? "Pause" : "Play"
                        onClicked: MprisService.togglePlaying()
                    }
                    ControlButton {
                        icon: Icons.next; iconSize: Metrics.iconLg
                        enabledState: media.player !== null && media.player.canGoNext
                        toolTip: "Next"
                        onClicked: MprisService.next()
                    }
                    ControlButton {
                        // MprisLoopState: 0 none, 1 track, 2 playlist
                        icon: media.player && media.player.loopState === 1 ? "󰑘" : media.player && media.player.loopState === 2 ? "󰑖" : "󰑗"
                        lit: media.player !== null && media.player.loopState !== 0
                        enabledState: MprisService.canLoop
                        visible: MprisService.canLoop
                        toolTip: "Repeat"
                        onClicked: MprisService.cycleLoop()
                    }
                    Item { Layout.fillWidth: true }
                    // The player's own volume, compact at the end of the row.
                    ControlButton {
                        visible: MprisService.hasVolume
                        icon: AudioService.volumeIcon(MprisService.volume, MprisService.muted)
                        iconSize: Metrics.iconSm
                        enabledState: MprisService.stream !== null
                        toolTip: MprisService.muted ? "Unmute" : "Mute"
                        onClicked: MprisService.toggleMute()
                    }
                    ShellSlider {
                        focusOnTab: true
                        visible: MprisService.hasVolume
                        Layout.preferredWidth: Metrics.popupMediaVolume
                        accessibleName: "Player volume"
                        value: MprisService.volume
                        onMoved: value => MprisService.setVolume(value)
                    }
                }

                // The bars: a row the transport's width, as tall as a small
                // control, rising from its foot. Kept while paused (flat),
                // so the popup does not change its height with the music.
                Row {
                    id: bars
                    Layout.fillWidth: true
                    Layout.preferredHeight: Metrics.controlHeightSm
                    visible: media.showsVisualizer
                    spacing: Metrics.spaceXxs
                    readonly property real barWidth: Math.max(1, (width - spacing * (Visualizer.BARS - 1)) / Visualizer.BARS)
                    Repeater {
                        model: Visualizer.BARS
                        Item {
                            required property int index
                            width: bars.barWidth
                            height: bars.height
                            Rectangle {
                                anchors.bottom: parent.bottom
                                width: parent.width
                                // A floor of a bar's width, so silence is a
                                // row of dots rather than nothing.
                                height: Math.max(width, parent.height * (MprisService.visualizerBars[parent.index] || 0))
                                radius: Math.min(width, height) / 2
                                color: Colors.accentFill
                                opacity: MprisService.playing ? 1 : Effects.mutedOpacity
                            }
                        }
                    }
                }
            }
        }

        Flow {
            Layout.fillWidth: true
            visible: MprisService.players.length > 1
            spacing: Metrics.spaceXs
            Repeater {
                model: MprisService.players
                ShellButton {
                    focusOnTab: true
                    required property var modelData
                    compact: true
                    icon: modelData.isPlaying ? "󰎈" : ""
                    text: modelData.identity
                    variant: modelData === MprisService.active ? "accent" : "surface"
                    onClicked: MprisService.select(modelData)
                }
            }
        }
    }
}
