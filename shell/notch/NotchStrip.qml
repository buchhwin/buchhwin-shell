import Quickshell
import QtQuick
import qs.theme
import qs.services
import "../../services/notch/NotchLogic.js" as Logic

// The always-visible strip: the list the user arranged, in its order. The
// notch draws two of them itself - the time, which carries the notch's own
// typography rather than a widget's, and the recording chip, whose dot turns
// into a stop button - and falls back to the widget file for everything else,
// handed the notch's colours because the notch is black in both themes.
//
// Its width is measured, not computed: what the strip carries is a list now,
// not a clock with an optional chip beside it.
Item {
    id: root
    property real scaleFactor: 1
    // The screen this strip is drawn on. Empty means it reports nothing, which
    // is what the copy inside the expanded notch wants while it is not the one
    // on screen.
    property string screenName: ""
    // Where this strip's window sits on the screen; see Notch.reportOrigin.
    property point reportOrigin: Qt.point(0, 0)
    // While a recording runs the chip leads the strip, unless the list carries
    // one itself - the same rule the pill bar follows for its recording pill.
    readonly property var items: Logic.stripItems(NotchService.collapsedItems, RecordingService.active)

    implicitWidth: row.implicitWidth
    implicitHeight: Metrics.notchHeight

    SystemClock { id: clock; precision: SystemClock.Minutes }

    // ---- where its parts are ---------------------------------------------
    // The notch is its own layer surface and the layout editor covers it, so
    // the editor cannot host the strip; it works on the real one and the strip
    // says where its parts sit. Reported once the morph has settled, never
    // while something is still moving - a rectangle that keeps changing makes
    // the drop index chase itself.
    readonly property bool reporting: screenName.length > 0 && NotchService.arranging && visible

    function screenRect(item) {
        const topLeft = item.mapToItem(null, 0, 0)
        return { x: Math.round(topLeft.x + reportOrigin.x), y: Math.round(topLeft.y + reportOrigin.y),
                 width: Math.round(item.width), height: Math.round(item.height) }
    }

    function reportRects() {
        if (!screenName.length) return
        LayoutService.reportSurfaceRect(screenName, "notchzone:collapsed",
                                        reporting ? screenRect(row) : null)
        for (let index = 0; index < items.length; ++index) {
            const id = items[index].id
            if (!id.length) continue
            const part = parts.itemAt(index)
            LayoutService.reportSurfaceRect(screenName, "notch:" + id,
                                            reporting && part ? screenRect(part) : null)
        }
    }

    function clearRects() {
        if (!screenName.length) return
        LayoutService.reportSurfaceRect(screenName, "notchzone:collapsed", null)
        for (const item of items)
            if (item.id.length) LayoutService.reportSurfaceRect(screenName, "notch:" + item.id, null)
    }

    onReportingChanged: reportTimer.restart()
    onXChanged: reportTimer.restart()
    onWidthChanged: reportTimer.restart()
    // The strip does not move inside its own surface when the screen changes
    // size, so nothing above notices - but every rectangle it reports is
    // offset by where that surface starts, and that does move. Without this
    // the editor's item frames go stale together with the notch's outline,
    // for the same reason and at the same moment.
    onReportOriginChanged: reportTimer.restart()
    Component.onCompleted: reportTimer.restart()
    Component.onDestruction: clearRects()

    Timer {
        id: reportTimer
        interval: Animations.hover
        onTriggered: root.reportRects()
    }

    Row {
        id: row
        anchors.centerIn: parent
        spacing: Metrics.spaceMd * root.scaleFactor

        Repeater {
            id: parts
            model: root.items
            Loader {
                required property var modelData
                anchors.verticalCenter: parent.verticalCenter
                onWidthChanged: reportTimer.restart()
                sourceComponent: modelData.type === "clock" ? timePart
                    : modelData.type === "recording" ? recordingPart : widgetPart
            }
        }
    }

    // The notch's own time: tabular, tracked, at the notch's size.
    Component {
        id: timePart
        Text {
            text: Logic.timeText(clock.date)
            color: Colors.notchText
            font.family: Typography.family
            font.pixelSize: Typography.notchTimeSize * root.scaleFactor
            font.weight: Typography.semibold
            font.letterSpacing: Typography.pillClockTracking
            font.features: { "tnum": 1 }
            renderType: Typography.renderType
        }
    }

    // A red dot with the elapsed time; a click stops the recording, and the
    // dot squares off under the pointer to say so.
    Component {
        id: recordingPart
        Item {
            implicitWidth: chip.implicitWidth
            implicitHeight: chip.implicitHeight
            Row {
                id: chip
                anchors.centerIn: parent
                spacing: (Metrics.spaceXs + Metrics.spaceXxs) * root.scaleFactor
                Rectangle {
                    anchors.verticalCenter: parent.verticalCenter
                    width: Metrics.notchRecordingDot * root.scaleFactor
                    height: width
                    radius: stop.containsMouse ? Metrics.spaceXxs : width / 2
                    color: Colors.recording
                }
                Text {
                    anchors.verticalCenter: parent.verticalCenter
                    text: RecordingService.busy === "stopping" ? "Saving …" : RecordingService.elapsedText
                    color: Colors.recording
                    font.family: Typography.family
                    font.pixelSize: Typography.notchTimeSize * root.scaleFactor
                    font.weight: Typography.semibold
                    font.features: { "tnum": 1 }
                    renderType: Typography.renderType
                }
            }
            MouseArea {
                id: stop
                anchors.fill: parent
                anchors.margins: -Metrics.spaceXs
                hoverEnabled: true
                cursorShape: Qt.PointingHandCursor
                onClicked: RecordingService.stop()
            }
        }
    }

    // Anything else is a widget: the same file the desktop and the bar load,
    // compact and told to draw on black.
    Component {
        id: widgetPart
        Loader {
            readonly property var entry: WidgetRegistry.type(modelData.type)
            source: WidgetRegistry.source(modelData.type)
            onLoaded: {
                // See the overview: three types share one file and are told
                // apart by `options.metric`.
                // `screen` as well as `type`; see NotchOverview.
                item.instance = { id: modelData.id, type: modelData.type,
                                  screen: root.screenName,
                                  options: entry && entry.options ? entry.options : {} }
                item.scaleFactor = root.scaleFactor
                item.sizeClass = "small"
                // The strip really is a cramped row, so this one stays.
                item.inGroup = true
                item.textColor = Colors.notchText
                item.mutedTextColor = Colors.notchMutedText
            }
        }
    }
}
