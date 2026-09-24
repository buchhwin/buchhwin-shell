import QtQuick
import QtQuick.Layouts
import qs.theme
import qs.services
import qs.shell.components

// Promt §5: outputs and applications side by side, input and device info below.
// Four CardSections: the one way to put a group of controls on a card, so the
// page's cards are the ones the rest of the control center draws.
GridLayout {
    id: root
    columns: width >= Metrics.compactWidth ? 2 : 1
    columnSpacing: Metrics.panelGap
    rowSpacing: Metrics.panelGap

    CardSection {
        Layout.fillWidth: true
        Layout.fillHeight: true
        title: "Output"
        spacing: Metrics.spaceSm
        Repeater {
            model: AudioService.sinks
            ListRow {
                required property var modelData
                Layout.fillWidth: true
                icon: AudioService.deviceIcon(modelData, false)
                title: AudioService.label(modelData)
                selected: modelData === AudioService.sink
                onClicked: AudioService.setDefaultSink(modelData)
            }
        }
        RowLayout {
            Layout.fillWidth: true
            ShellButton { icon: AudioService.volumeIcon(AudioService.volume, AudioService.muted); variant: "ghost"; compact: true; onClicked: AudioService.toggleMute(AudioService.sink) }
            ShellSlider { Layout.fillWidth: true; value: AudioService.volume; onMoved: value => AudioService.setVolume(AudioService.sink, value) }
            ShellText { text: Math.round(AudioService.volume * 100) + "%"; role: "small"; muted: true }
        }
    }

    CardSection {
        Layout.fillWidth: true
        Layout.fillHeight: true
        title: "Applications"
        spacing: Metrics.spaceSm
        EmptyState { visible: AudioService.playbackStreams.length === 0; row: true; icon: "󰝛"; title: "No app is playing audio" }
        Repeater {
            model: AudioService.playbackStreams
            StreamRow { required property var modelData; node: modelData; Layout.fillWidth: true }
        }
    }

    CardSection {
        Layout.fillWidth: true
        title: "Input"
        spacing: Metrics.spaceSm
        Repeater {
            model: AudioService.sources
            ListRow {
                required property var modelData
                Layout.fillWidth: true
                icon: AudioService.deviceIcon(modelData, true)
                title: AudioService.label(modelData)
                selected: modelData === AudioService.source
                onClicked: AudioService.setDefaultSource(modelData)
            }
        }
        RowLayout {
            Layout.fillWidth: true
            ShellButton { icon: AudioService.micMuted ? "󰍭" : "󰍬"; variant: "ghost"; compact: true; onClicked: AudioService.toggleMute(AudioService.source) }
            ShellSlider { Layout.fillWidth: true; value: AudioService.micVolume; onMoved: value => AudioService.setVolume(AudioService.source, value) }
            ShellText { text: Math.round(AudioService.micVolume * 100) + "%"; role: "small"; muted: true }
        }
    }

    CardSection {
        Layout.fillWidth: true
        Layout.fillHeight: true
        title: "Device info"
        spacing: Metrics.spaceXs
        ShellText { Layout.fillWidth: true; text: AudioService.label(AudioService.sink); role: "bodyLarge" }
        ShellText {
            Layout.fillWidth: true
            text: AudioService.sink ? (AudioService.sink.name || "") : ""
            role: "caption"; wrapMode: Text.WrapAnywhere; maximumLineCount: 2
        }
        ShellText {
            Layout.fillWidth: true
            text: AudioService.sink && AudioService.sink.audio ? AudioService.sink.audio.channels.length + " channels · Default" : ""
            role: "small"; muted: true
        }
    }
}
