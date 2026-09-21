import QtQuick
import QtQuick.Layouts
import qs.theme
import qs.services
import qs.shell.components
import qs.shell.controlcenter.pages

// Volume pill/widget: output volume and mute, output devices, per-app volume
// and the microphone switch.
PopupPanel {
    id: root
    panelId: "volumePopup"
    heading: "Audio"
    detail: AudioService.label(AudioService.sink)
    glyph: AudioService.volumeIcon(AudioService.volume, AudioService.muted)
    glyphActive: !AudioService.muted && AudioService.sink !== null
    footerText: "Audio settings"
    onFooterClicked: PanelService.open("settings", { page: "audio" })

    body: ColumnLayout {
        spacing: Metrics.panelGap

        CardSection {
            Layout.fillWidth: true
            padding: Metrics.spaceMd
            RowLayout {
                Layout.fillWidth: true
                spacing: Metrics.spaceSm
                ShellButton {
                    icon: AudioService.volumeIcon(AudioService.volume, AudioService.muted)
                    iconSize: Metrics.iconMd
                    variant: "ghost"; compact: true
                    toolTip: AudioService.muted ? "Unmute" : "Mute"
                    enabledState: AudioService.sink !== null
                    onClicked: AudioService.toggleMute(AudioService.sink)
                }
                ShellSlider {
                    Layout.fillWidth: true
                    value: AudioService.volume
                    enabledState: AudioService.sink !== null
                    onMoved: value => AudioService.setVolume(AudioService.sink, value)
                }
                ShellText {
                    Layout.minimumWidth: Metrics.iconXl
                    horizontalAlignment: Text.AlignRight
                    text: Math.round(AudioService.volume * 100) + "%"
                    role: "small"; muted: true
                    font.features: { "tnum": 1 }
                }
            }
        }

        ScrollList {
            Layout.fillWidth: true
            title: "Output"
            maxHeight: Metrics.rowHeight * 3
            Repeater {
                model: AudioService.sinks
                ListRow {
                    level: 1
                    required property var modelData
                    width: parent.width
                    icon: AudioService.deviceIcon(modelData, false)
                    title: AudioService.label(modelData)
                    selected: modelData === AudioService.sink
                    onClicked: AudioService.setDefaultSink(modelData)
                    ShellIcon { visible: modelData === AudioService.sink; glyph: Icons.check; size: Metrics.iconSm; color: Colors.accentForeground }
                }
            }
        }

        ScrollList {
            Layout.fillWidth: true
            title: "Applications"
            maxHeight: Metrics.popupListHeight
            EmptyState {
                visible: AudioService.playbackStreams.length === 0
                width: parent.width
                row: true
                icon: "󰝛"
                title: "No app is playing audio"
            }
            Repeater {
                model: AudioService.playbackStreams
                StreamRow { required property var modelData; node: modelData; showOutput: false; width: parent.width }
            }
        }

        // No rule next to a card: the card already separates the block.
        CardSection {
            Layout.fillWidth: true
            padding: Metrics.spaceSm
            ListRow {
                Layout.fillWidth: true
                level: 1
                icon: AudioService.micMuted ? "󰍭" : "󰍬"
                title: "Microphone"
                subtitle: AudioService.source === null ? "No input device"
                    : AudioService.micMuted ? "Muted" : AudioService.micInUse ? "In use · " + AudioService.label(AudioService.source)
                    : AudioService.label(AudioService.source)
                onClicked: AudioService.toggleMute(AudioService.source)
                ShellToggle {
                    checked: !AudioService.micMuted
                    enabledState: AudioService.source !== null
                    onToggled: AudioService.toggleMute(AudioService.source)
                }
            }
        }
    }
}
