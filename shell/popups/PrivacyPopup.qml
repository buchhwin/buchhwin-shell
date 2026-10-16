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
        spacing: Metrics.pageGap

        CardSection {
            Layout.fillWidth: true
            title: "Screen"
            padding: Metrics.spaceSm
            // Nothing happening is an empty state, the row kind that sits in
            // a card, as on the Microphone card below: the two cards said
            // "nothing" in two ways (a left-aligned row here, a large centred
            // crossed microphone there). Inset like a row's icon.
            EmptyState {
                Layout.fillWidth: true
                Layout.leftMargin: Metrics.spaceLg
                visible: !HyprlandService.screencastActive
                row: true
                icon: "󰹑"
                title: "No app is sharing the screen"
            }
            // A state, not a button: nothing happens on a click.
            ListRow {
                Layout.fillWidth: true
                visible: HyprlandService.screencastActive
                interactive: false
                level: 1
                icon: "󰹑"
                title: "Screen is being shared"
                subtitle: "An app records or shares a screen or window"
                active: true
            }
        }

        CardSection {
            Layout.fillWidth: true
            title: "Microphone"
            padding: Metrics.spaceSm
            spacing: Metrics.spaceXxs

            EmptyState {
                Layout.fillWidth: true
                Layout.leftMargin: Metrics.spaceLg
                visible: AudioService.captureStreams.length === 0
                row: true
                icon: "󰍭"
                title: "No app is using the microphone"
            }
            Repeater {
                model: AudioService.captureStreams
                ListRow {
                    required property var modelData
                    Layout.fillWidth: true
                    interactive: false
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
