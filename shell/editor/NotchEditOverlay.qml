import QtQuick
import qs.theme
import qs.services
import qs.shell.components
import "../../services/arrange/ArrangeLogic.js" as Arrange
import "../../services/LayoutLogic.js" as Logic

// Notch arranging inside the layout editor (desktop mode "Notch").
//
// It arranges the real notch in place, on the bar's pattern and for the same
// reason: the notch is a layer surface of its own and this editor covers it,
// so the editor cannot host the notch's items. The notch reports where each
// of them sits (LayoutService.surfaceRects, keys `notch:<id>` and
// `notchzone:<zone>`) and this overlay puts the frames, the drag surfaces and
// the drop marker exactly there.
//
// While it is open the notch holds itself expanded and draws both of its
// lists at once - the strip above its header, the overview below it - so
// either can be dragged and an item can cross from one into the other.
Item {
    id: overlay
    // EditLayer's root. A press here hands it the keys with takeFocus(), not
    // forceActiveFocus(): that would give them back to whichever option Tab
    // reached last, and Left or Right would go on flipping that switch while
    // the hand is on the notch.
    required property var editor
    readonly property string screenName: editor.screenName

    // Resizing: the item whose corner is being pulled, and the size it asks
    // for in grid steps. Written once, on release, like a move.
    property string sizeId: ""
    property int sizeW: 1
    property int sizeH: 1

    // Drag state; `dropIndex` counts the target zone without the dragged item.
    property string dragId: ""
    property string dropZone: ""
    property int dropIndex: -1
    // The overview's cell the drop would rest in (overlay coordinates), or
    // null: the strip marks the gap a drop opens, the grid the cell it lands
    // in (ArrangeLogic.gridDropTarget). A hairline after the list neighbour
    // was drawn past the grid's edge wherever the packer floats a block up.
    property var dropCell: null
    property real ghostX: 0
    property real ghostY: 0
    // Where inside the item it was taken hold of, so the ghost hangs there
    // instead of jumping to its own centre. That jump is what made the bar's
    // drag feel detached from the hand.
    property real grabX: 0
    property real grabY: 0

    readonly property string zone: LayoutService.notchEditZone
    // One shape at a time. The switch above the options says which, and only
    // that one's items are framed, dragged and sized - the strip is not on
    // screen while the overview is being arranged, and the other way round.
    readonly property var zoneKeys: [zone]
    readonly property var items: zone === "collapsed" ? NotchService.collapsedItems : NotchService.expandedItems

    // ---- the notch's own size ---------------------------------------------
    // The shape being worked on, as the editor sees it: the strip is only as
    // tall as the notch, so it is dragged sideways and its handle sits on the
    // right edge; the overview is dragged from its corner, in both directions.
    // The notch is centred, so a width follows the pointer at twice the speed
    // it moves - both edges travel.
    property bool shaping: false
    property real shapeWidth: 0
    property real shapeHeight: 0

    readonly property var shapeRect: {
        const unused = LayoutService.surfaceRects
        const notch = LayoutService.notchRect(screenName)
        const state = NotchService.states[screenName] || null
        if (!notch) return null
        if (overlay.zone === "collapsed")
            return { x: notch.x, y: notch.y, width: notch.width, height: notch.height }
        const width = state && state.expanded ? state.width : notch.width
        const height = state && state.expanded ? state.height : notch.height
        return { x: Math.round(notch.x + notch.width / 2 - width / 2), y: notch.y,
                 width: width, height: height }
    }

    function beginShape() {
        if (!shapeRect) return
        overlay.shaping = true
        overlay.shapeWidth = shapeRect.width
        overlay.shapeHeight = shapeRect.height
        LayoutService.arrangeDragging = "notch"
    }

    function updateShape(x, y) {
        if (!shapeRect) return
        const centre = shapeRect.x + shapeRect.width / 2
        overlay.shapeWidth = Math.max(Metrics.notchMinWidth, Math.round((x - centre) * 2))
        if (overlay.zone === "expanded")
            overlay.shapeHeight = Math.max(NotchService.bodyHeight, Math.round(y - shapeRect.y))
    }

    function endShape() {
        if (overlay.shaping) LayoutService.notchResize(overlay.shapeWidth, overlay.shapeHeight)
        cancelShape()
    }

    function cancelShape() {
        overlay.shaping = false
        LayoutService.arrangeDragging = ""
    }

    function rectOf(key) {
        const unused = LayoutService.surfaceRects
        return LayoutService.surfaceRect(screenName, key)
    }

    // The two drop zones, in the order they sit on screen.
    function zoneRects() {
        const list = []
        for (const key of zoneKeys) {
            const rect = rectOf("notchzone:" + key)
            if (rect) list.push({ key: key, x: rect.x, y: rect.y, width: rect.width, height: rect.height })
        }
        return list
    }

    function itemsIn(which) {
        return which === "collapsed" ? NotchService.collapsedItems : NotchService.expandedItems
    }

    // The cells of one zone, as ArrangeLogic wants them: only the ones that
    // really reported, because an item the notch never drew has no place.
    function cellsIn(zone) {
        const cells = []
        for (const item of itemsIn(zone)) {
            const rect = rectOf("notch:" + item.id)
            if (rect) cells.push({ id: item.id, x: rect.x, y: rect.y, width: rect.width, height: rect.height })
        }
        return cells
    }

    function typeOf(id) {
        for (const item of overlay.items) if (item.id === id) return item.type
        return ""
    }

    function placeOf(id) {
        const index = overlay.items.findIndex(item => item.id === id)
        return index >= 0 ? { zone: overlay.zone, index: index } : null
    }

    function marker() {
        if (!dropZone.length) return null
        const zone = rectOf("notchzone:" + dropZone)
        return Arrange.markerRect(cellsIn(dropZone), dropIndex, dragId, zone, Metrics.spaceSm)
    }

    // ---- the drag ---------------------------------------------------------

    function beginDrag(id, x, y) {
        const rect = rectOf("notch:" + id)
        overlay.dragId = id
        overlay.grabX = rect ? x - rect.x : 0
        overlay.grabY = rect ? y - rect.y : 0
        LayoutService.arrangeDragging = id
        overlay.dropZone = ""
        overlay.dropIndex = -1
        overlay.dropCell = null
    }

    function updateDrag(x, y) {
        overlay.ghostX = x
        overlay.ghostY = y
        overlay.dropZone = Arrange.zoneAt(zoneRects(), x, y, true)
        // The overview is a grid, so the index can be the one the grid will
        // really honour: every candidate order is packed and the nearest one
        // wins. Reading it off the rectangles guessed, and guessed wrong
        // wherever the packer had floated a block up into a hole. The strip is
        // a row - there are no holes in it - and it keeps the cheap answer.
        const zone = rectOf("notchzone:expanded")
        if (overlay.dropZone === "expanded" && zone) {
            const target = Arrange.gridDropTarget(
                NotchService.expandedItems.map(item => ({ id: item.id, w: item.w, h: item.h })),
                overlay.dragId,
                { x: x - zone.x, y: y - zone.y, grabX: overlay.grabX, grabY: overlay.grabY },
                { columns: NotchService.columns, width: zone.width,
                  gap: Metrics.notchColumnGap, unit: Metrics.notchGridUnit })
            overlay.dropIndex = target.index
            overlay.dropCell = target.cell ? { x: zone.x + target.cell.x, y: zone.y + target.cell.y,
                                               width: target.cell.width, height: target.cell.height } : null
        } else {
            overlay.dropIndex = Arrange.insertIndexAt(cellsIn(overlay.dropZone), x, y, overlay.dragId)
            overlay.dropCell = null
        }
    }

    // One write, one undo step: notchMoveTo already wraps beginChange, the
    // mutation and the save. A drop back onto the item's own gap writes
    // nothing at all.
    function endDrag() {
        if (dragId.length && dropZone.length
                && Arrange.changes(placeOf(dragId), dropZone, dropIndex))
            LayoutService.notchMoveTo(dragId, dropZone, dropIndex)
        cancelDrag()
    }

    // ---- pulling a corner -------------------------------------------------
    // Only the overview is a grid; the strip is a row and its items are as
    // wide as what they draw.
    function resizable(id) {
        return NotchService.expandedItems.some(item => item.id === id)
    }

    function sizeOf(id) {
        const found = NotchService.expandedItems.find(item => item.id === id)
        return found ? { w: found.w, h: found.h } : { w: 1, h: 1 }
    }

    // The floor the write applies (LayoutLogic.setNotchItemSize clamps to
    // it), so the preview cannot show a cell the release then undoes.
    function leastOf(id) {
        const found = NotchService.expandedItems.find(item => item.id === id)
        return found ? Logic.notchMinSize(found.type) : { w: 1, h: 1 }
    }

    function beginSize(id) {
        const size = sizeOf(id)
        overlay.sizeId = id
        overlay.sizeW = size.w
        overlay.sizeH = size.h
        LayoutService.arrangeDragging = id
    }

    function updateSize(x, y) {
        const zone = rectOf("notchzone:expanded")
        const rect = rectOf("notch:" + overlay.sizeId)
        if (!zone || !rect) return
        // Measured inside the zone, not on the screen: the clamp asks which
        // column the block starts in, and a screen x is not that. The row
        // ceiling is the one the layout file is sanitized against and the
        // floor is the item's own minimum, so nothing is previewed that the
        // write would take back.
        const wanted = Arrange.sizeAt(x - zone.x, y - zone.y,
                                      { x: rect.x - zone.x, y: rect.y - zone.y },
                                      NotchService.columns, zone.width,
                                      Metrics.notchColumnGap, Metrics.notchGridUnit,
                                      LayoutService.gridMaxRows, leastOf(overlay.sizeId))
        overlay.sizeW = wanted.w
        overlay.sizeH = wanted.h
    }

    function endSize() {
        const before = sizeOf(overlay.sizeId)
        if (overlay.sizeId.length && (before.w !== overlay.sizeW || before.h !== overlay.sizeH))
            LayoutService.notchSetSize(overlay.sizeId, overlay.sizeW, overlay.sizeH)
        cancelSize()
    }

    function cancelSize() {
        overlay.sizeId = ""
        LayoutService.arrangeDragging = ""
    }

    function cancelDrag() {
        overlay.dragId = ""
        overlay.dropZone = ""
        overlay.dropIndex = -1
        overlay.dropCell = null
        LayoutService.arrangeDragging = ""
    }

    function cancelAll() { cancelDrag(); cancelSize(); cancelShape() }

    onVisibleChanged: if (!visible) cancelAll()
    Component.onDestruction: cancelAll()

    // ---- what it draws ----------------------------------------------------

    // The two drop zones, only while something is being dragged: a frame
    // around the notch at rest would compete with the items' own frames.
    Repeater {
        model: overlay.dragId.length ? overlay.zoneKeys : []
        Rectangle {
            required property var modelData
            readonly property var rect: overlay.rectOf("notchzone:" + modelData)
            readonly property bool target: overlay.dropZone === modelData
            visible: rect !== null
            x: rect ? rect.x - Metrics.spaceSm : 0
            y: rect ? rect.y - Metrics.spaceSm : 0
            width: rect ? rect.width + Metrics.spaceSm * 2 : 0
            height: rect ? rect.height + Metrics.spaceSm * 2 : 0
            radius: Metrics.radiusCard
            color: target ? Colors.accentSoft : Colors.scrim
            border.width: target ? Metrics.focusBorderWidth : Metrics.borderWidth
            border.color: target ? Colors.accent : Colors.border

            // Below the notch, over the wallpaper: on a plate, as the hint
            // lines are.
            EditorCaption {
                anchors.horizontalCenter: parent.horizontalCenter
                anchors.top: parent.bottom
                anchors.topMargin: Metrics.spaceXs
                text: modelData === "collapsed" ? "Always visible" : "On hover"
                role: "label"
            }
        }
    }

    // One frame and one drag surface per item, on top of the real one.
    Repeater {
        model: overlay.items
        Item {
            id: frame
            required property var modelData
            readonly property var rect: overlay.rectOf("notch:" + modelData.id)
            readonly property bool dragging: overlay.dragId === modelData.id
            // While its corner is being pulled the frame shows the size that
            // would be written, so the grid step is visible before the release.
            readonly property bool sizing: overlay.sizeId === modelData.id
            readonly property var preview: {
                const zone = overlay.rectOf("notchzone:expanded")
                if (!frame.sizing || !zone || !frame.rect) return null
                const columns = Math.max(1, NotchService.columns)
                const gap = Metrics.notchColumnGap
                const column = (zone.width - gap * (columns - 1)) / columns
                return { width: column * overlay.sizeW + gap * (overlay.sizeW - 1),
                         height: Metrics.notchGridUnit * overlay.sizeH + gap * (overlay.sizeH - 1) }
            }
            // Stays visible while it is being dragged: hiding the item takes
            // the mouse grab with it, and the drag ends on its first move.
            visible: rect !== null
            // Exactly on the item, not a hair around it: inflated frames
            // overlapped their neighbours in the gaps, and the one drawn last
            // took the press meant for the one under the pointer.
            x: rect ? rect.x : 0
            y: rect ? rect.y : 0
            width: frame.preview ? frame.preview.width : rect ? rect.width : 0
            height: frame.preview ? frame.preview.height : rect ? rect.height : 0

            // Never filled: the frame lies on top of the real item, so a fill
            // would hide the thing being arranged.
            Rectangle {
                anchors.fill: parent
                visible: !frame.dragging
                radius: Metrics.radiusCard
                color: "transparent"
                // The notch is black in both themes, so the theme's own border
                // disappears on it; the frames borrow the notch's muted ink.
                border.width: frame.sizing ? Metrics.focusBorderWidth : Metrics.borderWidth
                border.color: frame.sizing ? Colors.accent : Colors.notchMutedText
            }

            MouseArea {
                id: drag
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
                    overlay.editor.takeFocus()
                    const point = mapToItem(overlay, mouse.x, mouse.y)
                    pressX = point.x
                    pressY = point.y
                    moved = false
                }
                onPositionChanged: mouse => {
                    if (!pressed) return
                    const point = mapToItem(overlay, mouse.x, mouse.y)
                    if (!moved && Math.abs(point.x - pressX) + Math.abs(point.y - pressY) < Metrics.dragThreshold) return
                    if (!moved) {
                        moved = true
                        overlay.beginDrag(frame.modelData.id, pressX, pressY)
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

    // The controls, on a layer of their own above every frame. The remove
    // button sits half outside its corner, which is inside the gap to the next
    // item - and a frame drawn later would otherwise take the press meant for
    // it.
    Repeater {
        model: overlay.items
        Item {
            id: chrome
            required property var modelData
            readonly property var rect: overlay.rectOf("notch:" + modelData.id)
            readonly property bool sizing: overlay.sizeId === modelData.id
            readonly property string label: NotchService.entry(modelData.type).label
            // The buttons are the arranged panels' (QuickSlot, DashboardSlot):
            // 30 px where there is room, shrinking with a short cell, and down
            // to the 16 px the discs were, never so wide that the two on top
            // of one item meet - the remove button takes half its width from
            // the item, the move button all of it.
            readonly property real button: Math.max(Metrics.iconSm, Math.min(Metrics.controlHeightSm,
                height - Metrics.spaceXxs * 2, (width - Metrics.spaceXxs) * 2 / 3))
            visible: rect !== null && overlay.dragId.length === 0
            x: rect ? rect.x : 0
            y: rect ? rect.y : 0
            width: rect ? rect.width : 0
            height: rect ? rect.height : 0

            // Takes the item off the notch: the danger button with the remove
            // glyph and a "Remove …" tip, as on every other surface that is
            // arranged this way (it was a 16 px disc with a close cross and no
            // name). Half outside is what keeps it off a strip item barely
            // taller than the button, and it never leaves the screen above the
            // notch. The danger wash is translucent, so it sits on the theme's
            // own background: half of it lies outside the black notch, and
            // over a light wallpaper a wash alone was gone. The backing takes
            // the button's shape (the roundness setting) and dips with it, or
            // a press left a ring of it behind.
            Item {
                id: drop
                x: -width / 2
                y: Math.max(-height / 2, chrome.rect ? -chrome.rect.y : 0)
                visible: overlay.sizeId.length === 0
                width: chrome.button
                height: width

                Rectangle {
                    anchors.fill: parent
                    radius: dropButton.radius
                    scale: dropButton.scale
                    // The button's ink follows the panel colour, so its
                    // backing does too (Colors.background follows the theme:
                    // a black panel in the light theme put light glyphs on
                    // a light disc).
                    color: Colors.solidSurface
                }
                ShellButton {
                    id: dropButton
                    anchors.fill: parent
                    icon: Icons.remove
                    iconSize: Math.round(chrome.button / 2)
                    variant: "danger"
                    compact: true
                    toolTip: "Remove " + chrome.label
                    onClicked: LayoutService.notchRemove(chrome.modelData.id)
                }
            }

            // Sends the item to the other row. Dragging it there is not on
            // offer any more - only one shape is on screen at a time - so the
            // move is a click, and it keeps the item's size with it. A button
            // like the remove one, on the same solid backing; the arrow says
            // which way and the tip says where.
            Item {
                id: hop
                // Inside the tile, not half outside it like the remove button:
                // at the top right it would sit on the neighbour's, and two
                // controls in one place is one too many.
                x: parent.width - width - Metrics.spaceXxs
                y: Metrics.spaceXxs
                // Not for a block the strip cannot draw (media, events,
                // status): sent there, it was an empty spot that could not
                // come back into the overview (NotchService.stripTakes).
                visible: overlay.sizeId.length === 0
                    && (overlay.zone === "collapsed" || NotchService.stripTakes(chrome.modelData.type))
                width: chrome.button
                height: width

                Rectangle {
                    anchors.fill: parent
                    radius: hopButton.radius
                    scale: hopButton.scale
                    color: Colors.solidSurface
                }
                ShellButton {
                    id: hopButton
                    anchors.fill: parent
                    icon: overlay.zone === "collapsed" ? Icons.collapse : Icons.raise
                    iconSize: Math.round(chrome.button / 2)
                    compact: true
                    toolTip: overlay.zone === "collapsed" ? "Move " + chrome.label + " to the overview"
                        : "Move " + chrome.label + " to the strip"
                    onClicked: LayoutService.notchMoveTo(chrome.modelData.id,
                        overlay.zone === "collapsed" ? "expanded" : "collapsed", 0)
                }
            }

            // Pull this and the item takes more columns and rows. The frame
            // follows while you pull and the size is written once, on release
            // - one undo step, like a move. Accent and opaque, as ArrangeItem's
            // corner is: the translucent fill it had showed whatever was under
            // it, and half of it lies outside the notch.
            Rectangle {
                id: handle
                visible: overlay.resizable(chrome.modelData.id)
                x: parent.width - width / 2
                y: parent.height - height / 2
                width: Metrics.iconSm
                height: width
                radius: width / 2
                color: chrome.sizing || corner.containsMouse ? Colors.accentHover : Colors.accent
                border.width: Metrics.borderWidth
                border.color: Colors.accentLine

                ToolTipHost {
                    id: cornerTip
                    anchorItem: handle
                    text: "Drag to resize " + chrome.label
                }
                MouseArea {
                    id: corner
                    anchors.fill: parent
                    anchors.margins: -Metrics.spaceXs
                    acceptedButtons: Qt.LeftButton
                    hoverEnabled: true
                    preventStealing: true
                    cursorShape: Qt.SizeFDiagCursor
                    property bool pulling: false
                    onEntered: cornerTip.arm()
                    onExited: cornerTip.release()
                    onPressed: {
                        cornerTip.release()
                        overlay.editor.takeFocus()
                        overlay.beginSize(chrome.modelData.id)
                        pulling = true
                    }
                    onPositionChanged: mouse => {
                        if (!pulling) return
                        const point = mapToItem(overlay, mouse.x, mouse.y)
                        overlay.updateSize(point.x, point.y)
                    }
                    onReleased: {
                        if (pulling) overlay.endSize()
                        pulling = false
                    }
                    onCanceled: {
                        if (pulling) overlay.cancelSize()
                        pulling = false
                    }
                }
            }
        }
    }

    // The notch's own outline while it is being sized, and the handle that
    // does it. The strip only moves sideways - its height is the notch's own -
    // so it gets an edge; the overview gets a corner.
    Rectangle {
        id: shape
        readonly property var rect: overlay.shapeRect
        readonly property real drawnWidth: overlay.shaping ? overlay.shapeWidth : rect ? rect.width : 0
        readonly property real drawnHeight: overlay.shaping ? overlay.shapeHeight : rect ? rect.height : 0
        visible: rect !== null && overlay.dragId.length === 0 && overlay.sizeId.length === 0
        x: rect ? rect.x + rect.width / 2 - drawnWidth / 2 : 0
        y: rect ? rect.y : 0
        width: drawnWidth
        height: drawnHeight
        color: "transparent"
        radius: Metrics.notchExpandedRadius
        border.width: overlay.shaping ? Metrics.focusBorderWidth : Metrics.borderWidth
        border.color: overlay.shaping ? Colors.accent : Colors.notchMutedText

        // Opaque accent like the items' corners: half of it lies outside the
        // notch, over whatever the wallpaper is.
        Rectangle {
            id: shapeHandle
            x: parent.width - width / 2
            y: overlay.zone === "collapsed" ? (parent.height - height) / 2 : parent.height - height / 2
            width: Metrics.iconSm
            height: width
            radius: width / 2
            color: overlay.shaping || shapeMouse.containsMouse ? Colors.accentHover : Colors.accent
            border.width: Metrics.borderWidth
            border.color: Colors.accentLine

            ToolTipHost {
                id: shapeTip
                anchorItem: shapeHandle
                text: overlay.zone === "collapsed" ? "Drag to set the strip's width" : "Drag to size the overview"
            }
            MouseArea {
                id: shapeMouse
                anchors.fill: parent
                anchors.margins: -Metrics.spaceXs
                acceptedButtons: Qt.LeftButton
                hoverEnabled: true
                preventStealing: true
                cursorShape: overlay.zone === "collapsed" ? Qt.SizeHorCursor : Qt.SizeFDiagCursor
                onEntered: shapeTip.arm()
                onExited: shapeTip.release()
                onPressed: {
                    shapeTip.release()
                    overlay.editor.takeFocus()
                    overlay.beginShape()
                }
                onPositionChanged: mouse => {
                    if (!overlay.shaping) return
                    const point = mapToItem(overlay, mouse.x, mouse.y)
                    overlay.updateShape(point.x, point.y)
                }
                onReleased: overlay.endShape()
                onCanceled: overlay.cancelShape()
            }
        }
    }

    // Insertion marker at the gap the dragged item would take.
    Rectangle {
        readonly property var line: overlay.marker()
        visible: overlay.dragId.length > 0 && overlay.dropZone.length > 0 && line !== null && overlay.dropCell === null
        width: Metrics.focusBorderWidth * 2
        height: line ? line.height : 0
        radius: width / 2
        x: line ? line.x - width / 2 : 0
        y: line ? line.y : 0
        color: Colors.accent
    }

    // On the overview the drop rests in a cell of the grid: that cell is
    // outlined, where the item will land.
    Rectangle {
        readonly property var cell: overlay.dropCell
        visible: overlay.dragId.length > 0 && overlay.dropZone === "expanded" && cell !== null
        x: cell ? cell.x : 0
        y: cell ? cell.y : 0
        width: cell ? cell.width : 0
        height: cell ? cell.height : 0
        radius: Metrics.radiusCard
        color: "transparent"
        border.width: Metrics.focusBorderWidth
        border.color: Colors.accent
    }

    // The item under the pointer while it is being dragged. It hangs where it
    // was taken hold of - not centred on the pointer, which is what made the
    // bar's own drag feel detached - and it is never animated: this is direct
    // manipulation and it has to work with animations turned off.
    Rectangle {
        id: ghost
        readonly property var rect: overlay.dragId.length ? overlay.rectOf("notch:" + overlay.dragId) : null
        readonly property var entry: NotchService.entry(overlay.typeOf(overlay.dragId))
        visible: overlay.dragId.length > 0 && rect !== null
        x: overlay.ghostX - overlay.grabX
        y: overlay.ghostY - overlay.grabY
        width: rect ? rect.width : 0
        height: rect ? rect.height : 0
        radius: Metrics.radiusCard
        color: Colors.notch
        border.width: Metrics.focusBorderWidth
        border.color: Colors.accent
        scale: Effects.dragScale

        Row {
            anchors.centerIn: parent
            spacing: Metrics.spaceXs
            ShellIcon {
                anchors.verticalCenter: parent.verticalCenter
                glyph: ghost.entry.icon
                size: Metrics.iconSm
                color: Colors.notchText
            }
            ShellText {
                anchors.verticalCenter: parent.verticalCenter
                text: ghost.entry.label
                role: "small"
                color: Colors.notchText
            }
        }
    }
}
