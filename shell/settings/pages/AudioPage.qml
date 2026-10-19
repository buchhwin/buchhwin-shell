import Quickshell
import QtQuick
import QtQuick.Layouts
import qs.theme
import qs.services
import qs.shell.components
import qs.shell.controlcenter.pages

// Settings > Audio: output and input devices with volume, a live input level
// while the page is open, per-app volume and output, and device details.
ColumnLayout {
    id: root
    spacing: Metrics.pageGap

    // The level meter runs only while this page is on screen (the Settings
    // panel hides instead of destroying the page).
    readonly property bool meterWanted: QsWindow.window !== null && QsWindow.window.visible
    property bool meterTracked: false
    onMeterWantedChanged: syncMeter()
    Component.onCompleted: syncMeter()
    Component.onDestruction: if (meterTracked) AudioService.untrackMeter()

    function syncMeter() {
        if (meterWanted === meterTracked) return
        meterTracked = meterWanted
        if (meterTracked) AudioService.trackMeter()
        else AudioService.untrackMeter()
    }

    SettingsSection {
        Layout.fillWidth: true
        title: "Output"
        description: AudioService.ready ? "Speakers and headphones. The selected device plays all sound." : "PipeWire is not ready"

        Repeater {
            // Kept rows, not rebuilt ones: AudioService's lists are new
            // whenever any PipeWire node comes or goes (a notification
            // sound, a browser tab), and a rebuilt row ended a slider drag
            // under the hand and took the keyboard focus. The nodes keep
            // their identity (ScriptModel).
            model: ScriptModel { values: AudioService.sinks }
            ListRow {
                focusOnTab: true
                level: 1
                required property var modelData
                // The port as the title and the card beside "In use", as in
                // the control center (AudioService.labelParts).
                readonly property var parts: AudioService.labelParts(modelData, AudioService.sinks)
                Layout.fillWidth: true
                icon: AudioService.deviceIcon(modelData, false)
                title: parts.title
                subtitle: [parts.subtitle, modelData === AudioService.sink ? "In use" : ""].filter(part => part.length).join(" · ")
                selected: modelData === AudioService.sink
                onClicked: AudioService.setDefaultSink(modelData)
            }
        }
        EmptyState { Layout.fillWidth: true; row: true; visible: AudioService.sinks.length === 0; icon: "󰓃"; title: "No output devices" }
        SettingRow {
            label: "Volume"
            ShellButton {
                focusOnTab: true
                icon: AudioService.volumeIcon(AudioService.volume, AudioService.muted)
                variant: "ghost"
                compact: true
                toolTip: AudioService.muted ? "Unmute" : "Mute"
                onClicked: AudioService.toggleMute(AudioService.sink)
            }
            ShellSlider {
                focusOnTab: true
                Layout.fillWidth: true
                value: AudioService.volume
                onMoved: value => AudioService.setVolume(AudioService.sink, value)
            }
            ShellText { text: Math.round(AudioService.volume * 100) + "%"; role: "small"; muted: true; Layout.minimumWidth: Metrics.iconXl }
        }
    }

    SettingsSection {
        Layout.fillWidth: true
        title: "Input"
        description: AudioService.micInUse ? "A microphone is in use right now." : "Microphones. The selected device is used by all apps."

        Repeater {
            model: ScriptModel { values: AudioService.sources }
            ListRow {
                focusOnTab: true
                level: 1
                required property var modelData
                // The port as the title and the card beside "In use", as in
                // the control center (AudioService.labelParts).
                readonly property var parts: AudioService.labelParts(modelData, AudioService.sources)
                Layout.fillWidth: true
                icon: AudioService.deviceIcon(modelData, true)
                title: parts.title
                subtitle: [parts.subtitle, modelData === AudioService.source ? "In use" : ""].filter(part => part.length).join(" · ")
                selected: modelData === AudioService.source
                onClicked: AudioService.setDefaultSource(modelData)
            }
        }
        EmptyState { Layout.fillWidth: true; row: true; visible: AudioService.sources.length === 0; icon: "󰍬"; title: "No input devices" }
        SettingRow {
            label: "Input volume"
            ShellButton {
                focusOnTab: true
                icon: AudioService.micMuted ? "󰍭" : "󰍬"
                variant: "ghost"
                compact: true
                toolTip: AudioService.micMuted ? "Unmute" : "Mute"
                onClicked: AudioService.toggleMute(AudioService.source)
            }
            ShellSlider {
                focusOnTab: true
                Layout.fillWidth: true
                value: AudioService.micVolume
                onMoved: value => AudioService.setVolume(AudioService.source, value)
            }
            ShellText { text: Math.round(AudioService.micVolume * 100) + "%"; role: "small"; muted: true; Layout.minimumWidth: Metrics.iconXl }
        }
        SettingRow {
            label: "Level"
            Item {
                // Same horizontal inset as the slider track above.
                Layout.fillWidth: true
                Layout.leftMargin: Metrics.controlHeightSm + Metrics.spaceSm + Metrics.sliderHandle / 2
                Layout.rightMargin: Metrics.sliderHandle / 2
                implicitHeight: Metrics.controlHeightSm

                Rectangle {
                    anchors.left: parent.left
                    anchors.right: parent.right
                    anchors.verticalCenter: parent.verticalCenter
                    height: Metrics.meterHeight
                    radius: height / 2
                    color: Colors.track

                    Rectangle {
                        width: parent.width * AudioService.inputLevel
                        height: parent.height
                        radius: parent.radius
                        color: AudioService.inputPeak >= 0.98 ? Colors.warning : Colors.accentFill
                        // Linear on purpose: a new level arrives halfway through
                        // every glide, and an ease-out would land each step in
                        // its first frames and then wait - the stutter
                        // Animations.meter is longer than the gap to avoid.
                        Behavior on width { NumberAnimation { duration: Animations.move(Animations.meter) } }
                    }
                    Rectangle {
                        visible: AudioService.inputPeak > 0
                        x: (parent.width - width) * AudioService.inputPeak
                        width: Metrics.meterPeakWidth
                        height: parent.height
                        color: Colors.text
                        opacity: Effects.disabledOpacity
                    }
                }
            }
            ShellText {
                Layout.minimumWidth: Metrics.iconXl
                text: AudioService.micMuted ? "Muted" : AudioService.meterRunning ? "" : "Off"
                role: "small"; muted: true
            }
        }
        ShellText {
            Layout.fillWidth: true
            text: "The level bar listens to the input only while this page is open. Nothing is recorded or saved, and it does not count as an app using the microphone."
            role: "caption"; wrapMode: Text.Wrap
        }
    }

    SettingsSection {
        Layout.fillWidth: true
        title: "Applications"
        description: "Volume and output of apps that are playing sound right now. The output is remembered for each app."

        EmptyState { Layout.fillWidth: true; row: true; visible: AudioService.playbackStreams.length === 0; icon: "󰝛"; title: "No app is playing audio" }
        Repeater {
            model: ScriptModel { values: AudioService.playbackStreams }
            StreamRow { required property var modelData; node: modelData; Layout.fillWidth: true }
        }
    }

    SettingsSection {
        Layout.fillWidth: true
        title: "Details"

        SettingRow {
            label: "Output device"
            ShellText { Layout.fillWidth: true; text: AudioService.sink ? AudioService.label(AudioService.sink) : "–"; muted: true; wrapMode: Text.Wrap }
        }
        SettingRow {
            label: "Channels"
            ShellText { Layout.fillWidth: true; text: AudioService.sink && AudioService.sink.audio ? String(AudioService.sink.audio.channels.length) : "–"; muted: true }
        }
        SettingRow {
            label: "Input device"
            ShellText { Layout.fillWidth: true; text: AudioService.source ? AudioService.label(AudioService.source) : "–"; muted: true; wrapMode: Text.Wrap }
        }
        SettingRow {
            label: "PipeWire name"
            ShellText { Layout.fillWidth: true; text: AudioService.sink ? (AudioService.sink.name || "–") : "–"; role: "caption"; wrapMode: Text.WrapAnywhere }
        }
    }
}
