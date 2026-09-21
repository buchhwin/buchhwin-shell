.pragma library

// What a cell of a given size should draw, for the three surfaces whose tiles
// the user pulls to a size: the control center, the dashboard and the notch.
//
// Before this existed every tile drew exactly one arrangement, anchored to the
// top of its cell, and a cell too short simply clipped it - a shorter media
// player was the same player with its controls cut off. That is the thing this
// file is here to end: a smaller cell shows *something else*, not less of the
// big one.
//
// Two questions, and they are not the same question:
//
//   Which shape?    A matter of grid steps. One column stacks, two or more
//                   place side by side. `fitClass` answers it.
//   How much fits?  A matter of pixels, because a row is 30 px in the control
//                   center and 64 px in the dashboard - the same step count is
//                   wildly different room. `rowsFor` answers it, generalising
//                   what the notch's events block already did by hand.
//
// Nothing here is ever stored. LayoutLogic says it plainly: "There is no
// ladder of three names: a corner is dragged and the size is whatever it lands
// on, bounded by the grid itself rather than by a vocabulary." A class is
// derived from the cell the packer granted, every time, and no layout file
// carries one.

// The five shapes a granted cell can have.
var CLASSES = ["icon", "small", "wide", "tall", "large"]

function step(value, fallback) {
    const number = Math.round(Number(value))
    return isFinite(number) && number >= 1 ? number : fallback
}

// The shape of a cell `w` columns wide and `h` rows tall.
//
//   icon   1x1      a glyph and one value, nothing else fits
//   small  1x2-3    the glyph, a name and a value, stacked
//   wide   2+x1-2   the same parts in a row, because there is width but no
//                   height - a short wide cell is the one shape a stack
//                   cannot serve at all
//   tall   1x4+     the full stacked form: a list, a forecast, controls
//   large  2+x3+    both, so everything a tile has to say
//
// Anything unreadable is `small`, which is what a tile starts as and the only
// answer that is wrong in no direction.
function fitClass(w, h) {
    const across = step(w, 0)
    const down = step(h, 0)
    if (across < 1 || down < 1) return "small"
    if (across === 1) {
        if (down === 1) return "icon"
        return down <= 3 ? "small" : "tall"
    }
    return down <= 2 ? "wide" : "large"
}

// The size name a widget already understands (WidgetBase.sizeClass) for a cell
// of this many **pixels**. Eleven widgets draw genuinely differently per name -
// a short date against a long one, a bar and a detail line instead of a bare
// number - and a surface that loads one has to say which it wants.
//
// Pixels, not grid steps, and that was measured twice. A widget's ladder is a
// *width* ladder: each step up is longer text in a bigger type. Asking a
// one-column notch cell for "large" because it was five rows tall drew the
// long date in headline type across 170 px and clipped it at both ends - so
// height only lifts a cell off `icon`. And a step is not a width: one column
// is 175 px on the notch, 210 in the control center and 420 on the dashboard,
// so deciding on steps put a lone glyph in a dashboard cell wide enough for a
// sentence.
//
// The thresholds are about text, not about the theme's spacing, which is why
// they live here: roughly a glyph, a glyph and a value, a name in front of it,
// and a detail line after it.
var WIDGET_ICON_WIDTH = 120
var WIDGET_SMALL_WIDTH = 260
var WIDGET_MEDIUM_WIDTH = 400
var WIDGET_MIN_HEIGHT = 26

// `expanded` is deliberately never produced: it is the bar's pill display,
// not a shape a grid cell can have.
function widgetSize(width, height) {
    const across = Number(width)
    const down = Number(height)
    if (!isFinite(across) || across <= 0) return "small"
    if (isFinite(down) && down > 0 && down < WIDGET_MIN_HEIGHT) return "icon"
    if (across < WIDGET_ICON_WIDTH) return "icon"
    if (across < WIDGET_SMALL_WIDTH) return "small"
    if (across < WIDGET_MEDIUM_WIDTH) return "medium"
    return "large"
}

// How many rows of `rowHeight` fit in `height`, with `gap` between them, and
// never fewer than one - a cell too short for even one row shows one anyway
// rather than nothing, because an empty field says less than a cut-off line.
//
// This is the notch events block's arithmetic, which was the only place in the
// shell that read the room it had been given instead of assuming it.
function rowsFor(height, rowHeight, gap) {
    const room = Number(height)
    const row = Number(rowHeight)
    const space = Number(gap) || 0
    if (!isFinite(room) || !isFinite(row) || row <= 0) return 1
    return Math.max(1, Math.floor((room + space) / (row + space)))
}

// Whether a block of `wanted` pixels has room in `height`. The same question
// as `rowsFor` for something that is not a list: a forecast strip, a cover, a
// row of controls. Hiding it is what leaves the rest legible.
function roomFor(height, wanted) {
    const room = Number(height)
    const need = Number(wanted)
    if (!isFinite(room) || !isFinite(need)) return false
    return room >= need
}

// The smallest cell a tile may be pulled to. A catalogue entry says so with
// `minW`/`minH`; most do not, and one step in each direction is the answer for
// them. A media player at 1x1 is not a smaller player, it is not a player.
function minSize(entry) {
    const found = entry || {}
    return { w: step(found.minW, 1), h: step(found.minH, 1) }
}
