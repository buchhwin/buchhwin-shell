import Quickshell
import QtQuick
import QtQuick.Layouts
import qs.theme
import qs.services
import qs.shell.components

// Privacy pill/widget: screen sharing and the apps recording from the
// microphone, with a microphone switch.
PopupPanel {
    id: root
    panelId: "privacyPopup"
    heading: "Privacy"
    detail: HyprlandService.screencastActive && AudioService.micInUse ? "Screen and microphone in use"
        : HyprlandService.screencastActive ? "Screen is shared"
        : AudioService.micInUse ? "Microphone in use" : "Nothing is recording"
    glyph: HyprlandService.screencastActive ? "󰹑" : "󰍬"
    glyphActive: HyprlandService.screencastActive || AudioService.micInUse
    footerText: "Audio settings"
    onFooterClicked: PanelService.open("settings", { page: "audio" })

    body: ColumnLayout {
        spacing: Metrics.panelGap

        CardSection {
            Layout.fillWidth: true
            title: "Screen"
            padding: Metrics.spaceSm
            ListRow {
                Layout.fillWidth: true
                level: 1
                icon: "󰹑"
                title: HyprlandService.screencastActive ? "Screen is being shared" : "Not shared"
                subtitle: HyprlandService.screencastActive ? "An app records or shares a screen or window" : ""
                active: HyprlandService.screencastActive
            }
        }

        CardSection {
            Layout.fillWidth: true
            title: "Microphone"
            padding: Metrics.spaceSm
            spacing: Metrics.spaceXxs

            EmptyState {
                Layout.fillWidth: true
                visible: AudioService.captureStreams.length === 0
                icon: "󰍭"
                title: "No app is using the microphone"
            }
            Repeater {
                model: AudioService.captureStreams
                ListRow {
                    required property var modelData
                    Layout.fillWidth: true
                    level: 1
                    iconSource: AudioService.streamIcon(modelData).length ? Quickshell.iconPath(AudioService.streamIcon(modelData), true) : ""
                    icon: "󰍬"
                    title: AudioService.streamLabel(modelData)
                    subtitle: AudioService.micMuted ? "Recording (microphone muted)" : "Recording"
                    active: !AudioService.micMuted
                }
            }

            ListRow {
                focusOnTab: true
                Layout.fillWidth: true
                level: 1
                icon: AudioService.micMuted ? "󰍭" : "󰍬"
                title: "Microphone"
                subtitle: AudioService.source === null ? "No input device" : AudioService.micMuted ? "Muted for all apps" : "On"
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
