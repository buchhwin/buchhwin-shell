import Quickshell
import QtQuick
import QtQuick.Layouts
import qs.theme
import qs.services
import qs.shell.components

// Now playing pill/widget, laid out horizontally: cover on the left over a
// blurred copy of it; on the right title, artist and album, seek bar with
// times, shuffle / previous / play-pause / next / loop (where the player
// supports them) and the player's own volume; a player switcher below when
// several players are running.
PopupPanel {
    id: root
    panelId: "mediaPopup"
    backdropSource: MprisService.artUrl
    cardWidth: Metrics.popupMediaWidth

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
        spacing: Metrics.panelGap
        readonly property var player: MprisService.active
        readonly property bool seekable: player !== null && player.lengthSupported && player.length > 0
        readonly property var entry: player && player.desktopEntry ? DesktopEntries.byId(player.desktopEntry) : null
        Component.onCompleted: MprisService.trackers += 1
        Component.onDestruction: MprisService.trackers = Math.max(0, MprisService.trackers - 1)

        RowLayout {
            Layout.fillWidth: true
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
                    size: Metrics.iconXl * 2
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
                        text: media.seekable ? MprisService.formatTime(seek.pressed ? seek.liveValue * media.player.length : media.player.position) : ""
                        role: "caption"
                        font.features: { "tnum": 1 }
                    }
                    ShellSlider {
                        focusOnTab: true
                        id: seek
                        Layout.fillWidth: true
                        enabledState: media.player !== null && media.player.canSeek
                        value: media.seekable ? media.player.position / media.player.length : 0
                        onReleased: value => MprisService.seekTo(value)
                    }
                    ShellText {
                        text: media.seekable ? "−" + MprisService.formatTime(media.player.length - (seek.pressed ? seek.liveValue * media.player.length : media.player.position)) : ""
                        role: "caption"
                        font.features: { "tnum": 1 }
                    }
                }

                RowLayout {
                    Layout.fillWidth: true
                    spacing: Metrics.spaceXs
                    opacity: MprisService.hasPlayer ? 1 : Effects.disabledOpacity

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
                        value: MprisService.volume
                        onMoved: value => MprisService.setVolume(value)
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
