import QtQuick
import qs.theme
import qs.services
import qs.shell.components
import qs.shell.desktop
import "../../services/LayoutLogic.js" as Logic
import "SnapEngine.js" as Snap

// Editable representation of one placement inside the layout editor.
Item {
    id: card
    required property string placementId
    required property var editor
    readonly property var entry: LayoutService.item(placementId)
    readonly property bool selected: editor.selection.indexOf(placementId) >= 0
    property bool dragging: false
    property bool resizing: false
    property real previewScale: entry ? entry.scale : 1
    property point pressPoint
    property point startPos
    property real startScale: 1
    property real resizeFrom: 0
    // Where the card is while it is dragged. Its place itself stays a
    // binding: assigning x and y ended it for the card's life, and after a
    // drag an undo, an arrow-key nudge or a new scale moved the stored widget
    // but not its card - and every nudge after that started from the same
    // stale place.
    property real dragX: 0
    property real dragY: 0
    // The press may still move the card. Escape ends a drag with the button
    // held (cancelDrag), and the rest of that press must not start it again.
    property bool dragArmed: false

    readonly property var previewItem: entry ? (resizing ? Object.assign({}, entry, { scale: previewScale }) : entry) : null
    readonly property var restingPosition: entry ? Logic.pixelPosition(entry, width, height, editor.width, editor.height) : ({ x: 0, y: 0 })

    width: frame.hasContent ? frame.implicitWidth : placeholder.implicitWidth + Metrics.spaceLg * 2
    height: frame.hasContent ? frame.implicitHeight : placeholder.implicitHeight + Metrics.spaceMd * 2
    x: dragging ? dragX : restingPosition.x
    y: dragging ? dragY : restingPosition.y
    // Only while its widget is there. A removed widget's card goes with its
    // row of the Repeater in the same turn, so there is nothing to fade out.
    // Its position is not animated either: a desktop widget has no
    // neighbours to displace, and x feeds reportRect, so an animated x would
    // keep reporting and never settle.
    visible: entry !== null

    // Editable, so it says so. Not while it is being dragged or resized: it is
    // already following the pointer then.
    Wiggle {
        id: wiggle
        index: card.wiggleIndex
        running: !card.dragging && !card.resizing && !card.selected
    }
    transform: Rotation {
        origin.x: card.width / 2
        origin.y: card.height / 2
        angle: wiggle.angle
    }
    readonly property int wiggleIndex: Math.max(0, card.editor.placementIndex(card.placementId))

    onXChanged: editor.reportRect(placementId, x, y, width, height)
    onYChanged: editor.reportRect(placementId, x, y, width, height)
    onWidthChanged: editor.reportRect(placementId, x, y, width, height)
    onHeightChanged: editor.reportRect(placementId, x, y, width, height)
    Component.onDestruction: {
        cancelDrag()
        editor.forgetRect(placementId)
    }

    // The drag, from the press to the drop, in the editor's coordinates. They
    // are the card's own functions rather than its MouseArea's, so Escape can
    // end a drag (EditLayer.cancelDrags) and a test can drive one.
    function press(point) {
        pressPoint = point
        startPos = Qt.point(x, y)
        dragArmed = true
    }
    function dragTo(point, noSnap) {
        if (!dragArmed) return
        const dx = point.x - pressPoint.x
        const dy = point.y - pressPoint.y
        if (!dragging && Math.abs(dx) + Math.abs(dy) < Metrics.dragThreshold) return
        if (!dragging) {
            dragX = startPos.x
            dragY = startPos.y
            dragging = true
        }
        const result = Snap.snap({ x: startPos.x + dx, y: startPos.y + dy, width: width, height: height },
            editor.otherRects(placementId),
            { screenWidth: editor.width, screenHeight: editor.height, threshold: Metrics.snapThreshold,
              grid: editor.gridEnabled, gridSize: Metrics.gridSize, margin: Metrics.screenMargin,
              disabled: noSnap === true })
        dragX = result.x
        dragY = result.y
        editor.guides = result.guides
    }
    // The undo step is taken at the drop, not when the drag began: nothing is
    // written before it, so the step is the same - and a drag Escape ended,
    // or one let go where it began, leaves none behind.
    function drop() {
        if (dragArmed && dragging && entry
            && (Math.abs(dragX - startPos.x) >= 0.5 || Math.abs(dragY - startPos.y) >= 0.5)) {
            const position = Logic.relativePosition(dragX, dragY, width, height, editor.width, editor.height)
            LayoutService.beginChange()
            LayoutService.updateItem(placementId, position)
            LayoutService.save()
        }
        cancelDrag()
    }
    // Back to where the widget is stored, which is where its card rests.
    function cancelDrag() {
        dragArmed = false
        if (!dragging) return
        dragging = false
        editor.guides = []
    }

    // The resize handle's drag, the same way.
    function beginResize(pointX) {
        if (!entry) return
        resizeFrom = pointX
        startScale = entry.scale
        previewScale = entry.scale
        resizing = true
    }
    function resizeTo(pointX) {
        if (!resizing || !entry) return
        const dx = pointX - resizeFrom
        const base = Math.max(1, width / previewScale)
        const direction = entry.anchorX === "right" ? -1 : 1
        previewScale = Math.max(Metrics.widgetScaleMin, Math.min(Metrics.widgetScaleMax,
            startScale + direction * dx / base))
    }
    // A step and a write only for a scale that changed: a click on the handle
    // took an undo step that undid nothing, rewrote layout.json and rounded a
    // scale that was not on two decimals.
    function endResize() {
        if (!resizing) return
        const next = Math.round(previewScale * 100) / 100
        if (entry && previewScale !== startScale && next !== entry.scale) {
            LayoutService.beginChange()
            LayoutService.updateItem(placementId, { scale: next })
            LayoutService.save()
        }
        resizing = false
    }
    function cancelResize() { resizing = false }

    WidgetFrame {
        id: frame
        item: card.previewItem
        editing: true
        opacity: card.entry && card.entry.visible ? 1 : Effects.disabledOpacity
    }

    // Widgets without current content (e.g. no media player) stay editable.
    // Nothing else is drawn behind it, so it brings its own plate, as the
    // hint lines do: straight on the wallpaper the muted ink vanished on a
    // dark image and the scrim's on a bright one.
    EditorCaption {
        id: placeholder
        anchors.centerIn: parent
        visible: !frame.hasContent
        text: card.entry ? (WidgetRegistry.type(card.entry.type) || { label: card.entry.type }).label + " (empty)" : ""
        role: "small"
        muted: true
    }

    Rectangle {
        anchors.fill: parent
        anchors.margins: -Metrics.spaceXs
        radius: Metrics.radiusCard
        color: card.selected ? Colors.accentSoft : "transparent"
        border.width: card.selected ? Metrics.focusBorderWidth : Metrics.borderWidth
        border.color: card.selected ? Colors.accentLine : dragArea.containsMouse ? Colors.borderStrong : Colors.border
        z: -1
    }

    MouseArea {
        id: dragArea
        anchors.fill: parent
        anchors.margins: -Metrics.spaceXs
        hoverEnabled: true
        cursorShape: card.dragging ? Qt.ClosedHandCursor : Qt.OpenHandCursor
        preventStealing: true

        onPressed: event => {
            card.editor.takeFocus()
            card.editor.select(card.placementId, event.modifiers & Qt.ShiftModifier)
            const point = mapToItem(card.editor, event.x, event.y)
            card.press(Qt.point(point.x, point.y))
        }
        onPositionChanged: event => {
            if (!pressed) return
            const point = mapToItem(card.editor, event.x, event.y)
            card.dragTo(Qt.point(point.x, point.y), (event.modifiers & Qt.AltModifier) !== 0)
        }
        onReleased: card.drop()
        // A press the window loses (testing.md pitfall 114) drops nothing.
        onCanceled: card.cancelDrag()
    }

    Rectangle {
        id: handle
        visible: card.selected
        width: Metrics.resizeHandle
        height: Metrics.resizeHandle
        radius: width / 2
        x: card.width - width / 2
        y: card.height - height / 2
        color: Colors.accent
        border.width: Metrics.focusBorderWidth
        border.color: Colors.knob

        MouseArea {
            anchors.fill: parent
            anchors.margins: -Metrics.spaceXs
            cursorShape: Qt.SizeFDiagCursor
            preventStealing: true
            onPressed: event => card.beginResize(mapToItem(card.editor, event.x, event.y).x)
            onPositionChanged: event => {
                if (pressed) card.resizeTo(mapToItem(card.editor, event.x, event.y).x)
            }
            onReleased: card.endResize()
            onCanceled: card.cancelResize()
        }
    }
}
