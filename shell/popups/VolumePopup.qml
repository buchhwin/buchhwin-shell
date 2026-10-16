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
        spacing: Metrics.pageGap

        CardSection {
            Layout.fillWidth: true
            padding: Metrics.spaceMd
            RowLayout {
                Layout.fillWidth: true
                spacing: Metrics.spaceSm
                ShellButton {
                    focusOnTab: true
                    icon: AudioService.volumeIcon(AudioService.volume, AudioService.muted)
                    iconSize: Metrics.iconMd
                    variant: "ghost"; compact: true
                    toolTip: AudioService.muted ? "Unmute" : "Mute"
                    enabledState: AudioService.sink !== null
                    onClicked: AudioService.toggleMute(AudioService.sink)
                }
                ShellSlider {
                    focusOnTab: true
                    Layout.fillWidth: true
                    // Named on the slider, as the control center's audio page
                    // names its own: the glyph and the figure beside it are
                    // siblings, and a screen reader said "slider, 40%".
                    accessibleName: "Output volume"
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
                    focusOnTab: true
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
                // Inset like the rows (ListRow's spaceLg), so its icon lines
                // up with theirs instead of sitting at the card's padding.
                x: Metrics.spaceLg
                width: parent.width - Metrics.spaceLg * 2
                row: true
                icon: "󰝛"
                title: "No app is playing audio"
            }
            Repeater {
                model: AudioService.playbackStreams
                // Inset like the output rows above (ListRow's spaceLg), so the
                // app icons line up with the device icons instead of sitting
                // at the card's padding.
                StreamRow {
                    required property var modelData
                    node: modelData
                    showOutput: false
                    x: Metrics.spaceLg
                    width: parent.width - Metrics.spaceLg * 2
                }
            }
        }

        // No rule next to a card: the card already separates the block.
        CardSection {
            Layout.fillWidth: true
            padding: Metrics.spaceSm
            ListRow {
                focusOnTab: true
                Layout.fillWidth: true
                level: 1
                icon: AudioService.micMuted ? "󰍭" : "󰍬"
                title: "Microphone"
                subtitle: AudioService.source === null ? "No input device"
                    : AudioService.micMuted ? "Muted" : AudioService.micInUse ? "In use · " + AudioService.label(AudioService.source)
                    : AudioService.label(AudioService.source)
                onClicked: AudioService.toggleMute(AudioService.source)
                ShellToggle {
                    focusOnTab: true
                    checked: !AudioService.micMuted
                    enabledState: AudioService.source !== null
                    onToggled: AudioService.toggleMute(AudioService.source)
                }
            }
        }
    }
}
