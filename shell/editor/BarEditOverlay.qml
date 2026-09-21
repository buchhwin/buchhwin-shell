import QtQuick
import qs.theme
import qs.services
import qs.shell.components
import "../../services/arrange/ArrangeLogic.js" as Arrange
import "../../services/bar/BarLogic.js" as BarLogic
import "../../services/LayoutLogic.js" as Logic

// Bar editing inside the layout editor (desktop modes "Pills" and "Bar").
//
// It edits the real bar in place. The bar is a layer surface of its own, so
// the editor cannot host its pills; instead every pill and every item reports
// where it is (LayoutService.surfaceRects) and this overlay puts the frames, the
// drag surfaces and the drop marker exactly there. Before, the bar was edited
// through a copy drawn below it, which is why its arrow keys reordered where a
// widget's nudge moves and why Del removed an item before its pill.
Item {
    id: overlay
    required property var editor
    readonly property string screenName: editor.screenName
    readonly property var bar: LayoutService.bar
    readonly property string unit: bar.style === "bar" ? "group" : "pill"

    // Drag state; `dropIndex` counts the target zone without the dragged pill.
    property string dragPill: ""
    property string dropZone: ""
    property int dropIndex: -1
    property real ghostX: 0
    property real ghostY: 0

    readonly property var zoneKeys: ["left", "center", "right"]
    // Which way the bar runs. Every piece of this file that has a direction
    // asks it: the zone the pointer is over, the index a drop would take, the
    // marker, the drag threshold and the labels.
    readonly property bool vertical: BarLogic.vertical(bar.edge)

    function rectOf(key) {
        const unused = LayoutService.surfaceRects
        return LayoutService.surfaceRect(screenName, key)
    }
    // Whole rectangles, not just x and width: the shared maths reads a cell's
    // band before its place within it, which is what lets the same functions
    // serve a grid. A bar is one band, so the band half never decides anything
    // - but it has to be there to be ignored, and which axis is the band turns
    // with the bar.
    function zoneRects() {
        return zoneKeys.map(key => {
            const rect = rectOf("zone:" + key)
            return rect ? { key: key, x: rect.x, y: rect.y,
                            width: rect.width, height: rect.height } : null
        }).filter(Boolean)
    }
    function pillRects(zone) {
        return (bar[zone] || []).map(pill => {
            const rect = rectOf(pill.id)
            return rect ? { id: pill.id, x: rect.x, y: rect.y,
                            width: rect.width, height: rect.height } : null
        }).filter(Boolean)
    }
    // The bar's own place across its own axis, so the marker and the ghost sit
    // on it. Still called `barTop` because for a horizontal bar that is what
    // it is, and the callers read better for it.
    function barTop() {
        for (const key of zoneKeys) {
            const rect = rectOf("zone:" + key)
            if (rect) return rect
        }
        return null
    }
    function marker() {
        const zone = rectOf("row:" + dropZone)
        return Arrange.markerRect(pillRects(dropZone), dropIndex, dragPill, zone, Metrics.pillGap, vertical)
    }

    function beginDrag(pillId) {
        dragPill = pillId
        LayoutService.editorDragging = pillId
        dropZone = ""
        dropIndex = -1
    }
    function updateDrag(x, y) {
        ghostX = x
        ghostY = y
        dropZone = Arrange.zoneAt(zoneRects(), x, y, vertical)
        dropIndex = Arrange.insertIndexAt(pillRects(dropZone), x, y, dragPill, vertical)
    }
    function endDrag() {
        if (dragPill.length && dropZone.length
            && Arrange.changes(LayoutService.barPlace(dragPill), dropZone, dropIndex))
            LayoutService.barMovePillTo(dragPill, dropZone, dropIndex)
        cancelDrag()
    }
    function cancelDrag() {
        dragPill = ""
        LayoutService.editorDragging = ""
        dropZone = ""
        dropIndex = -1
    }

    // The three drop thirds, only while something is being dragged: a frame
    // around the whole bar at rest would compete with the pills' own frames.
    Repeater {
        model: overlay.dragPill.length ? overlay.zoneKeys : []
        Rectangle {
            required property var modelData
            readonly property var rect: overlay.rectOf("zone:" + modelData)
            readonly property bool target: overlay.dropZone === modelData
            visible: rect !== null
            x: rect ? rect.x : 0
            y: rect ? rect.y : 0
            width: rect ? rect.width : 0
            height: rect ? rect.height : 0
            radius: Metrics.radiusCard
            color: target ? Colors.accentSoft : Colors.scrim
            border.width: target ? Metrics.focusBorderWidth : Metrics.borderWidth
            border.color: target ? Colors.accent : Colors.border

            SectionLabel {
                anchors.horizontalCenter: parent.horizontalCenter
                anchors.top: parent.bottom
                anchors.topMargin: Metrics.spaceXs
                // Start and end rather than left and right once the bar runs
                // down the screen: "Left" on a left-hand bar means nothing.
                text: overlay.vertical
                    ? (modelData === "left" ? "Top" : modelData === "center" ? "Center" : "Bottom")
                    : (modelData === "left" ? "Left" : modelData === "center" ? "Center" : "Right")
            }
        }
    }

    // One frame and one drag surface per pill, on top of the real pill.
    Repeater {
        model: Logic.barPillIds(overlay.bar)
        Item {
            id: frame
            required property var modelData
            readonly property var rect: overlay.rectOf(modelData)
            readonly property bool selected: overlay.editor.barPill === modelData
            readonly property bool dragging: overlay.dragPill === modelData
            // Stays visible while it is being dragged: hiding the item takes
            // the mouse grab with it, and the drag ends on the first move.
            visible: rect !== null
            x: rect ? rect.x - Metrics.spaceXxs : 0
            y: rect ? rect.y - Metrics.spaceXxs : 0
            width: rect ? rect.width + Metrics.spaceXxs * 2 : 0
            height: rect ? rect.height + Metrics.spaceXxs * 2 : 0

            // Never filled: the frame lies on top of the real pill, so a fill
            // would hide what is being edited. The widget editor can fill
            // because it draws the widget inside its own card.
            Rectangle {
                anchors.fill: parent
                // While this pill is the one being dragged, the ghost under the
                // pointer stands for it and the frame steps back.
                visible: !frame.dragging
                radius: Metrics.radiusCard
                color: "transparent"
                border.width: frame.selected ? Metrics.focusBorderWidth : Metrics.borderWidth
                border.color: frame.selected ? Colors.accent : Colors.border
            }

            MouseArea {
                anchors.fill: parent
                acceptedButtons: Qt.LeftButton
                // Both are what makes the move events arrive at all: without
                // them the press is delivered and every motion afterwards goes
                // somewhere else, so a drag looks like a click.
                hoverEnabled: true
                preventStealing: true
                cursorShape: frame.dragging ? Qt.ClosedHandCursor : Qt.OpenHandCursor
                property real pressX: 0
                property real pressY: 0
                property bool moved: false
                onPressed: mouse => {
                    overlay.editor.forceActiveFocus()
                    const point = mapToItem(overlay, mouse.x, mouse.y)
                    pressX = point.x
                    pressY = point.y
                    moved = false
                    overlay.editor.selectBar(frame.modelData, overlay.itemUnder(frame.modelData, point.x, point.y))
                }
                onPositionChanged: mouse => {
                    if (!pressed) return
                    const point = mapToItem(overlay, mouse.x, mouse.y)
                    // The threshold is along the bar: a pill on a vertical bar
                    // is dragged up and down, and measuring x there means a
                    // drag never starts.
                    const travelled = overlay.vertical ? Math.abs(point.y - pressY) : Math.abs(point.x - pressX)
                    if (!moved && travelled < Metrics.dragThreshold) return
                    if (!moved) {
                        moved = true
                        overlay.beginDrag(frame.modelData)
                    }
                    overlay.updateDrag(point.x, point.y)
                }
                onReleased: {
                    if (moved) overlay.endDrag()
                    moved = false
                }
                onCanceled: { overlay.cancelDrag(); moved = false }
            }
        }
    }

    // Which item of a pill sits under a screen point, or -1 for the pill
    // itself. Measured along the bar, whichever way it runs: the items of a
    // pill stack downwards on a vertical bar and every one of them has the
    // same x there, so asking about x answered "the first one" wherever the
    // pointer was.
    function itemUnder(pillId, x, y) {
        const place = LayoutService.barPlace(pillId)
        if (!place) return -1
        const items = LayoutService.bar[place.zone][place.index].items
        if (items.length < 2) return -1
        const along = vertical ? y : x
        for (let index = 0; index < items.length; ++index) {
            const rect = rectOf(pillId + "#" + index)
            if (!rect) continue
            const start = vertical ? rect.y : rect.x
            const size = vertical ? rect.height : rect.width
            if (along >= start && along <= start + size) return index
        }
        return -1
    }

    // The selected item inside a pill of several.
    Rectangle {
        readonly property var rect: overlay.editor.barItem >= 0
            ? overlay.rectOf(overlay.editor.barPill + "#" + overlay.editor.barItem) : null
        visible: rect !== null && !overlay.dragPill.length
        x: rect ? rect.x : 0
        y: rect ? rect.y : 0
        width: rect ? rect.width : 0
        height: rect ? rect.height : 0
        radius: Metrics.radiusInner
        color: "transparent"
        border.width: Metrics.focusBorderWidth
        border.color: Colors.accent
    }

    // Insertion marker at the gap the dragged pill would take: a hairline
    // *across* the bar, so it turns with it.
    Rectangle {
        // Not `top`: an Item already has an anchor line of that name.
        readonly property var line: overlay.barTop()
        readonly property var spot: overlay.marker()
        readonly property real thin: Metrics.focusBorderWidth * 2
        visible: overlay.dragPill.length > 0 && overlay.dropZone.length > 0 && line !== null
        width: overlay.vertical ? (line ? line.width : 0) : thin
        height: overlay.vertical ? thin : (line ? line.height : 0)
        radius: thin / 2
        x: overlay.vertical ? (line ? line.x : 0) : spot.x - thin / 2
        y: overlay.vertical ? spot.y - thin / 2 : (line ? line.y : 0)
        color: Colors.accent
    }

    // Follows the pointer while dragging, so the pill is visible over a zone.
    Rectangle {
        visible: overlay.dragPill.length > 0
        x: overlay.ghostX - width / 2
        y: overlay.ghostY - height / 2
        width: ghostLabel.implicitWidth + Metrics.spaceLg * 2
        height: Metrics.pillHeight
        radius: height / 2
        color: Colors.pill
        border.width: Metrics.focusBorderWidth
        border.color: Colors.accent

        ShellText {
            id: ghostLabel
            anchors.centerIn: parent
            text: overlay.editor.barPillLabel(overlay.dragPill)
            role: "small"
        }
    }
}
