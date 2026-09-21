import QtQuick
import qs.shell.widgets
import qs.theme
import qs.services

// Red dot with the elapsed time while the screen is recorded; hidden
// otherwise. A click stops the recording (the dot turns into a stop symbol on
// hover).
Item {
    id: root
    property var instance: null
    property real scaleFactor: 1
    property string sizeClass: "small"
    property bool hovered: false
    property string alignment: "right"
    property bool inGroup: false
    // A bar that runs down the screen: the dot goes above the elapsed time
    // rather than beside it. `WidgetBase` already turns its row into a column
    // when it is told; this file simply never told it, so the chip drew a
    // full-width row on a strip a pill wide.
    property bool vertical: false
    // The surface decides the ink: the notch is black in both themes, so a
    // widget placed there is handed its colours instead of the theme's.
    property color textColor: Colors.text
    property color mutedTextColor: Colors.mutedText
    readonly property bool hasData: RecordingService.active

    implicitWidth: content.implicitWidth
    implicitHeight: content.implicitHeight

    WidgetBase {
        id: content
        anchors.centerIn: parent
        scaleFactor: root.scaleFactor
        sizeClass: root.sizeClass
        inGroup: root.inGroup
        vertical: root.vertical
        icon: stopMouse.containsMouse ? "󰓛" : "󰑊"
        iconColor: Colors.recording
        // "Saving …" has nowhere to go on a strip a pill wide, and the
        // elapsed time is what the chip is for, so stacked it stays on the
        // figures.
        label: RecordingService.busy === "stopping" && !root.vertical
            ? "Saving …" : RecordingService.elapsedText
        maxLabelWidth: root.vertical ? 64 : 120
    }

    MouseArea {
        id: stopMouse
        anchors.fill: parent
        anchors.margins: -Metrics.spaceXs
        hoverEnabled: true
        cursorShape: Qt.PointingHandCursor
        onClicked: RecordingService.stop()
    }
}
