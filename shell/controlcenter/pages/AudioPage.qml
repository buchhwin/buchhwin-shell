import QtQuick
import QtQuick.Layouts
import qs.theme
import qs.services
import qs.shell.components

// Promt §5: outputs and applications side by side, input and device info below.
GridLayout {
    id: root
    columns: width >= Metrics.compactWidth ? 2 : 1
    columnSpacing: Metrics.panelGap
    rowSpacing: Metrics.panelGap

    ShellCard {
        Layout.fillWidth: true
        Layout.fillHeight: true
        implicitHeight: outputColumn.implicitHeight + Metrics.spaceLg * 2
        ColumnLayout {
            id: outputColumn
            anchors.fill: parent
            anchors.margins: Metrics.spaceLg
            spacing: Metrics.spaceSm
            SectionLabel { text: "Output" }
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
    }

    ShellCard {
        Layout.fillWidth: true
        Layout.fillHeight: true
        implicitHeight: appsColumn.implicitHeight + Metrics.spaceLg * 2
        ColumnLayout {
            id: appsColumn
            anchors.fill: parent
            anchors.margins: Metrics.spaceLg
            spacing: Metrics.spaceSm
            SectionLabel { text: "Applications" }
            ShellText { visible: AudioService.playbackStreams.length === 0; text: "No app is playing audio"; role: "small"; muted: true }
            Repeater {
                model: AudioService.playbackStreams
                StreamRow { required property var modelData; node: modelData; Layout.fillWidth: true }
            }
            Item { Layout.fillHeight: true }
        }
    }

    ShellCard {
        Layout.fillWidth: true
        implicitHeight: inputColumn.implicitHeight + Metrics.spaceLg * 2
        ColumnLayout {
            id: inputColumn
            anchors.fill: parent
            anchors.margins: Metrics.spaceLg
            spacing: Metrics.spaceSm
            SectionLabel { text: "Input" }
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
    }

    ShellCard {
        Layout.fillWidth: true
        Layout.fillHeight: true
        implicitHeight: infoColumn.implicitHeight + Metrics.spaceLg * 2
        ColumnLayout {
            id: infoColumn
            anchors.fill: parent
            anchors.margins: Metrics.spaceLg
            spacing: Metrics.spaceXs
            SectionLabel { text: "Device info" }
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
            Item { Layout.fillHeight: true }
        }
    }
}
