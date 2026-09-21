.pragma library

// Where something that appears on its own comes from.
//
// A panel grows out of whatever opened it - ShellPanel has done that for a
// while. A notification and an OSD have nobody to open them, so they grow out
// of the thing they belong to instead: the notch, which is what a notch is
// for. When there is no notch on that screen - another desktop mode, or one
// hidden behind a fullscreen window - they appear where they always did.
//
// Pure geometry, so "where does an OSD sit when the notch is 656 wide on a
// 1920 screen" is a test rather than a screenshot, and so the two callers
// cannot drift apart.

// Where a box of `width` sits under `origin`: centred on it, `gap` below it,
// and never closer than `margin` to either edge of the screen. Null when there
// is nothing to sit under.
function under(origin, width, screenWidth, margin, gap) {
    const w = Math.max(0, Number(width) || 0)
    const screen = Math.max(0, Number(screenWidth) || 0)
    // No origin, or a screen whose size is not known yet: there is nowhere to
    // put anything, and answering anyway pins the box to the left margin -
    // which is what "the volume bar is in the top left corner" looked like.
    if (!origin || screen <= 0 || w <= 0) return null
    const edge = Math.max(0, Number(margin) || 0)
    const space = Math.max(0, Number(gap) || 0)
    const centre = Number(origin.x) + Number(origin.width) / 2
    // A box wider than the screen has no room to be pushed into, so it starts
    // at the margin rather than at a negative number.
    const room = Math.max(edge, screen - w - edge)
    return { x: Math.round(Math.max(edge, Math.min(room, centre - w / 2))),
             y: Math.round(Number(origin.y) + Number(origin.height) + space) }
}

// The mirror of `under`, for an origin at the bottom of the screen: a box of
// `width` x `height` centred on it and `gap` *above* it. A bar at the bottom
// edge is the reason this exists - the thing it belongs to is below it, so
// coming out downwards would leave the screen.
function above(origin, width, height, screenWidth, margin, gap) {
    const placed = under(origin, width, screenWidth, margin, gap)
    if (placed === null) return null
    const h = Math.max(0, Number(height) || 0)
    const space = Math.max(0, Number(gap) || 0)
    return { x: placed.x,
             y: Math.round(Math.max(0, Number(origin.y) - space - h)) }
}

// The other pair, for a bar that runs down the screen: a box of `width` x
// `height` centred on `origin` along **y** and `gap` to one side of it.
// `toLeft` puts it on the left, which is what a bar on the right edge needs.
//
// Written as its own function rather than by transposing `under`, because the
// clamp has to be against the screen's *height* here and the box's own height,
// and a transposed version of a function whose parameters are called `width`
// and `screenWidth` is a function nobody can read.
function beside(origin, width, height, screenWidth, screenHeight, margin, gap, toLeft) {
    const w = Math.max(0, Number(width) || 0)
    const h = Math.max(0, Number(height) || 0)
    const wide = Math.max(0, Number(screenWidth) || 0)
    const tall = Math.max(0, Number(screenHeight) || 0)
    // Same rule as `under`: a screen whose size is not known yet has nowhere
    // to put anything, and answering anyway pins the box to a margin.
    if (!origin || wide <= 0 || tall <= 0 || w <= 0 || h <= 0) return null
    const edge = Math.max(0, Number(margin) || 0)
    const space = Math.max(0, Number(gap) || 0)
    const centre = Number(origin.y) + Number(origin.height) / 2
    const room = Math.max(edge, tall - h - edge)
    const y = Math.round(Math.max(edge, Math.min(room, centre - h / 2)))
    const x = toLeft
        ? Math.round(Math.max(edge, Number(origin.x) - space - w))
        : Math.round(Math.min(Math.max(edge, wide - w - edge),
                              Number(origin.x) + Number(origin.width) + space))
    return { x: x, y: y }
}

// Where a box of `width` x `height` sits when it has no origin to come out of:
// centred on the bottom edge of the screen, which is where an OSD has always
// been. Given as a place rather than as an anchor, so the surface can keep one
// pair of anchors for its whole life - a layer surface that is already mapped
// does not reliably take a new anchor, which is why the bar remaps itself when
// its own zone changes.
function atBottom(width, height, screenWidth, screenHeight, bottomMargin, edgeMargin) {
    const w = Math.max(0, Number(width) || 0)
    const h = Math.max(0, Number(height) || 0)
    const screen = Math.max(0, Number(screenWidth) || 0)
    const tall = Math.max(0, Number(screenHeight) || 0)
    if (screen <= 0 || tall <= 0 || w <= 0) return null
    const edge = Math.max(0, Number(edgeMargin) || 0)
    const room = Math.max(edge, screen - w - edge)
    return { x: Math.round(Math.max(edge, Math.min(room, (screen - w) / 2))),
             y: Math.round(Math.max(0, tall - h - Math.max(0, Number(bottomMargin) || 0))) }
}

// The same for a box that belongs in a top corner: the notification popups,
// which have always used the right one.
function atTopRight(width, screenWidth, top, margin) {
    const w = Math.max(0, Number(width) || 0)
    const screen = Math.max(0, Number(screenWidth) || 0)
    if (screen <= 0 || w <= 0) return null
    const edge = Math.max(0, Number(margin) || 0)
    return { x: Math.round(Math.max(edge, screen - w - edge)),
             y: Math.round(Math.max(0, Number(top) || 0)) }
}

// A place on the bar, as a rectangle with no width, for a popup whose own
// widget is not on the bar: a notification comes out of the bar's end, an OSD
// out of its centre. `where` is "end" or "centre"; the end is the right-hand
// one, because that is the corner notifications have always used.
// `atEdge` is the bar's own edge and `screenHeight` the screen it is on: a bar
// at the bottom occupies the last `inset` pixels rather than the first, and a
// spot built from the top would sit under the whole screen.
// Where along its edge a spot sits. Three values reach this and not two:
// `BarLogic.SPOTS` offers "start", "centre" and "end", and Settings offers all
// three - but "start" used to fall into the same branch as "end", so choosing
// it moved nothing. `ShellPanel` reads the same setting and has always handled
// it, which is why panels honoured it and notifications quietly did not.
function spotAlong(where, length, margin) {
    const name = String(where)
    if (name === "centre") return length / 2
    if (name === "start") return Math.min(margin, Math.max(0, length - margin))
    return Math.max(margin, length - margin)
}

function barSpot(barInset, screenWidth, where, margin, atEdge, screenHeight) {
    const inset = Number(barInset)
    const screen = Math.max(0, Number(screenWidth) || 0)
    if (!isFinite(inset) || inset < 0 || screen <= 0) return null
    const edge = Math.max(0, Number(margin) || 0)
    const side = String(atEdge)
    const tall = Math.max(0, Number(screenHeight) || 0)
    // A vertical bar runs down one side, so the spot runs down it too: the
    // rectangle has no *height* instead of no width, and "end" is the bottom
    // rather than the right. Without this branch a left or right bar fell into
    // the top-edge case and put everything in the top-left corner.
    if (side === "left" || side === "right") {
        if (tall <= 0) return null
        const y = spotAlong(where, tall, edge)
        const x = side === "left" ? 0 : Math.max(0, screen - inset)
        return { x: Math.round(x), y: Math.round(y), width: Math.round(inset), height: 0 }
    }
    const x = spotAlong(where, screen, edge)
    if (side !== "bottom")
        return { x: Math.round(x), y: 0, width: 0, height: Math.round(inset) }
    if (tall <= 0) return null
    return { x: Math.round(x), y: Math.round(Math.max(0, tall - inset)), width: 0, height: Math.round(inset) }
}

// How far a box at `target` would have to travel to sit on `origin`, centre on
// centre. A popup is drawn at its resting place and carried back by this while
// it appears, so it travels out of the origin rather than fading in on top of
// it - which is the same motion a panel growing out of a pill makes.
function offsetTo(origin, target) {
    if (!origin || !target) return { x: 0, y: 0 }
    return { x: Math.round((Number(origin.x) + Number(origin.width) / 2)
                           - (Number(target.x) + Number(target.width) / 2)),
             y: Math.round((Number(origin.y) + Number(origin.height) / 2)
                           - (Number(target.y) + Number(target.height) / 2)) }
}
