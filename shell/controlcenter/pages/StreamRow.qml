import Quickshell
import QtQuick
import QtQuick.Layouts
import qs.theme
import qs.services
import qs.shell.components

// One app stream: volume, mute and (optionally) the output it plays on.
ColumnLayout {
    id: root
    required property var node
    // Output selector ("Default output" + every sink); off in the compact
    // overview card.
    property bool showOutput: true
    spacing: Metrics.spaceXxs

    // Panels hide instead of destroying their pages: read the routing
    // metadata only while the row is on screen.
    readonly property bool routingWanted: showOutput && QsWindow.window !== null && QsWindow.window.visible
    property bool routingTracked: false
    onRoutingWantedChanged: syncRouting()
    Component.onCompleted: syncRouting()
    Component.onDestruction: if (routingTracked) AudioService.untrackRouting()

    function syncRouting() {
        if (routingWanted === routingTracked) return
        routingTracked = routingWanted
        if (routingTracked) AudioService.trackRouting()
        else AudioService.untrackRouting()
    }

    RowLayout {
        Layout.fillWidth: true
        spacing: Metrics.spaceSm
        Image {
            Layout.preferredWidth: Metrics.iconMd
            Layout.preferredHeight: Metrics.iconMd
            source: AudioService.streamIcon(root.node).length ? Quickshell.iconPath(AudioService.streamIcon(root.node), true) : ""
            sourceSize.width: Metrics.iconMd * 2
            sourceSize.height: Metrics.iconMd * 2
            visible: status === Image.Ready
        }
        ShellText { Layout.fillWidth: true; text: AudioService.streamLabel(root.node); role: "small"; elide: Text.ElideRight }
        ShellText { text: root.node.audio ? Math.round(root.node.audio.volume * 100) + "%" : ""; role: "caption" }
    }
    RowLayout {
        Layout.fillWidth: true
        spacing: Metrics.spaceXs
        ShellButton {
            icon: AudioService.volumeIcon(root.node.audio ? root.node.audio.volume : 0, root.node.audio ? root.node.audio.muted : false)
            variant: "ghost"; compact: true
            toolTip: root.node.audio && root.node.audio.muted ? "Unmute" : "Mute"
            onClicked: AudioService.toggleMute(root.node)
        }
        ShellSlider {
            Layout.fillWidth: true
            value: root.node.audio ? root.node.audio.volume : 0
            onMoved: value => AudioService.setVolume(root.node, value)
        }
    }
    RowLayout {
        visible: root.showOutput
        Layout.fillWidth: true
        spacing: Metrics.spaceXs
        ShellIcon {
            Layout.preferredWidth: Metrics.controlHeightSm
            Layout.preferredHeight: Metrics.controlHeight
            Layout.alignment: Qt.AlignTop
            glyph: "󰓃"; size: Metrics.iconSm; color: Colors.mutedText
        }
        ShellSelect {
            Layout.fillWidth: true
            options: AudioService.outputOptions
            current: AudioService.streamTarget(root.node)
            listHeight: Metrics.rowHeight * 4
            onSelected: value => AudioService.routeStream(root.node, value)
        }
    }
}
