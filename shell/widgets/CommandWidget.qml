import QtQuick
import qs.shell.widgets
import qs.theme
import qs.services
import qs.shell.components
import "../../services/widgets/CommandLogic.js" as Logic

// A widget from a command of the user's: the first line it prints, its
// glyph, its name from the medium size up and the second line at large. A
// command that fails (exit status not 0) draws its glyph in the warning ink,
// says "Failed" when it printed nothing, and its exit status on hover.
// A click runs the click command, or asks again without one; a widget whose
// command is not set yet says so and leads to Settings > Widgets, where the
// three are set up (CommandLogic, CommandWidgetService).
Item {
    id: root
    property var instance: null
    property real scaleFactor: 1
    property string sizeClass: "small"
    property bool hovered: false
    property string alignment: "right"
    property bool inGroup: false
    property bool vertical: false
    property color textColor: Colors.text
    property color mutedTextColor: Colors.mutedText
    property color glyphInk: textColor
    property color trackColor: Colors.track
    property bool onDark: false

    readonly property string slot: Logic.slotOf(instance ? instance.type : "", instance ? instance.options : null)
    readonly property var definition: CommandWidgetService.definition(slot)
    readonly property bool configured: definition.command.length > 0
    readonly property var result: CommandWidgetService.results[slot] || null

    // Whether this one runs its command. On the desktop, the bar and the
    // notch it is always on screen; the dashboard binds this to whether it
    // is open (as it does for the system readouts). The first sync waits a
    // turn for what a host hands over in its Loader's `onLoaded`.
    property bool sampling: true
    property bool tracked: false
    onSamplingChanged: syncTracking()
    onSlotChanged: if (tracked) { CommandWidgetService.untrack(trackedSlot); tracked = false; syncTracking() }
    property string trackedSlot: ""
    Component.onCompleted: Qt.callLater(root.syncTracking)
    Component.onDestruction: if (tracked) CommandWidgetService.untrack(trackedSlot)
    function syncTracking() {
        if (sampling === tracked) return
        tracked = sampling
        if (tracked) {
            trackedSlot = slot
            CommandWidgetService.track(slot)
        } else {
            CommandWidgetService.untrack(trackedSlot)
        }
    }

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
        icon: root.definition.icon
        iconColor: root.result && root.result.failed ? content.warningInk : content.glyphInk
        label: !root.configured ? "Set up"
            : !root.result ? "…"
            : root.result.line.length || !root.result.failed ? root.result.line : "Failed"
        name: root.definition.label
        detail: root.result ? root.result.detail : ""
    }

    MouseArea {
        anchors.fill: parent
        anchors.margins: -Metrics.spaceXs
        cursorShape: Qt.PointingHandCursor
        hoverEnabled: true
        onEntered: failTip.arm()
        onExited: failTip.release()
        onClicked: {
            failTip.release()
            CommandWidgetService.click(root.slot)
        }
    }
    ToolTipHost {
        id: failTip
        anchorItem: root
        text: Logic.failureText(root.result)
    }
}
