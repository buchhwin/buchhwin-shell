import QtQuick
import qs.shell.widgets
import qs.theme
import qs.services
import qs.shell.components

// The running countdown (TimerService) wherever the notch's own chip is not:
// a bar in work mode showed nothing at all while a timer ran, so its end came
// as a surprise. The glyph says what it counts - a timer, or a Focus session
// (AdaptiveService.focusFor) - and the time left beside it; medium names it,
// large adds how much is left as a bar. Hidden while nothing runs, as the
// recording chip is. A click stops it (the glyph turns into a stop symbol on
// hover), as the notch chip's does; a Focus session ends with it.
Item {
    id: root
    property var instance: null
    property real scaleFactor: 1
    property string sizeClass: "small"
    property bool hovered: false
    property string alignment: "right"
    property bool inGroup: false
    // A bar down the screen stacks the glyph above the time (WidgetBase).
    property bool vertical: false
    // The surface's inks, handed on: the notch's overview is black in both
    // themes and gives its own.
    property color textColor: Colors.text
    property color mutedTextColor: Colors.mutedText
    property color glyphInk: textColor
    property color trackColor: Colors.track
    property bool onDark: false
    property real availableWidth: -1
    readonly property bool hasData: TimerService.running
    readonly property bool focusRun: TimerService.kind === "focus"

    implicitWidth: content.implicitWidth
    implicitHeight: content.implicitHeight

    WidgetBase {
        id: content
        anchors.centerIn: parent
        scaleFactor: root.scaleFactor
        sizeClass: root.sizeClass
        inGroup: root.inGroup
        vertical: root.vertical
        textColor: root.textColor
        mutedTextColor: root.mutedTextColor
        glyphInk: root.glyphInk
        trackColor: root.trackColor
        onDark: root.onDark
        availableWidth: root.availableWidth
        // On hover the stop it will do, in the text's ink: the muted one
        // read as a disabled glyph rather than as the click's action.
        icon: stopMouse.containsMouse ? Icons.stop : root.focusRun ? Icons.focus : "󰔛"
        iconColor: stopMouse.containsMouse ? root.textColor : content.accentInk
        label: TimerService.remainingText
        maxLabelWidth: 90
        name: root.focusRun ? "Focus" : "Timer"
        meter: TimerService.running ? TimerService.fraction : -1
    }

    // One click stops the timer or ends the session, so it says so first,
    // where the surface has a layer for bubbles (ToolTipHost).
    MouseArea {
        id: stopMouse
        anchors.fill: parent
        anchors.margins: -Metrics.spaceXs
        hoverEnabled: true
        cursorShape: Qt.PointingHandCursor
        onEntered: stopTip.arm()
        onExited: stopTip.release()
        onClicked: {
            stopTip.release()
            TimerService.stop()
        }
    }
    ToolTipHost {
        id: stopTip
        anchorItem: root
        text: root.focusRun ? "End Focus" : "Stop the timer"
    }
}
