import Quickshell
import QtQuick
import "Harness.js" as T
import "../../services/arrange/ArrangeLogic.js" as A
import "../../services/LayoutLogic.js" as L
import "../../services/quick/QuickLogic.js" as Quick

// The geometry behind every surface the user arranges by dragging. A drag
// cannot be screenshotted (see Pitfalls in docs/testing.md), so this is where
// the behaviour is actually held to account.
ShellRoot {
    // A row of same-sized cells, placed the way a panel would place them.
    function grid(count, columns, width, gap, span) {
        const cells = []
        for (let index = 0; index < count; ++index)
            cells.push({ id: "t" + index, span: (span && span[index]) || 1, contentHeight: 50 })
        return A.layout(cells, columns, width, gap)
    }
    function ids(cells) { return cells.map(cell => cell.id) }

    Component.onCompleted: {
        // ---- layout: rows, spans and height -------------------------------
        const two = grid(4, 2, 410, 10)
        T.eq(two.cells.length, 4, "every cell is placed")
        T.eq(two.cells[0].width, 200, "two columns share the width minus the gap")
        T.eq([two.cells[0].x, two.cells[1].x], [0, 210], "the second column starts after the gap")
        T.eq([two.cells[0].y, two.cells[2].y], [0, 60], "the third cell starts the second row")
        T.eq(two.height, 110, "two rows of 50 with one gap between them")

        const one = grid(3, 1, 200, 10)
        T.eq(ids(one.cells), ["t0", "t1", "t2"], "one column is a list")
        T.eq(one.cells.map(cell => cell.width), [200, 200, 200], "a single column takes the whole width")
        T.eq(one.height, 170, "three rows of 50 with two gaps")

        // A wide cell takes both columns and pushes what does not fit down.
        const wide = A.layout([
            { id: "a", span: 1, contentHeight: 50 },
            { id: "b", span: 2, contentHeight: 30 },
            { id: "c", span: 1, contentHeight: 50 }
        ], 2, 410, 10)
        T.eq(wide.cells[0].y, 0, "the first cell stays in the first row")
        T.eq(wide.cells[1].y, 60, "a wide cell that does not fit starts a new row")
        T.eq(wide.cells[1].width, 410, "a wide cell spans both columns and the gap between them")
        T.eq(wide.cells[2].y, 100, "the next cell follows the wide row")

        // In one column a wide cell is just a cell; nothing special happens.
        const narrow = A.layout([{ id: "a", span: 2, contentHeight: 50 }], 1, 200, 10)
        T.eq(narrow.cells[0].width, 200, "a span is clamped to the columns there are")

        // A row is as tall as its tallest cell, so the two line up.
        const uneven = A.layout([
            { id: "a", span: 1, contentHeight: 50 },
            { id: "b", span: 1, contentHeight: 80 }
        ], 2, 410, 10)
        T.eq([uneven.cells[0].height, uneven.cells[1].height], [80, 80], "a row is as tall as its tallest cell")
        T.eq(uneven.height, 80, "and the whole thing is that tall")

        T.eq(A.layout([], 2, 410, 10).height, 0, "nothing to place is no height")

        // ---- the control center's own arrangement -------------------------
        // The regression guard for replacing its GridLayout: the twelve default
        // tiles, three of them wide, in the two-column panel.
        const quick = L.quickItems(L.defaultQuick()).map(item => ({ id: item.id, w: item.w, h: item.h }))
        const panel = A.gridLayout(quick, 2, 410, 10, 30)
        T.eq(panel.cells.length, 12, "every default tile is placed")
        T.ok(panel.cells.every(cell => cell.width === 200 || cell.width === 410),
             "a tile is one column or both, never something between")
        T.eq(panel.cells[0].height, 70, "a plain tile is two rows of the panel's grid")
        T.ok(panel.height > 0, "the panel has a height")

        // ---- a grid the user sizes ---------------------------------------
        // Four columns of 100 with gaps of 10 in 430, rows of 40.
        const g = (id, w, h) => ({ id: id, w: w, h: h })
        const sized = A.gridLayout([g("a", 1, 1), g("b", 2, 2), g("c", 1, 1), g("d", 4, 1)], 4, 430, 10, 40)
        T.eq(sized.cells.map(c => [c.id, c.x, c.y, c.width, c.height]),
             [["a", 0, 0, 100, 40], ["b", 110, 0, 210, 90], ["c", 330, 0, 100, 40], ["d", 0, 100, 430, 40]],
             "cells take the columns and rows they ask for, and a full row wraps")
        T.eq(sized.height, 140, "the grid is as tall as its rows, with no gap under the last")

        // Two short cells fit beside one tall cell, one under the other. A
        // shelf packer could only ever put one thing beside a tall neighbour.
        const beside = A.gridLayout([g("tall", 2, 2), g("one", 2, 1), g("two", 2, 1)], 4, 430, 10, 40)
        T.eq(beside.cells.map(c => [c.id, c.x, c.y]),
             [["tall", 0, 0], ["one", 220, 0], ["two", 220, 50]],
             "the second short cell goes under the first, beside the tall one")
        T.eq(beside.height, 90, "and the grid is only two rows tall")
        // A cell slots into a hole an earlier row left open.
        const hole = A.gridLayout([g("a", 3, 1), g("b", 1, 1), g("c", 1, 1)], 4, 430, 10, 40)
        T.eq(hole.cells.map(c => [c.id, c.x, c.y]), [["a", 0, 0], ["b", 330, 0], ["c", 0, 50]],
             "the first free slot wins, scanning top to bottom")
        T.eq(A.gridLayout([g("a", 9, 1)], 2, 210, 10, 40).cells[0].width, 210, "a cell never asks for more columns than there are")
        T.eq(A.gridLayout([g("a", 1, 0)], 2, 210, 10, 40).cells[0].height, 40, "nor for less than one row")
        T.eq(A.gridLayout([], 4, 430, 10, 40), { cells: [], height: 0 }, "an empty grid")

        // A placed cell carries the size it was really granted, so nothing has
        // to re-attach the stored one and reach past the edge the packer
        // stopped at.
        T.eq(sized.cells.map(c => [c.id, c.w, c.h]),
             [["a", 1, 1], ["b", 2, 2], ["c", 1, 1], ["d", 4, 1]],
             "a placed cell says how wide and tall it ended up")
        T.eq(A.gridLayout([g("a", 9, 1)], 2, 210, 10, 40).cells[0].w, 2, "and that is the clamped size")

        // Dragging a corner: the size it asks for, in steps.
        const origin = { x: 0, y: 0 }
        T.eq(A.sizeAt(100, 40, origin, 4, 430, 10, 40), { w: 1, h: 1 }, "a corner at the cell's own corner is one step")
        T.eq(A.sizeAt(210, 90, origin, 4, 430, 10, 40), { w: 2, h: 2 }, "dragged to the second column and row")
        T.eq(A.sizeAt(9999, 9999, origin, 4, 430, 10, 40).w, 4, "never wider than the grid")
        T.eq(A.sizeAt(-50, -50, origin, 4, 430, 10, 40), { w: 1, h: 1 }, "nor smaller than one step")
        T.eq(A.sizeAt(320, 40, { x: 110, y: 0 }, 4, 430, 10, 40), { w: 2, h: 1 },
             "the handle measures from the cell, not from the surface")
        // Both axes stop where the packer would stop, so the preview cannot
        // promise a size the release then takes back.
        T.eq(A.sizeAt(9999, 40, { x: 110, y: 0 }, 4, 430, 10, 40).w, 3,
             "a cell never reaches past the edge from the column it starts in")
        T.eq(A.sizeAt(100, 9999, origin, 4, 430, 10, 40, 6).h, 6, "nor past the rows the file allows")
        T.ok(A.sizeAt(100, 9999, origin, 4, 430, 10, 40).h > 6, "and no ceiling given is no ceiling")

        // ---- insertIndexAt: rows first, then the centre line --------------
        // Four cells, two columns: t0 t1 / t2 t3, each 200 wide, 50 tall.
        const cells = two.cells
        const left0 = cells[0], right0 = cells[1], left1 = cells[2]

        T.eq(A.insertIndexAt(cells, left0.x + 10, left0.y + 10, ""), 0,
             "left of the first cell's centre is the first place")
        T.eq(A.insertIndexAt(cells, left0.x + 190, left0.y + 10, ""), 1,
             "right of it is the second")
        T.eq(A.insertIndexAt(cells, right0.x + 190, right0.y + 10, ""), 2,
             "past the end of the first row is the third")

        // The bug class this exists for: a point low on the panel must never
        // answer with an index from the row above it.
        T.eq(A.insertIndexAt(cells, left1.x + 10, left1.y + 10, ""), 2,
             "left of the second row's first cell is that cell's flat index, not 0")
        T.eq(A.insertIndexAt(cells, left1.x + 190, left1.y + 10, ""), 3,
             "and right of it is the next")
        T.eq(A.insertIndexAt(cells, cells[3].x + 190, cells[3].y + 10, ""), 4,
             "past the last cell is the end")

        // Outside the rows altogether.
        T.eq(A.insertIndexAt(cells, left0.x + 10, -50, ""), 0, "above everything is the first place")
        T.eq(A.insertIndexAt(cells, cells[3].x + 190, 5000, ""), 4, "below everything is the last")
        T.eq(A.insertIndexAt([], 10, 10, ""), 0, "an empty surface takes the first place")

        // The dragged cell does not count towards the index it is dropped at.
        T.eq(A.insertIndexAt(cells, left1.x + 10, left1.y + 10, "t0", 2), 1,
             "the dragged cell is left out of the count")

        // The bug the bands were rewritten for: gridLayout floats a later cell
        // up into a hole, so the cells sharing a row are neither neighbours in
        // the list nor ascending in x. Reading them in list order answered with
        // the floated cell's own index and put the drop a whole row away.
        const floated = A.gridLayout([g("a", 1, 2), g("b", 2, 1), g("c", 1, 2)], 2, 210, 10, 40)
        T.eq(floated.cells.map(c => [c.id, c.x, c.y]), [["a", 0, 0], ["b", 0, 100], ["c", 110, 0]],
             "c floats up beside a, and the wide b starts the row below them")
        T.eq(A.insertIndexAt(floated.cells, 190, 10, ""), 1,
             "a drop to the right of the floated cell is not that cell's own index")

        // ---- gridDropIndex: the index the grid will really honour ---------
        // Packed once per candidate, so the preview and the drop cannot
        // disagree - they run the same order through the same packer.
        const box = { columns: 2, width: 210, gap: 10, unit: 40 }
        const three = [g("a", 1, 1), g("b", 1, 1), g("c", 1, 1)]
        T.eq(A.gridDropIndex(three, "c", { x: 5, y: 5, grabX: 0, grabY: 0 }, box), 0,
             "carried to the top left corner, the last cell takes the first place")
        T.eq(A.gridDropIndex(three, "a", { x: 5, y: 55, grabX: 0, grabY: 0 }, box), 2,
             "carried into the second row, the first cell takes the last place")
        T.eq(A.gridDropIndex(three, "b", { x: 115, y: 5, grabX: 0, grabY: 0 }, box), 1,
             "left where it was, a cell keeps its own index")
        T.eq(A.gridDropIndex(three, "zz", { x: 0, y: 0 }, box), 0, "an id that is not there takes the first place")
        T.eq(A.gridDropIndex([], "a", { x: 0, y: 0 }, box), 0, "and so does an empty surface")
        // The grab point is honoured: the same pointer, held by the cell's
        // bottom right instead of its top left, means a different place.
        T.eq(A.gridDropIndex(three, "a", { x: 105, y: 95, grabX: 100, grabY: 40 }, box), 2,
             "a cell is judged by the corner the hand is holding")

        // ---- previewOrder agrees with the model ---------------------------
        // This is the contract that makes the preview honest: what the user
        // sees while dragging has to be what the model does on release.
        const list = ["a", "b", "c", "d", "e"]
        const model = L.sanitizeQuick({ quick: list.map(id => ({ id: id, items: [{ type: "wifi" }] })) })
        for (let from = 0; from < list.length; ++from) {
            for (let to = 0; to < list.length; ++to) {
                const preview = A.previewOrder(list, list[from], to)
                const moved = L.moveQuickTileTo(model, list[from], to).quick.map(pill => pill.id)
                T.eq(preview, moved, "preview and model agree moving " + from + " to " + to)
            }
        }
        T.eq(A.previewOrder(list, "zz", 2), list, "an unknown id changes nothing")
        T.eq(A.previewOrder(list, "a", 99), ["b", "c", "d", "e", "a"], "past the end is the end")
        T.eq(A.previewOrder(list, "e", -3), ["e", "a", "b", "c", "d"], "before the start is the start")

        // Dropping a cell back where it came from leaves the order alone.
        T.eq(A.previewOrder(list, "c", 2), list, "dropping a cell on its own gap changes nothing")

        // ---- the gap the marker draws -------------------------------------
        const marker0 = A.markerRect(cells, 0, "", null, 10)
        T.eq(marker0.x, cells[0].x - 5, "the marker for the first place sits in the half gap before it")
        const marker1 = A.markerRect(cells, 1, "", null, 10)
        T.eq(marker1.x, cells[0].x + cells[0].width + 5, "and after a cell for the next")
        T.eq(marker1.y, cells[0].y, "the marker takes the row's top")
        const empty = A.markerRect([], 0, "", { x: 10, y: 20, width: 100, height: 40 }, 10)
        T.eq([empty.x, empty.height], [60, 40], "an empty surface marks its own centre")

        // ---- zones --------------------------------------------------------
        const zones = [{ key: "left", x: 0, y: 0, width: 100, height: 40 },
                       { key: "center", x: 110, y: 0, width: 100, height: 40 },
                       { key: "right", x: 220, y: 0, width: 100, height: 40 }]
        T.eq(A.zoneAt(zones, 50, 20, false), "left", "a point inside a zone is that zone")
        T.eq(A.zoneAt(zones, 160, 20, false), "center", "the middle one too")
        T.eq(A.zoneAt(zones, 105, 20, false), "left", "between two zones is the nearer one")
        T.eq(A.zoneAt(zones, -80, 20, false), "left", "left of everything is the first")
        T.eq(A.zoneAt(zones, 900, 20, false), "right", "right of everything is the last")
        T.eq(A.zoneAt([], 50, 20, false), "", "no zones is no zone")

        const stacked = [{ key: "top", x: 0, y: 0, width: 100, height: 40 },
                         { key: "bottom", x: 0, y: 50, width: 100, height: 40 }]
        T.eq(A.zoneAt(stacked, 10, 60, true), "bottom", "a stacked zone is chosen on y")
        T.eq(A.zoneAt(stacked, 10, 10, true), "top", "and so is the one above it")

        // ---- changes ------------------------------------------------------
        T.ok(!A.changes({ zone: "left", index: 2 }, "left", 2), "its own gap is not a change")
        T.ok(A.changes({ zone: "left", index: 2 }, "left", 3), "another index is")
        T.ok(A.changes({ zone: "left", index: 2 }, "right", 2), "another zone is")
        T.ok(A.changes(null, "left", 0), "a cell with no place anywhere is a change")

        // ---- how wide the panel is, in columns -------------------------------
        // Measured against the panel's content width: the card minus its
        // padding twice. Floored, so a column is never narrower than the metric
        // says one is worth - and the last column is reachable, which it was
        // not while the count was rounded.
        T.eq(A.columnsFor(320, 210, 4), 1, "the narrowest panel is a single column")
        T.eq(A.columnsFor(600, 210, 4), 2, "the default panel is two")
        T.eq(A.columnsFor(860, 210, 4), 4, "and the widest reaches the last column")
        T.eq(A.columnsFor(419, 210, 4), 1, "a width that does not pay for a column does not get one")
        T.eq(A.columnsFor(99999, 210, 4), 4, "never more columns than the grid has")
        T.eq(A.columnsFor(0, 210, 4), 1, "nor fewer than one")

        // ---- how big the panel is, as it was dragged -------------------------
        const bounds = { minWidth: 360, maxWidth: 900, width: 640, minHeight: 200, room: 800 }
        T.eq(A.panelBox(0, 0, bounds), { width: 640, height: 0 },
             "a panel that was never dragged is its default width and follows its content")
        T.eq(A.panelBox(700, 500, bounds), { width: 700, height: 500 }, "a dragged size is kept")
        T.eq(A.panelBox(99999, 99999, bounds), { width: 900, height: 800 },
             "never wider than it may be, nor taller than the room below it")
        T.eq(A.panelBox(10, 10, bounds), { width: 360, height: 200 },
             "nor narrower, nor short enough to empty its own body")
        T.eq(A.panelBox(700, 500, { minWidth: 360, maxWidth: 900, width: 640, minHeight: 200 }),
             { width: 700, height: 500 }, "with no room given the height is only floored")
        // A floor that is taller than the room still wins: a panel with no body
        // is worse than one that runs a little past the bottom.
        T.eq(A.panelBox(700, 500, { minWidth: 360, maxWidth: 900, width: 640, minHeight: 200, room: 100 }).height,
             200, "the floor beats a room too small to hold it")
        T.eq(A.panelBox(-5, -5, bounds), { width: 640, height: 0 }, "nonsense is the default")

        // The corner is measured from where the card's fixed corner was when
        // the drag began, not from where it is now.
        const corner = { right: 1000, top: 100 }
        T.eq(A.panelDragTo(400, 700, corner, bounds), { width: 600, height: 600 },
             "the width grows leftwards and the height downwards")
        T.eq(A.panelDragTo(1100, 50, corner, bounds), { width: 360, height: 200 },
             "dragged past the corner it stops at its floors")
        T.eq(A.panelDragTo(-500, 5000, corner, bounds), { width: 900, height: 800 },
             "and dragged off the screen it stops at its ceilings")


        // ---- the bar: one row, through the same functions -----------------
        // The bar had its own copy of all of this (shell/editor/BarDrop.js)
        // until it was deleted. These are its own tests, kept as they were, so
        // the one-dimensional case cannot quietly stop working now that the
        // same functions also serve a grid. A bar reports whole rectangles; the
        // row half never decides anything here, and has to be ignored.
        const barZones = [{ key: "left", x: 0, y: 0, width: 300, height: 40 },
                          { key: "center", x: 310, y: 0, width: 300, height: 40 },
                          { key: "right", x: 620, y: 0, width: 300, height: 40 }]
        T.eq([A.zoneAt(barZones, 10, 20, false), A.zoneAt(barZones, 400, 20, false),
              A.zoneAt(barZones, 700, 20, false)], ["left", "center", "right"], "zone under the pointer")
        T.eq(A.zoneAt(barZones, 305, 20, false), "left", "the gap between two zones takes the nearer one")
        T.eq([A.zoneAt(barZones, -50, 20, false), A.zoneAt(barZones, 5000, 20, false)],
             ["left", "right"], "outside the strip clamps to the ends")
        T.eq(A.zoneAt([], 10, 20, false), "", "no zones, no target")

        const pills = [{ id: "a", x: 0, y: 0, width: 100, height: 40 },
                       { id: "b", x: 110, y: 0, width: 100, height: 40 },
                       { id: "c", x: 220, y: 0, width: 100, height: 40 }]
        T.eq([A.insertIndexAt(pills, 10, 20, ""), A.insertIndexAt(pills, 60, 20, ""),
              A.insertIndexAt(pills, 165, 20, "")], [0, 1, 2], "index follows the pill centres")
        T.eq(A.insertIndexAt(pills, 400, 20, ""), 3, "past the last pill appends")
        T.eq(A.insertIndexAt([], 400, 20, ""), 0, "an empty zone takes the first place")
        T.eq(A.insertIndexAt(pills, 165, 20, "b"), 1, "the dragged pill does not count")
        T.eq(A.insertIndexAt(pills, 400, 20, "c"), 2, "dragging the last pill past the end stays at the end")

        T.eq(A.markerRect(pills, 0, "", barZones[0], 10).x, -5, "marker before the first pill")
        T.eq(A.markerRect(pills, 2, "", barZones[0], 10).x, 215, "marker in the gap")
        T.eq(A.markerRect(pills, 9, "", barZones[0], 10).x, 325, "marker after the last pill")
        T.eq(A.markerRect(pills, 1, "a", barZones[0], 10).x, 215, "marker skips the dragged pill")
        T.eq(A.markerRect([], 0, "", barZones[1], 10).x, 460, "an empty zone marks its centre")

        // ---- the same bar, running down the screen ------------------------
        // A vertical bar is the mirror case of a one-row bar: there every cell
        // shares a `y` and only the centre-line test decides; here they share
        // an `x`. Both halves have to turn together or the drop lands anywhere.
        const column = [{ id: "a", x: 0, y: 0, width: 40, height: 100 },
                        { id: "b", x: 0, y: 110, width: 40, height: 100 },
                        { id: "c", x: 0, y: 220, width: 40, height: 100 }]

        T.eq(A.insertIndexAt(column, 20, 10, "", true), 0, "above the first item's middle is the first place")
        T.eq(A.insertIndexAt(column, 20, 90, "", true), 1, "below it is the second")
        T.eq(A.insertIndexAt(column, 20, 200, "", true), 2, "and on down the column")
        T.eq(A.insertIndexAt(column, 20, 310, "", true), 3, "past the last is the end")
        T.eq(A.insertIndexAt(column, 20, -50, "", true), 0, "before everything is the first place")
        T.eq(A.insertIndexAt(column, 20, 5000, "", true), 3, "past everything is the last")
        T.eq(A.insertIndexAt(column, 20, 200, "b", true), 1, "the dragged item is not one of its own neighbours")
        T.eq(A.insertIndexAt([], 20, 20, "", true), 0, "an empty column takes the first place")

        // Read the same column horizontally and the answer is nonsense, which
        // is the point of the flag: every cell shares an x, so the centre-line
        // test compares three identical numbers.
        T.eq([A.insertIndexAt(column, 20, 10, "", true), A.insertIndexAt(column, 20, 10, "", false)], [0, 1],
             "the flag is not decoration: the same point answers differently")

        // The marker turns with it: a hairline *across* the bar, so the size
        // that comes back is the other one.
        const down0 = A.markerRect(column, 0, "", null, 10, true)
        T.eq([down0.y, down0.x, down0.width], [-5, 0, 40], "the first place is the half gap above it, full width of the bar")
        const down1 = A.markerRect(column, 1, "", null, 10, true)
        T.eq(down1.y, 105, "and after an item for the next")
        T.eq(down1.height, undefined, "a vertical marker says its width, not its height")
        T.eq(A.markerRect(column, 0, "", null, 10, false).width, undefined, "and a horizontal one the other way round")
        const emptyDown = A.markerRect([], 0, "", { x: 10, y: 20, width: 40, height: 300 }, 10, true)
        T.eq([emptyDown.y, emptyDown.x, emptyDown.width], [170, 10, 40], "an empty column marks its own centre")

        // Zones stack too, which zoneAt could already do - it is the one piece
        // of this that was built before the rest.
        const downZones = [{ key: "start", x: 0, y: 0, width: 40, height: 100 },
                           { key: "center", x: 0, y: 110, width: 40, height: 100 },
                           { key: "end", x: 0, y: 220, width: 40, height: 100 }]
        T.eq(A.zoneAt(downZones, 20, 50, true), "start", "a point in the first third is the start zone")
        T.eq(A.zoneAt(downZones, 20, 160, true), "center", "the middle one too")
        T.eq(A.zoneAt(downZones, 20, 5000, true), "end", "and past the end is the end")

        T.finish("arrange")
        Qt.quit()
    }
}
