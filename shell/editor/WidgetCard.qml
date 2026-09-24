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
    property bool changeStarted: false

    readonly property var previewItem: entry ? (resizing ? Object.assign({}, entry, { scale: previewScale }) : entry) : null
    readonly property var restingPosition: entry ? Logic.pixelPosition(entry, width, height, editor.width, editor.height) : ({ x: 0, y: 0 })

    width: frame.hasContent ? frame.implicitWidth : placeholder.implicitWidth + Metrics.spaceLg * 2
    height: frame.hasContent ? frame.implicitHeight : placeholder.implicitHeight + Metrics.spaceMd * 2
    x: dragging ? x : restingPosition.x
    y: dragging ? y : restingPosition.y
    visible: entry !== null || opacity > 0
    // A removed widget fades rather than blinking out. Its position is *not*
    // animated: a desktop widget has no neighbours to displace, and x feeds
    // reportRect, so an animated x would keep reporting and never settle.
    opacity: entry !== null ? 1 : 0
    Behavior on opacity { NumberAnimation { duration: Animations.popupClose; easing.type: Animations.easingExit } }

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
    Component.onDestruction: editor.forgetRect(placementId)

    WidgetFrame {
        id: frame
        item: card.previewItem
        editing: true
        opacity: card.entry && card.entry.visible ? 1 : Effects.disabledOpacity
    }

    // Widgets without current content (e.g. no media player) stay editable.
    ShellText {
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
        color: card.selected ? Colors.selection : "transparent"
        border.width: card.selected ? Metrics.focusBorderWidth : Metrics.borderWidth
        border.color: card.selected ? Colors.accent : dragArea.containsMouse ? Colors.borderStrong : Colors.border
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
            card.editor.forceActiveFocus()
            card.editor.select(card.placementId, event.modifiers & Qt.ShiftModifier)
            const global = mapToItem(card.editor, event.x, event.y)
            card.pressPoint = Qt.point(global.x, global.y)
            card.startPos = Qt.point(card.x, card.y)
            card.changeStarted = false
        }
        onPositionChanged: event => {
            if (!pressed) return
            const global = mapToItem(card.editor, event.x, event.y)
            const dx = global.x - card.pressPoint.x
            const dy = global.y - card.pressPoint.y
            if (!card.dragging && Math.abs(dx) + Math.abs(dy) < Metrics.dragThreshold) return
            if (!card.changeStarted) {
                LayoutService.beginChange()
                card.changeStarted = true
                card.dragging = true
            }
            const result = Snap.snap({ x: card.startPos.x + dx, y: card.startPos.y + dy, width: card.width, height: card.height },
                card.editor.otherRects(card.placementId),
                { screenWidth: card.editor.width, screenHeight: card.editor.height, threshold: Metrics.snapThreshold,
                  grid: card.editor.gridEnabled, gridSize: Metrics.gridSize, margin: Metrics.screenMargin,
                  disabled: (event.modifiers & Qt.AltModifier) !== 0 })
            card.x = result.x
            card.y = result.y
            card.editor.guides = result.guides
        }
        onReleased: {
            if (card.dragging) {
                const position = Logic.relativePosition(card.x, card.y, card.width, card.height, card.editor.width, card.editor.height)
                LayoutService.updateItem(card.placementId, position)
                LayoutService.save()
            }
            card.dragging = false
            card.editor.guides = []
        }
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
            property real pressX: 0
            onPressed: event => {
                pressX = mapToItem(card.editor, event.x, event.y).x
                card.startScale = card.entry.scale
                card.previewScale = card.entry.scale
                LayoutService.beginChange()
                card.resizing = true
            }
            onPositionChanged: event => {
                if (!pressed) return
                const dx = mapToItem(card.editor, event.x, event.y).x - pressX
                const base = Math.max(1, card.width / card.previewScale)
                const direction = card.entry.anchorX === "right" ? -1 : 1
                card.previewScale = Math.max(Metrics.widgetScaleMin, Math.min(Metrics.widgetScaleMax,
                    card.startScale + direction * dx / base))
            }
            onReleased: {
                LayoutService.updateItem(card.placementId, { scale: Math.round(card.previewScale * 100) / 100 })
                LayoutService.save()
                card.resizing = false
            }
        }
    }
}
