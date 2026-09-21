.pragma library

// Geometry of the bar (shell/bar/PillBar.qml) in its two styles:
//   pills  floating capsules, one per pill (LayoutLogic bar zones)
//   bar    one continuous bar; "floating" is inset by the margin with all
//          corners rounded, "attached" is flush with its own screen edge and
//          the screen sides, filled through to its inner edge, with the
//          rounding on the window side of it: two concave corners in its own
//          colour at the screen's sides, so the area the windows live in is
//          what looks rounded
// The bar hangs from any of the four screen edges (`edge`). Top and bottom
// make it horizontal, left and right vertical.
// Pixel values come from theme tokens passed in by the caller.

var STYLES = ["pills", "bar"]
var POSITIONS = ["floating", "attached"]
// Which screen edge the bar hangs from. A separate axis from `position`,
// which says whether it floats or is flush: a floating bar may sit at the
// bottom and an attached one at the left.
//
// Everything below is written in the bar's *own* two directions rather than in
// x and y: **along** is the direction it runs (across the screen for a top
// bar, down it for a left one) and **across** is how thick it is. The mapping
// to x and y happens once, at the end of `geometry`. Writing it the other way
// round - an x/y version and a second y/x version beside it - is how the two
// drift apart, and the concave corners alone are eight segments and two arcs.
var EDGES = ["top", "bottom", "left", "right"]

// Where along the bar something opens. "widget" is what the shell has always
// done - out of the pill you clicked, and out of the bar's end for a
// notification with no pill of its own - and the other three pin it to a place
// regardless. Panels and notifications get one of these each, because wanting
// the control center under your hand and the notifications out of the way is
// one wish, not two conflicting ones.
var SPOTS = ["widget", "start", "centre", "end"]

function spot(value) { return oneOf(value, SPOTS, "widget") }

function oneOf(value, choices, fallback) {
    return choices.indexOf(value) >= 0 ? value : fallback
}

function style(value) { return oneOf(value, STYLES, "pills") }
function position(value) { return oneOf(value, POSITIONS, "floating") }
function edge(value) { return oneOf(value, EDGES, "top") }

// Whether the bar runs down the screen rather than across it.
function vertical(value) {
    const side = edge(value)
    return side === "left" || side === "right"
}

// Whether the bar hangs from the far edge - the bottom or the right - which is
// the one thing that mirrors rather than being direction-agnostic: an attached
// bar's rounding hangs *into* the screen, so it is drawn from the other side.
function farEdge(value) {
    const side = edge(value)
    return side === "bottom" || side === "right"
}

function nonNegative(value) {
    const number = Number(value)
    return isFinite(number) && number > 0 ? number : 0
}

// A corner radius from the theme, never more than a round end.
function cornerRadius(height, token) {
    return Math.min(nonNegative(height) / 2, nonNegative(token))
}

// Hover highlight inside the bar: concentric with the bar corners (bar radius
// minus the inset), at most a round end of the highlight itself. Items with a
// round cover at an end get round ends, concentric with the cover.
function highlightRadius(barRadius, inset, highlightHeight, roundEnd) {
    const round = nonNegative(highlightHeight) / 2
    return roundEnd ? round : Math.min(round, nonNegative(nonNegative(barRadius) - nonNegative(inset)))
}

// Layout of the bar surface for the length of the screen edge it hangs from -
// the screen's width for a top or bottom bar, its height for a left or right
// one. `metrics` holds the (already bar-scaled) tokens: height, margin,
// radius, border. `metrics.height` is the bar's thickness whichever way it
// runs.
//
// Everything is measured from the bar's **own** edge, not from the top of the
// screen: `inset` is how far into the screen the bar reaches, and `edge` says
// from which side. A caller turns that into a margin for whatever it is
// placing. The field used to be called `bottom`, which was true only while the
// bar could only be at the top.
//
// The one thing that mirrors rather than being edge-agnostic is the attached
// bar's rounding, which hangs *into* the screen - below a top bar, above a
// bottom one, right of a left one - so the far edges flip where it is drawn
// from. `farEdge` is that question asked once.
//
// Returns the surface's thickness, the space windows keep free when reserving,
// the inset panels open beyond, and for the bar style the background rect (it
// may extend past the surface so hidden edges draw no border) with per-corner
// radii and the content rect the zones sit in. Rects are in x/y, mapped from
// along/across at the end.
function geometry(styleName, positionName, edgeName, screenLength, metrics, reserve) {
    const name = style(styleName)
    const place = position(positionName)
    const side = edge(edgeName)
    const upright = vertical(side)
    const far = farEdge(side)
    const length = nonNegative(screenLength)
    const thick = nonNegative(metrics.height)
    const margin = nonNegative(metrics.margin)
    const border = nonNegative(metrics.border)
    const attached = name === "bar" && place === "attached"
    const thickness = attached ? thick : margin + thick
    const radius = cornerRadius(thick, metrics.radius)

    // The one place x and y are decided. Everything above and below this line
    // talks about the bar's own directions.
    const rect = (alongStart, alongSize, acrossStart, acrossSize) => upright
        ? { x: acrossStart, y: alongStart, width: acrossSize, height: alongSize }
        : { x: alongStart, y: acrossStart, width: alongSize, height: acrossSize }

    const result = {
        style: name,
        position: place,
        edge: side,
        vertical: upright,
        thickness: thickness,
        exclusiveZone: reserve ? thickness : 0,
        inset: thickness,
        // The margin is on the side away from the screen edge, so a floating
        // bottom bar has its gap below it, not above.
        content: rect(margin, Math.max(0, length - margin * 2), far ? 0 : margin, thick),
        background: null,
        radii: { topLeft: 0, topRight: 0, bottomLeft: 0, bottomRight: 0 },
        // The concave corners an attached bar hangs into the screen, and how
        // far past its own inner edge the surface has to reach to draw them.
        corners: 0
    }
    if (name !== "bar") return result
    if (attached) {
        const acrossStart = far ? radius : 0
        result.content = rect(0, length, acrossStart, thick)
        // The edge and side borders sit outside the surface, twice the border
        // width away so fractional scales round no part of them back in.
        const outset = border * 2
        result.background = rect(-outset, length + outset * 2,
                                 far ? acrossStart : -outset, thick + outset)
        // Square: the bar fills through to its own inner edge. Rounding those
        // corners let the wallpaper show in the two notches that left, so the
        // bar and the windows read as two shapes instead of one.
        result.radii = { topLeft: 0, topRight: 0, bottomLeft: 0, bottomRight: 0 }
        // The rounding belongs on the window side instead. The surface reaches
        // that far to draw it, but reserves and reports only the bar itself:
        // the corners are decoration hanging over the windows, not space taken
        // from them.
        result.corners = radius
        result.thickness = thick + radius
        result.exclusiveZone = reserve ? thick : 0
        result.inset = thick
    } else {
        const acrossStart = upright ? result.content.x : result.content.y
        result.background = rect(margin, Math.max(0, length - margin * 2), acrossStart, thick)
        result.radii = { topLeft: radius, topRight: radius, bottomLeft: radius, bottomRight: radius }
    }
    return result
}

// How thick the bar is: the pills on it, plus - on a vertical bar only - a
// padding on each side. A horizontal bar needs none, because its widgets run
// *along* it and their width costs its thickness nothing. A vertical one reads
// a widget's stacked value across its thickness, and a value like "50%" is a
// pill wide to the pixel.
//
// The padding is its own number because it is an across-axis one. It used to
// be `zoneInset`, which is the inset *along* the bar and is spent there
// already - so an attached bar was padded with the side padding, 8 px, for no
// reason. Whatever it comes to, half of it belongs on each side: pinning the
// zones to the start of the content rect put all of it against the screen
// edge, which is what made a right-hand bar look both too wide and off centre.
function barThickness(edgeName, pillThickness, verticalPadding) {
    const thick = nonNegative(pillThickness)
    return vertical(edge(edgeName)) ? thick + nonNegative(verticalPadding) * 2 : thick
}

// Where the bar's surface sits on the screen: what has to be added to a
// rectangle mapped to the bar's own window to get the same rectangle on the
// screen. The surface is only as thick as the bar and hangs from its own edge,
// so the two agree on the top and the left edge and nowhere else - which is
// why every reported rectangle was right for as long as those were the only
// two edges there were. The notch has carried the same correction from the
// day it was built.
//
// Only the axis across the bar moves. Along it the surface spans the whole
// screen, so window and screen already agree there.
function surfaceOrigin(edgeName, thickness, screenWidth, screenHeight) {
    const side = edge(edgeName)
    if (!farEdge(side)) return { x: 0, y: 0 }
    const thick = nonNegative(thickness)
    return vertical(side)
        ? { x: Math.max(0, nonNegative(screenWidth) - thick), y: 0 }
        : { x: 0, y: Math.max(0, nonNegative(screenHeight) - thick) }
}

// Inset of the zones along the bar: the highlight inset, so the first and last
// hover highlight sit concentric in the bar ends; attached bars have square
// outer corners and use the larger side padding.
function zoneInset(styleName, positionName, highlightInset, sidePadding) {
    if (style(styleName) !== "bar") return 0
    return position(positionName) === "attached" ? nonNegative(sidePadding) : nonNegative(highlightInset)
}

// Separator before each group of a zone: only between visible groups, never
// before the first visible one. `visible` is an array of booleans.
function separators(visible) {
    const result = []
    let seen = false
    for (const shown of (Array.isArray(visible) ? visible : [])) {
        result.push(Boolean(shown) && seen)
        if (shown) seen = true
    }
    return result
}

// Padding at the two ends of one bar segment (one item), along the bar. A
// round cover at an end keeps the same gap to the highlight edge as to its
// side; icon-only items use the smaller padding.
//
// `start` and `end` rather than `left` and `right`: on a vertical bar they are
// above and below, and a name that is wrong half the time is worse than one
// that is abstract.
function segmentPadding(coverStart, coverEnd, iconOnly, pads) {
    const coverPad = Math.max(0, nonNegative(pads.cover) - nonNegative(pads.highlight))
    const plain = iconOnly ? nonNegative(pads.icon) : nonNegative(pads.text)
    return { start: coverStart ? coverPad : plain, end: coverEnd ? coverPad : plain }
}

// Screen-relative place along the bar that a popup centres on, for an item
// segment. x on a horizontal bar, y on a vertical one - the caller knows which
// it is handing over, because it is the one that read the geometry.
function anchorAlong(segmentStart, segmentSize) {
    return Math.round(Number(segmentStart) + nonNegative(segmentSize) / 2)
}
