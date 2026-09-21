import QtQuick
import qs.shell.widgets
import qs.theme
import qs.services

// Shows while the microphone is recording or the screen is shared; hidden
// otherwise.
WidgetBase {
    readonly property bool sharing: HyprlandService.screencastActive
    readonly property bool recording: AudioService.micInUse
    hasData: sharing || recording
    icon: sharing ? "󰹑" : "󰍬"
    iconColor: sharing ? Colors.danger : Colors.warning
    label: sharing && recording ? "Screen and microphone" : sharing ? "Screen is shared" : "Microphone active"
    maxLabelWidth: 200
    name: "In use"
}
