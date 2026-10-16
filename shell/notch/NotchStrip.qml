import Quickshell
import QtQuick
import QtQuick.Shapes
import qs.theme
import qs.services
import "../../services/notch/NotchLogic.js" as Logic
import "../../services/model/KeyedLogic.js" as Keyed

// The always-visible strip: the list the user arranged, in its order. The
// notch draws two of them itself - the time, which carries the notch's own
// typography rather than a widget's, and the recording chip, whose dot turns
// into a stop button - and falls back to the widget file for everything else,
// handed the notch's colours because the notch is black in both themes.
//
// Its width is measured, not computed: what the strip carries is a list now,
// not a clock with an optional chip beside it. Measured around the clock,
// when there is one: the notch is centred on the screen, and the time should
// be too, so the lighter side is padded to the heavier one's width
// (NotchLogic.stripSymmetry) rather than the row simply being centred. The
// lighter side's padding is split: half of it outside the group, half between
// the group and the clock, so the group stands in the middle of its half.
Item {
    id: root
    property real scaleFactor: 1
    // Where the clock sits inside the row, written by its delegate. Stale
    // values do no harm: `hasClock` is read from the list itself.
    property real clockX: -1
    property real clockWidth: 0
    readonly property bool hasClock: items.some(item => item && item.type === "clock")
    readonly property int clockIndex: items.findIndex(item => item && item.type === "clock")
    readonly property var symmetry: Logic.stripSymmetry(row.implicitWidth,
        hasClock ? clockX : -1, hasClock ? clockWidth : 0)

    // The inner halves of the pads, as a shift of the parts: everything from
    // the clock on moves by half the left pad (the room before the clock),
    // everything after the clock by half the right pad as well (the room
    // after it). A shift and not a spacer item in the row, because the row
    // is what the pads are measured from: a spacer inside it would be
    // measured with it, and the pad would size the measurement that sizes
    // the pad - a binding loop, with the log to show for it. The row's `x`
    // carries the outer half of the left pad (`symmetry.offset`), so the
    // clock lands where it did: in the middle of the strip.
    function padShift(index) {
        if (clockIndex < 0) return 0
        return (index >= clockIndex ? symmetry.leftPad / 2 : 0)
             + (index > clockIndex ? symmetry.rightPad / 2 : 0)
    }
    // Each item with a key that is all of it: the type and id, and the
    // display and options a widget is loaded with. The recording and timer
    // chips have no id and differ by type; the count after `#` keeps two
    // equal items apart.
    // What the model below was handed last, kept outside any binding's
    // dependencies: each change hands back the very same objects for the
    // entries that stayed, which is the only way Quickshell's ScriptModel
    // matches them right (services/model/KeyedLogic.js).
    property var lastParts: ({ list: [] })
    function keptParts(next) {
        const list = Keyed.keep(lastParts.list, next, "partKey")
        lastParts.list = list
        return list
    }
    function partKeys(list) {
        const seen = {}
        return list.map(item => {
            const text = JSON.stringify(item)
            seen[text] = (seen[text] || 0) + 1
            return Object.assign({ partKey: text + "#" + seen[text] }, item)
        })
    }
    // The screen this strip is drawn on. Empty means it reports nothing, which
    // is what the copy inside the expanded notch wants while it is not the one
    // on screen.
    property string screenName: ""
    // Where this strip's window sits on the screen; see Notch.reportOrigin.
    property point reportOrigin: Qt.point(0, 0)
    // While a recording runs the chip leads the strip, unless the list carries
    // one itself - the same rule the pill bar follows for its recording pill.
    readonly property var items: Logic.stripItems(NotchService.collapsedItems, RecordingService.active, TimerService.running)

    implicitWidth: symmetry.width
    implicitHeight: NotchService.bodyHeight

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
        // The whole strip, padding included: a drop beside the lighter side
        // is a drop on the strip.
        LayoutService.reportSurfaceRect(screenName, "notchzone:collapsed",
                                        reporting ? screenRect(root) : null)
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
        anchors.verticalCenter: parent.verticalCenter
        // The symmetric strip centred in whatever width the notch gives it,
        // then the row shifted by the outer half of the left pad; the inner
        // halves are the parts' own shift (`padShift`), and the two together
        // put the clock's centre on the strip's centre.
        x: (root.width - root.symmetry.width) / 2 + root.symmetry.offset
        spacing: Metrics.spaceMd * root.scaleFactor

        Repeater {
            id: parts
            // Matched, not rebuilt: `items` is a new list on every write of
            // the layout (a mode or profile switch, an undo, any edit) and
            // whenever a recording or the timer starts or stops, and on a
            // plain array every part on every screen was thrown away and
            // loaded again. The key is the whole item (`partKeys`), so a part
            // whose display or options changed is still loaded anew - the
            // widget reads them once, in `onLoaded` - and a kept one gets the
            // same values again: nothing in it moves, and no part here has a
            // spring on its size to start running (pitfall 40). Kept parts
            // are handed over as the same objects (`keptParts`).
            model: ScriptModel { values: root.keptParts(root.partKeys(root.items)); objectProp: "partKey" }
            Loader {
                required property var modelData
                required property int index
                readonly property bool isClock: modelData.type === "clock"
                anchors.verticalCenter: parent.verticalCenter
                onWidthChanged: { reportTimer.restart(); if (isClock) root.clockWidth = width }
                onXChanged: if (isClock) root.clockX = x
                Component.onCompleted: if (isClock) { root.clockX = x; root.clockWidth = width }
                // The pad's inner half. `x` stays the row's own, which is what
                // `clockX` measures; the drawn and the hit-tested place carry
                // the shift, and so does `screenRect`, which maps through it.
                transform: Translate { x: root.padShift(index) }
                sourceComponent: modelData.type === "clock" ? timePart
                    : modelData.type === "recording" ? recordingPart
                    : modelData.type === "timer" ? timerPart : widgetPart
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
            textFormat: Text.PlainText
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
                    textFormat: Text.PlainText
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

    // A countdown: a ring that empties and the time left; a click stops it.
    Component {
        id: timerPart
        Item {
            implicitWidth: timerChip.implicitWidth
            implicitHeight: timerChip.implicitHeight
            Row {
                id: timerChip
                anchors.centerIn: parent
                spacing: (Metrics.spaceXs + Metrics.spaceXxs) * root.scaleFactor
                Shape {
                    id: timerRing
                    anchors.verticalCenter: parent.verticalCenter
                    width: Metrics.notchTimerRing * root.scaleFactor
                    height: width
                    preferredRendererType: Shape.CurveRenderer
                    readonly property real r: (width - Metrics.notchRingStroke) / 2
                    ShapePath {
                        fillColor: "transparent"
                        strokeColor: Colors.notchTrack
                        strokeWidth: Metrics.notchRingStroke
                        PathAngleArc { centerX: timerRing.width / 2; centerY: timerRing.height / 2
                                       radiusX: timerRing.r; radiusY: timerRing.r; startAngle: 0; sweepAngle: 360 }
                    }
                    ShapePath {
                        fillColor: "transparent"
                        strokeColor: timerStop.containsMouse ? Colors.notchMutedText : Colors.accent
                        strokeWidth: Metrics.notchRingStroke
                        capStyle: ShapePath.RoundCap
                        PathAngleArc { centerX: timerRing.width / 2; centerY: timerRing.height / 2
                                       radiusX: timerRing.r; radiusY: timerRing.r
                                       startAngle: -90; sweepAngle: 360 * TimerService.fraction }
                    }
                }
                Text {
                    anchors.verticalCenter: parent.verticalCenter
                    text: TimerService.remainingText
                    color: Colors.notchText
                    font.family: Typography.family
                    font.pixelSize: Typography.notchTimeSize * root.scaleFactor
                    font.weight: Typography.semibold
                    font.features: { "tnum": 1 }
                    textFormat: Text.PlainText
                    renderType: Typography.renderType
                }
            }
            MouseArea {
                id: timerStop
                anchors.fill: parent
                anchors.margins: -Metrics.spaceXs
                hoverEnabled: true
                cursorShape: Qt.PointingHandCursor
                onClicked: TimerService.stop()
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
                // The registry's options, then the item's own on top (a
                // workspace style chosen for this notch only).
                item.instance = { id: modelData.id, type: modelData.type,
                                  screen: root.screenName,
                                  options: Object.assign({}, entry && entry.options ? entry.options : {},
                                                         modelData.options || {}) }
                item.scaleFactor = root.scaleFactor
                // "icon": the glyph alone - a battery without its percentage.
                item.sizeClass = modelData.display === "icon" ? "icon" : "small"
                // The strip really is a cramped row, so this one stays.
                item.inGroup = true
                item.textColor = Colors.notchText
                item.mutedTextColor = Colors.notchMutedText
                // The neutral glyph ink: the accent when the strip is asked
                // for it (notch.accentGlyphs "all"), else the notch's white. A
                // binding, so a new accent or a changed setting reaches a
                // widget that is already loaded. Only widgets built on
                // WidgetBase have one (and the groove); the workspace dots or
                // the weather draw their own and are left as they are.
                if (item.glyphInk !== undefined)
                    item.glyphInk = Qt.binding(() => NotchService.stripGlyphsInAccent ? Colors.notchAccent : Colors.notchText)
                if (item.trackColor !== undefined) item.trackColor = Colors.notchTrack
                // The strip is black in both themes, so a state colour
                // (charging, low, a tunnel up, unread) is its on-dark variant:
                // the light theme's green and red are made for light panels.
                if (item.onDark !== undefined) item.onDark = true
            }
        }
    }
}
