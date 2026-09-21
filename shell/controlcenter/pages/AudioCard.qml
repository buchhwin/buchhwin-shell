import QtQuick
import QtQuick.Layouts
import qs.theme
import qs.services
import qs.shell.components

ShellCard {
    id: root
    signal openDetails()
    property string tab: "system"
    implicitHeight: column.implicitHeight + Metrics.spaceLg * 2

    // The shape of the cell it was given. A card too short for the tabs plus
    // what is under them keeps the volume row - which is what the tile is for
    // - and drops the tabs and the device name rather than showing the top
    // half of all three.
    property string shape: "small"
    readonly property bool tight: shape !== "tall" && shape !== "large"
    // `tab` is the user's, but the apps tab has nothing to draw at this size,
    // so a short card is always on the system one.
    readonly property string shownTab: tight ? "system" : tab

    ColumnLayout {
        id: column
        // Centred in the cell rather than stretched across it. The cell decides
        // the height now, and a layout that fills it hands every spare pixel to
        // whichever child happens to be a layout itself - which is how a tall
        // tile ended up with its text pinned to the top and a growing empty
        // band under it. Centred, a cell that is too short overflows instead,
        // and QuickSlot clips that to the cell's own edge.
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.verticalCenter: parent.verticalCenter
        anchors.leftMargin: Metrics.spaceLg
        anchors.rightMargin: Metrics.spaceLg
        spacing: Metrics.spaceMd

        SegmentedControl {
            Layout.fillWidth: true
            visible: !root.tight
            style: "underline"
            current: root.tab
            options: [{ value: "system", label: "System" }, { value: "apps", label: "Apps" }]
            onSelected: value => root.tab = value
        }

        ColumnLayout {
            visible: root.shownTab === "system"
            Layout.fillWidth: true
            spacing: Metrics.spaceSm

            ListRow {
                Layout.fillWidth: true
                visible: !root.tight
                icon: AudioService.deviceIcon(AudioService.sink, false)
                title: AudioService.label(AudioService.sink)
                chevron: true
                onClicked: root.openDetails()
            }
            RowLayout {
                Layout.fillWidth: true
                spacing: Metrics.spaceSm
                ShellButton {
                    icon: AudioService.volumeIcon(AudioService.volume, AudioService.muted)
                    variant: "ghost"; compact: true; iconSize: Metrics.iconMd
                    onClicked: AudioService.toggleMute(AudioService.sink)
                }
                ShellSlider {
                    Layout.fillWidth: true
                    value: AudioService.volume
                    enabledState: AudioService.sink !== null
                    onMoved: value => AudioService.setVolume(AudioService.sink, value)
                }
                ShellText { text: Math.round(AudioService.volume * 100) + "%"; role: "small"; muted: true; Layout.minimumWidth: Metrics.iconXl }
                // The way into the audio page, for the short shape only.
                //
                // The device row above carries it at full size and is dropped
                // here for want of height - which left the small tile with a
                // mute button, a slider and no way to reach the output list at
                // all. The user found it: "I can only set the volume, I cannot
                // get into the audio window the way I can from the
                // microphone." A chevron needs no row of its own.
                ShellButton {
                    visible: root.tight
                    focusOnTab: true
                    icon: Icons.forward
                    variant: "ghost"; compact: true; iconSize: Metrics.iconSm
                    toolTip: "Audio settings"
                    onClicked: root.openDetails()
                }
            }
        }

        ColumnLayout {
            visible: root.shownTab === "apps"
            Layout.fillWidth: true
            spacing: Metrics.spaceXs

            EmptyState {
                Layout.fillWidth: true
                Layout.topMargin: Metrics.spaceSm
                visible: AudioService.playbackStreams.length === 0
                icon: "󰝛"
                title: "No app is playing audio"
            }
            Repeater {
                model: AudioService.playbackStreams.slice(0, 3)
                StreamRow { required property var modelData; node: modelData; showOutput: false; Layout.fillWidth: true }
            }
        }
    }
}
