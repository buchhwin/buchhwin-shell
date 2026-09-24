import QtQuick
import qs.theme
import qs.services
import "../../services/arrange/ArrangeLogic.js" as Arrange

// A surface whose items the user rearranges by dragging them. It places its
// items itself, from ArrangeLogic, instead of leaving that to a layout: a
// QtQuick layout owns its children's geometry outright and cannot animate
// them aside, and making room is the whole point here.
//
// While a drag runs the items take their places from the *preview* order, so
// the gap opens under the pointer and the model is written once, on release.
//
// The item being dragged stays where it is in the scene - hiding it would take
// the mouse grab with it and end the drag on its first move. It is drawn on
// `dragLayer` instead, as a texture of itself, and its own place goes empty.
Item {
    id: area

    // What to arrange: [{ id, span }] in the committed order. Heights come
    // from the items themselves, so the caller does not have to know them.
    property var model: []
    property int columns: 1
    property real gap: Metrics.panelGap
    // A surface the user sizes: when `unit` is greater than zero every model
    // entry brings its own `w` and `h` in grid steps and the cells take those,
    // instead of each item reporting how tall it would like to be. One step is
    // a column and a row, never a pixel, so the same layout holds on any
    // screen and at any scale.
    readonly property bool sized: unit > 0
    property real unit: 0
    property bool editing: false
    // Whether the items glide to their places. A surface whose own size is
    // being dragged turns this off: every cell changes in every frame, and a
    // glide behind the hand reads as lag rather than as motion.
    property bool animated: true

    // **And they do not glide for the first moment a surface is on screen.**
    // An item whose content is not ready yet reports no height and so holds no
    // place, and the ones after it pack into the slot it has not claimed; when
    // it arrives the whole grid corrects itself. That correction is right - the
    // resting order is the stored order either way, and nothing is written -
    // but gliding through it is the "opening the quick panel after a while
    // shuffles every widget once, and opening it straight away does not" that
    // was reported. On a second open the tiles are already there, which is why
    // it only happens cold.
    //
    // So the correction is made unseen rather than delayed: at this point the
    // panel is still animating in, and a tile that is simply *drawn* in its
    // right place costs nothing.
    readonly property bool gliding: animated && warm
    property bool warm: false
    onVisibleChanged: {
        area.warm = false
        if (visible) warmTimer.restart()
    }
    Component.onCompleted: if (visible) warmTimer.restart()
    Timer {
        id: warmTimer
        interval: Animations.popupOpen
        onTriggered: area.warm = true
    }
    // The ceiling a cell may be dragged to, in rows - the one the layout file
    // is sanitized against, so nothing is previewed that the write undoes.
    property int maxRows: 0
    // While a corner is being pulled, the surface lays itself out with that
    // cell at the wanted size. The whole grid reflows under the hand, which is
    // what will really happen on release - previewing only the cell itself let
    // it grow past the panel edge and then teleport to another row.
    property string sizingId: ""
    property int sizingW: 1
    property int sizingH: 1
    readonly property bool sizing: sizingId.length > 0
    // Where the dragged item is drawn. A panel hands over its `overlay`; a
    // full-screen editor hands over itself. Without one there is no drag.
    property Item dragLayer: null

    signal committed(string id, int index)

    // The flag is global so Escape and the panel can see it; `ownsDrag` keeps
    // one area from reacting to another area's drag.
    readonly property string dragId: LayoutService.arrangeDragging
    property bool ownsDrag: false
    readonly property bool dragging: ownsDrag && dragId.length > 0
    property int dropIndex: -1

    // Natural heights, reported by the items. Replaced rather than mutated: a
    // `var` map changed in place emits no change signal, so nothing that reads
    // it would ever re-evaluate.
    property var heights: ({})
    function reportHeight(id, value) {
        const rounded = Math.round(value)
        if (area.heights[id] === rounded) return
        const next = Object.assign({}, area.heights)
        next[id] = rounded
        area.heights = next
    }
    function forgetHeight(id) {
        if (!(id in area.heights)) return
        const next = Object.assign({}, area.heights)
        delete next[id]
        area.heights = next
    }

    // The order the items sit in right now: the committed one, or the one the
    // drag is previewing.
    readonly property var order: model.map(entry => entry.id)
    readonly property var shownOrder: dragging && dropIndex >= 0
        ? Arrange.previewOrder(order, dragId, dropIndex) : order

    // An item that has nothing to show reports no height and is left out
    // entirely, the way a layout skips an invisible child - otherwise it would
    // hold an empty cell open. While the surface is being arranged every item
    // is shown, so the filter never runs during a drag and the indices the
    // drop maths produces always count the whole list.
    readonly property var placement: {
        const byId = {}
        for (const entry of model) byId[entry.id] = entry
        if (sized) {
            // A cell's size is its own, but an item with nothing to show still
            // holds no place: it reports a height of zero and is left out, the
            // way a layout skips an invisible child. While the surface is
            // being arranged every item is shown, so the filter never runs
            // during a drag and the indices the drop maths produces always
            // count the whole list.
            const sizedCells = shownOrder.filter(id => byId[id] && area.heights[id] !== 0)
                .map(id => id === sizingId ? { id: id, w: sizingW, h: sizingH }
                                           : { id: id, w: byId[id].w, h: byId[id].h })
            return Arrange.gridLayout(sizedCells, columns, width, gap, unit)
        }
        const cells = []
        for (const id of shownOrder) {
            const height = area.heights[id] || 0
            if (height <= 0) continue
            cells.push({ id: id, span: byId[id] ? byId[id].span : 1, contentHeight: height })
        }
        return Arrange.layout(cells, columns, width, gap)
    }

    // The size a corner pulled to (x, y) asks for. `origin` is the cell as it
    // was when the handle was pressed - measuring against the live cell would
    // feed the reflow back into the measurement. Only means anything on a
    // sized surface.
    function sizeAt(origin, x, y) {
        if (!sized || !origin) return { w: 1, h: 1 }
        return Arrange.sizeAt(x, y, origin, columns, width, gap, unit, maxRows, leastOf(origin.id))
    }

    // The smallest cell one item may be pulled to, as its model entry declares
    // it. A surface whose catalogue names no minimum simply leaves the two
    // keys off and every cell goes down to a single step, as before.
    function leastOf(id) {
        for (const entry of (model || []))
            if (entry.id === id) return { w: entry.minW || 1, h: entry.minH || 1 }
        return { w: 1, h: 1 }
    }

    // The resting rectangle of one item, or null while it is not placed yet.
    // It carries the size the packer granted, not the one the model asked for:
    // re-attaching the stored w and h let a handle preview a cell reaching past
    // the panel edge that the packer had already refused.
    function cellOf(id) {
        for (const cell of placement.cells) if (cell.id === id) return cell
        return null
    }

    implicitHeight: placement.height

    // The rows the committed cells pack into, in steps. Read this to size a
    // step from the layout rather than the other way round: it depends on the
    // model and on which items hold a place, and on nothing that depends on
    // `unit` - not even `sized`, which is `unit > 0` and made this a binding
    // loop in the log although its value never changes. A surface whose unit
    // is a share of its height over *this* is safe; the launcher is that
    // surface, see its `gridUnit`. On a surface that is not sized the model
    // carries no `w`/`h` and every cell counts as one step, and nobody reads it.
    readonly property int rowsUsed: {
        const cells = []
        for (const entry of (model || []))
            if (area.heights[entry.id] !== 0) cells.push({ id: entry.id, w: entry.w || 1, h: entry.h || 1 })
        return Arrange.gridRows(cells, columns)
    }

    // ---- the drag ---------------------------------------------------------

    function begin(id, item, grabX, grabY) {
        if (!dragLayer || !editing) return false
        area.ownsDrag = true
        area.dropIndex = order.indexOf(id)
        LayoutService.arrangeDragging = id
        ghost.grabX = grabX
        ghost.grabY = grabY
        ghost.sourceItem = item
        return true
    }

    // The list this surface sits in, if it sits in one. Found by walking up
    // rather than handed in: the area is loaded inside the list rather than
    // declared beside it, so nothing on the way down knows about it. A
    // Flickable is the only thing with a maximumFlickVelocity.
    function scroller() {
        let node = area.parent
        while (node) {
            if (node.maximumFlickVelocity !== undefined) return node
            node = node.parent
        }
        return null
    }

    // How fast the list under the drag should be moving, in pixels per tick,
    // from how far into the edge band the pointer has come. Arranging shows
    // every item - about twenty rows on the control center - and the drag's
    // preventStealing keeps the list from scrolling under the pointer, so
    // without this half the surface cannot be reached at all.
    property real edgeSpeed: 0
    function edgeSpeedAt(y) {
        const view = scroller()
        if (!view || view.contentHeight <= view.height) return 0
        const point = area.mapToItem(view, 0, y)
        const band = Metrics.scrollEdge
        if (point.y < band) return -(band - point.y) / band * Metrics.scrollStep
        if (point.y > view.height - band) return (point.y - (view.height - band)) / band * Metrics.scrollStep
        return 0
    }

    Timer {
        running: area.dragging && area.edgeSpeed !== 0
        repeat: true
        interval: Animations.scrollTick
        onTriggered: {
            const view = area.scroller()
            if (!view) return
            const most = Math.max(0, view.contentHeight - view.height)
            view.contentY = Math.max(0, Math.min(most, view.contentY + area.edgeSpeed))
        }
    }

    // `point` is in this area's coordinates.
    function update(x, y) {
        if (!dragging) return
        area.edgeSpeed = edgeSpeedAt(y)
        // Against the committed places, not the previewed ones: asking where a
        // moving target is would make the index chase itself.
        if (sized) {
            // Every candidate index is packed and the nearest one wins, so the
            // index is the one the grid will really honour. Reading it off the
            // rectangles guessed, and the guess was wrong wherever the packer
            // had floated a cell up into a hole.
            area.dropIndex = Arrange.gridDropIndex(
                model.filter(entry => area.heights[entry.id] !== 0)
                     .map(entry => ({ id: entry.id, w: entry.w, h: entry.h })),
                dragId, { x: x, y: y, grabX: ghost.grabX, grabY: ghost.grabY },
                { columns: columns, width: width, gap: gap, unit: unit })
        } else {
            const resting = []
            for (const entry of model) {
                const height = area.heights[entry.id] || 0
                if (height <= 0) continue
                resting.push({ id: entry.id, span: entry.span, contentHeight: height })
            }
            area.dropIndex = Arrange.insertIndexAt(Arrange.layout(resting, columns, width, gap).cells,
                                                   x, y, dragId)
        }
        // The ghost lives on another item, so the pointer has to be carried
        // into its coordinates rather than used as it stands.
        const onLayer = area.mapToItem(area.dragLayer, x, y)
        ghost.x = onLayer.x - ghost.grabX
        ghost.y = onLayer.y - ghost.grabY
    }

    function finish() {
        if (!dragging) { cancel(); return }
        const id = dragId
        const index = dropIndex
        const from = order.indexOf(id)
        cancel()
        // Dropping an item back on its own gap is not a move: no write, no
        // undo step, no animation.
        if (index >= 0 && index !== from) area.committed(id, index)
    }

    function cancel() {
        if (ownsDrag) LayoutService.arrangeDragging = ""
        area.ownsDrag = false
        area.dropIndex = -1
        area.edgeSpeed = 0
        ghost.sourceItem = null
    }

    // Leaving the arrange mode ends both gestures. The size preview is cleared
    // by hand as well as by the handle's own release: a dropped pointer grab
    // would otherwise leave the grid laid out for a drag that is over.
    function endSizing() {
        area.sizingId = ""
    }

    onEditingChanged: if (!editing) { cancel(); endSizing() }
    Component.onDestruction: cancel()

    // A texture of the item, not a second copy of it: an interactive tile
    // instantiated twice would subscribe to its services twice. `hideSource`
    // leaves the item visible to the input chain, so the grab survives.
    ShaderEffectSource {
        id: ghost
        property real grabX: 0
        property real grabY: 0
        parent: area.dragLayer
        visible: area.dragging && sourceItem !== null
        sourceItem: null
        hideSource: true
        live: true
        z: 1
        width: sourceItem ? sourceItem.width : 0
        height: sourceItem ? sourceItem.height : 0
        transformOrigin: Item.Center
        scale: Effects.dragScale
    }
}
