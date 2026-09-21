.pragma library

// Pure geometry for every surface the user arranges by dragging: the control
// center's tiles, the bar's pills, and (later) the notch and the dashboard.
// It replaced shell/editor/BarDrop.js, which did the same in one dimension for
// the bar alone; the bar runs on this now and that file is gone. Its own tests
// came with it, so the one-dimensional case cannot quietly stop working.
//
// Two jobs, and they belong together because the second is only honest if it
// agrees with the first:
//
//   layout()         where the cells rest, so a container can place them
//                    itself instead of leaving it to a GridLayout. A layout
//                    that owns its children's geometry cannot animate them
//                    aside, which is the whole point of the exercise.
//   insertIndexAt()  the index a drop would take, from the same rectangles.
//   gridDropIndex()  the same question on a grid the user sizes, answered by
//                    packing each candidate rather than reading rectangles.
//
// Everything is plain data: a cell going in is { id, span, contentHeight },
// a cell coming out is { id, x, y, width, height }. No QML, no units beyond
// the pixels the caller passes in.

// ---- resting places -------------------------------------------------------

function clampSpan(span, columns) {
    const wanted = Math.round(Number(span) || 1)
    return Math.max(1, Math.min(Math.max(1, columns), wanted))
}

// Rows of indices, in order. A cell starts a new row when its span does not
// fit in what is left of the current one.
function rowsOf(cells, columns) {
    const width = Math.max(1, Math.round(columns) || 1)
    const rows = []
    let row = []
    let used = 0
    for (let index = 0; index < (cells || []).length; ++index) {
        const span = clampSpan(cells[index].span, width)
        if (used > 0 && used + span > width) {
            rows.push(row)
            row = []
            used = 0
        }
        row.push(index)
        used += span
    }
    if (row.length) rows.push(row)
    return rows
}

// Where every cell rests, and how tall the whole thing is.
//
// `contentHeight` (in) and `height` (out) are deliberately two different
// fields: binding a container's implicitHeight to its own height is the loop
// this function exists to avoid.
function layout(cells, columns, width, gap) {
    const list = cells || []
    const count = Math.max(1, Math.round(columns) || 1)
    const space = Math.max(0, Number(gap) || 0)
    const total = Math.max(0, Number(width) || 0)
    // Columns share what the gaps leave over.
    const column = count > 0 ? (total - space * (count - 1)) / count : total
    const rows = rowsOf(list, count)
    const placed = []
    let top = 0
    for (const row of rows) {
        let rowHeight = 0
        for (const index of row)
            rowHeight = Math.max(rowHeight, Math.max(0, Number(list[index].contentHeight) || 0))
        let left = 0
        for (const index of row) {
            const span = clampSpan(list[index].span, count)
            const cellWidth = column * span + space * (span - 1)
            placed.push({
                id: list[index].id,
                x: left,
                y: top,
                width: cellWidth,
                height: rowHeight
            })
            left += cellWidth + space
        }
        top += rowHeight + space
    }
    // The last row contributes no gap below it.
    return { cells: placed, height: Math.max(0, top - space) }
}

// ---- a grid the user sizes ------------------------------------------------

// A grid every cell claims a piece of: `w` columns wide and `h` rows tall.
// Cells are placed in order, each in the first free slot found scanning top to
// bottom and left to right - so a cell two rows tall leaves room beside it for
// two one-row cells, one under the other, instead of wasting the second row.
// A shelf packer, which is what this was first, could only ever put one thing
// beside a tall neighbour.
//
// The order of the list is still what decides the layout, so dragging an item
// somewhere else is still the whole of arranging.
function gridLayout(cells, columns, width, gap, unit) {
    const list = cells || []
    const count = Math.max(1, Math.round(columns) || 1)
    const space = Math.max(0, Number(gap) || 0)
    const total = Math.max(0, Number(width) || 0)
    const step = Math.max(1, Number(unit) || 1)
    const column = count > 0 ? (total - space * (count - 1)) / count : total
    // One entry per grid row, each a list of booleans as wide as the grid.
    const taken = []
    const rowAt = index => {
        while (taken.length <= index) taken.push(new Array(count).fill(false))
        return taken[index]
    }
    const fits = (col, row, w, h) => {
        if (col + w > count) return false
        for (let r = row; r < row + h; ++r)
            for (let c = col; c < col + w; ++c)
                if (rowAt(r)[c]) return false
        return true
    }
    const claim = (col, row, w, h) => {
        for (let r = row; r < row + h; ++r)
            for (let c = col; c < col + w; ++c) rowAt(r)[c] = true
    }
    const placed = []
    let rows = 0
    for (const cell of list) {
        const w = clampSpan(cell.w, count)
        const h = Math.max(1, Math.round(Number(cell.h) || 1))
        let row = 0
        let col = 0
        // The scan always terminates: a row of its own always fits.
        for (;; ++row) {
            let found = -1
            for (let c = 0; c + w <= count; ++c) {
                if (fits(c, row, w, h)) { found = c; break }
            }
            if (found >= 0) { col = found; break }
        }
        claim(col, row, w, h)
        rows = Math.max(rows, row + h)
        placed.push({
            id: cell.id,
            // The size as it was granted, not as it was asked for: whoever
            // draws a handle on this cell must not re-attach the stored w and
            // h, or the preview reaches past the edge the packer stopped at.
            w: w,
            h: h,
            x: col * (column + space),
            y: row * (step + space),
            width: column * w + space * (w - 1),
            height: step * h + space * (h - 1)
        })
    }
    return { cells: placed, height: rows > 0 ? rows * step + space * (rows - 1) : 0 }
}

// The size a corner dragged to (x, y) inside the grid asks for, in steps.
// `origin` is the cell's own top left, so the handle measures the cell rather
// than the surface.
//
// Both axes are clamped to what will really be granted, so what the preview
// shows is what the release writes: across, to the columns left from the one
// this cell starts in - the packer refuses a cell that reaches past the right
// edge and drops it to a row of its own - and down, to `maxRows`, the same
// ceiling the layout file is sanitized against. `maxRows` of 0 is no ceiling.
//
// `least` is the floor the same write applies, when the item has one: a tile
// pulled below the size its catalogue calls the smallest useful one has to
// stop under the hand, or the preview shows a cell the release then undoes.
function sizeAt(x, y, origin, columns, width, gap, unit, maxRows, least) {
    const count = Math.max(1, Math.round(columns) || 1)
    const space = Math.max(0, Number(gap) || 0)
    const total = Math.max(0, Number(width) || 0)
    const step = Math.max(1, Number(unit) || 1)
    const column = count > 0 ? (total - space * (count - 1)) / count : total
    const across = Math.max(0, Number(x) - Number(origin.x))
    const down = Math.max(0, Number(y) - Number(origin.y))
    const w = Math.round((across + space) / (column + space))
    const h = Math.round((down + space) / (step + space))
    const from = Math.max(0, Math.min(count - 1, Math.round(Number(origin.x) / (column + space))))
    const rows = Math.max(1, Math.round(Number(maxRows) || 0) || h)
    const floor = least || {}
    const leastW = Math.max(1, Math.round(Number(floor.w)) || 1)
    const leastH = Math.max(1, Math.round(Number(floor.h)) || 1)
    // The floor never wins against the ceiling: a cell whose minimum is wider
    // than the columns left to it is placed at what is there, the way the
    // packer would, rather than previewing a width it cannot have.
    return { w: Math.max(1, Math.min(count - from, Math.max(leastW, w))),
             h: Math.max(1, Math.min(rows, Math.max(leastH, h))) }
}

// ---- the size of the surface itself ---------------------------------------
// The control center and the dashboard are both panels the user drags to a
// size, so the arithmetic lives with the rest of the arranging rather than in
// either one's own catalogue.

function clamp(value, low, high) {
    return Math.max(low, Math.min(high, value))
}

// A panel's own size, as it was dragged.
//
// `bounds` carries what the surface knows and this file cannot: minWidth,
// maxWidth and the default width, a minHeight that keeps the body from
// collapsing, and `room` - what is really left below the panel's top edge.
//
// The height used to be a bare floor with no ceiling and no floor worth the
// name. Dragged past the bottom of the screen it was stored as given: the card
// stopped growing where the room ended, and the grip on its bottom corner
// walked off the display and could not be reached again. Dragged small it went
// to 72, at which the body computed a negative height and clamped to nothing -
// the whole panel, every page of it, became empty and stayed empty across
// restarts. Both ends are real clamps now. A height of 0 still means "follow
// the content", which is what a panel that has never been dragged does.
function panelBox(wantedWidth, wantedHeight, bounds) {
    const b = bounds || {}
    const minWidth = Math.max(1, Number(b.minWidth) || 1)
    const maxWidth = Math.max(minWidth, Number(b.maxWidth) || minWidth)
    const asked = Number(wantedWidth) > 0 ? Number(wantedWidth) : Number(b.width) || minWidth
    const width = clamp(Math.round(asked), minWidth, maxWidth)
    const minHeight = Math.max(1, Number(b.minHeight) || 1)
    const room = Number(b.room) > 0 ? Math.round(Number(b.room)) : 0
    const maxHeight = room > 0 ? Math.max(minHeight, room) : 0
    const wanted = Number(wantedHeight) > 0 ? Math.round(Number(wantedHeight)) : 0
    const height = wanted <= 0 ? 0
        : maxHeight > 0 ? clamp(wanted, minHeight, maxHeight) : Math.max(minHeight, wanted)
    return { width: width, height: height }
}

// The size the panel's corner is asking for, from where the pointer is and
// where the card's *fixed* corner was when the drag began.
//
// `origin` is { right, top } and it is taken once, at the press. Reading the
// card's live edge instead made the drag chase its own result: ShellPanel
// anchors the control center to the desktop clock whenever that clock sits in
// the left two thirds, and then both edges move with the width, so the gearing
// halved, the drag lagged a frame and it never landed where it was let go.
function panelDragTo(x, y, origin, bounds) {
    const o = origin || {}
    return panelBox(Math.max(1, Math.round(Number(o.right) - Number(x))),
                    Math.max(1, Math.round(Number(y) - Number(o.top))),
                    bounds)
}

// How many grid columns a panel of that width is worth. Floored, not rounded:
// rounding up handed out a column the width did not pay for, so every column
// came out narrower than the metric says one is worth.
function columnsFor(width, cell, most) {
    const step = Math.max(1, Number(cell) || 1)
    const top = Math.max(1, Math.round(Number(most) || 1))
    return Math.max(1, Math.min(top, Math.floor(Number(width) / step)))
}

// ---- where a drop would land ----------------------------------------------

// Rectangles without the cell being dragged.
function others(cells, skipId) {
    return (cells || []).filter(cell => cell && cell.id !== skipId)
}

// The index a dragged cell would take, from placed rectangles. The rows come
// out of those rectangles, so this needs no column count of its own.
//
// The row is chosen first, by the band it occupies, and only then the place
// within it - by the same centre line the bar has always used. Choosing on x
// alone would let a point low on the panel land in the top row, and the index
// is flat, so getting the row wrong puts the cell a whole row away.
//
// The bands are built in *reading* order, not in list order. It used to be list
// order, which quietly assumed that the cells sharing a row are neighbours in
// the list and ascend in x - true of a shelf packer and false of gridLayout,
// which floats a later cell up into a hole an earlier row left open. The index
// that came back then was the floated cell's own, and the drop landed a row
// away. Each cell keeps the index it has in the list, so what comes back is
// still a list index; only the order they are read in changed.
//
// `vertical` swaps the two axes, for a bar that runs down the screen instead
// of across it. It is the mirror case of a one-row bar: there, all the cells
// share a `y` and the bands collapse to one, so only the centre-line test
// decides; here they share an `x` and the bands would collapse the other way,
// leaving the centre-line test comparing numbers that are all the same. Both
// halves have to turn together or the drop lands anywhere.
function insertIndexAt(cells, x, y, skipId, vertical) {
    const list = others(cells, skipId)
    if (!list.length) return 0
    // The band axis and the axis within a band, named once.
    const band = cell => vertical ? cell.x : cell.y
    const bandSize = cell => vertical ? cell.width : cell.height
    const within = vertical ? y : x
    const along = cell => vertical ? cell.y : cell.x
    const alongSize = cell => vertical ? cell.height : cell.width
    const across = vertical ? x : y

    const reading = list.map((cell, index) => ({ cell: cell, index: index }))
    reading.sort((a, b) => (band(a.cell) - band(b.cell)) || (along(a.cell) - along(b.cell)))
    const bands = []
    for (const entry of reading) {
        const current = bands.length ? bands[bands.length - 1] : null
        if (current && current.start === band(entry.cell)) {
            current.end = Math.max(current.end, band(entry.cell) + bandSize(entry.cell))
            current.items.push(entry)
        } else {
            bands.push({ start: band(entry.cell), end: band(entry.cell) + bandSize(entry.cell), items: [entry] })
        }
    }
    // Before everything is the first place; past everything is the last.
    if (across < bands[0].start) return bands[0].items[0].index
    let chosen = bands[bands.length - 1]
    for (const entry of bands) {
        if (across <= entry.end) { chosen = entry; break }
    }
    for (const entry of chosen.items) {
        if (within < along(entry.cell) + alongSize(entry.cell) / 2) return entry.index
    }
    // Past the last cell of this band: whatever is read next, or the end.
    const last = chosen.items[chosen.items.length - 1]
    const after = reading.indexOf(last) + 1
    return after < reading.length ? reading[after].index : list.length
}

// Where a drop really lands on a grid the user sizes.
//
// insertIndexAt answers from the rectangles alone, which is all a surface that
// can only report its cells has to offer. A sized grid can do better: pack the
// grid once for every candidate index and keep the one that puts the dragged
// cell under the hand. It is honest by construction, because the preview packs
// the very same order - so what is shown while dragging is what is written on
// release, instead of the two agreeing by argument.
//
// It costs one pack per cell per pointer move. With twelve tiles that is
// nothing; a surface with hundreds of cells would want a cheaper answer.
//
// `entries` are { id, w, h } in the committed order, `point` is
// { x, y, grabX, grabY } - where the pointer is, and where inside the cell it
// took hold, so the cell is judged by the corner the hand is actually holding.
function gridDropIndex(entries, dragId, point, grid) {
    const list = (entries || []).filter(entry => entry && entry.id)
    const ids = list.map(entry => entry.id)
    if (ids.indexOf(dragId) < 0) return 0
    const byId = {}
    for (const entry of list) byId[entry.id] = entry
    const at = point || {}
    const x = Number(at.x) || 0
    const y = Number(at.y) || 0
    const grabX = Number(at.grabX) || 0
    const grabY = Number(at.grabY) || 0
    const box = grid || {}
    let best = 0
    let bestDistance = Infinity
    for (let index = 0; index < list.length; ++index) {
        const packed = gridLayout(previewOrder(ids, dragId, index).map(id => byId[id]),
                                  box.columns, box.width, box.gap, box.unit)
        const cell = packed.cells.find(each => each.id === dragId)
        if (!cell) continue
        const dx = cell.x + grabX - x
        const dy = cell.y + grabY - y
        const distance = dx * dx + dy * dy
        // Strictly nearer, so a tie keeps the lower index and a drop that
        // changes nothing stays where it was.
        if (distance < bestDistance) {
            bestDistance = distance
            best = index
        }
    }
    return best
}

// The gap a drop would open, as a rectangle to draw a marker in. An empty
// surface marks its own centre.
//
// The answer is a hairline across the bar, so only one of its two sizes is
// given: `height` for a horizontal bar, `width` for a vertical one. The
// caller supplies the other, because it is the one that knows how thick a
// marker should be - and giving both would invite it to draw a rectangle
// where a line is meant.
function markerRect(cells, index, skipId, area, gap, vertical) {
    const list = others(cells, skipId)
    const half = Math.max(0, Number(gap) || 0) / 2
    const box = area || { x: 0, y: 0, width: 0, height: 0 }
    const at = (alongStart, acrossStart, acrossSize) => vertical
        ? { x: acrossStart, y: alongStart, width: acrossSize }
        : { x: alongStart, y: acrossStart, height: acrossSize }
    const along = cell => vertical ? cell.y : cell.x
    const alongSize = cell => vertical ? cell.height : cell.width
    const across = cell => vertical ? cell.x : cell.y
    const acrossSize = cell => vertical ? cell.width : cell.height

    if (!list.length) {
        const centre = vertical ? box.y + box.height / 2 : box.x + box.width / 2
        return at(centre, vertical ? box.x : box.y, vertical ? box.width : box.height)
    }
    const place = Math.max(0, Math.min(list.length, index))
    if (place === 0)
        return at(along(list[0]) - half, across(list[0]), acrossSize(list[0]))
    const before = list[place - 1]
    return at(along(before) + alongSize(before) + half, across(before), acrossSize(before))
}

// ---- the order a drop would produce ---------------------------------------

// The order the surface would have if the drag ended now. `index` counts the
// list without the dragged id, which is the same thing the model operations
// mean by it - the test holds the two against each other.
function previewOrder(ids, dragId, index) {
    const list = (ids || []).slice()
    const from = list.indexOf(dragId)
    if (from < 0) return list
    list.splice(from, 1)
    list.splice(Math.max(0, Math.min(list.length, index)), 0, dragId)
    return list
}

// ---- zones (the bar's three thirds, the notch's two, a dashboard column) ---

// Zone under a point: the one whose rectangle contains it, otherwise the
// nearest. Zones are laid out along one axis; `vertical` picks which.
function zoneAt(zones, x, y, vertical) {
    const list = zones || []
    if (!list.length) return ""
    const along = vertical ? y : x
    for (const zone of list) {
        const start = vertical ? zone.y : zone.x
        const size = vertical ? zone.height : zone.width
        if (along >= start && along <= start + size) return zone.key
    }
    let best = list[0]
    let bestDistance = Infinity
    for (const zone of list) {
        const start = vertical ? zone.y : zone.x
        const size = vertical ? zone.height : zone.width
        const distance = along < start ? start - along : along - (start + size)
        if (distance < bestDistance) {
            bestDistance = distance
            best = zone
        }
    }
    return best.key
}

// Whether a drop moves the cell at all. `index` counts the zone without the
// dragged cell, so dropping it back on its own gap changes nothing and must
// not be written, undone or animated.
function changes(place, zone, index) {
    if (!place || place.zone !== zone) return true
    return index !== place.index
}
