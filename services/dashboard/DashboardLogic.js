.pragma library
.import "../arrange/FitLogic.js" as Fit

// The cards the dashboard can show, for the picker and for the labels in its
// edit mode. The cards themselves live in shell/dashboard/DashboardPanel.qml;
// this is only what they are called, what they look like in a list, and how
// big they start.
//
// A card that has nothing to show hides itself. That is not the same as being
// removed here, which is the user saying they never want to see it.
//
// Deliberately its own table rather than the control center's: `clock` here is
// a large time over a long date, not a pill, and the two surfaces have
// different ids for different things. They share the model and the picker,
// not the list.

// A row is `Metrics.dashboardGridUnit` and a layout file clamps every cell to
// six of them, so nothing here may start above six - a start size that cannot
// be stored is not a start size, it is whatever the clamp leaves.
var catalogue = [
    { type: "clock", label: "Time", icon: "󰥔", w: 1, h: 2 },
    { type: "weather", label: "Weather", icon: "󰖐", w: 1, h: 4, minH: 2 },
    // Five rows, because the month is six weeks: the header, the weekday
    // names and six rows of days are 346 px on a card, and four rows (292 px
    // with the 12 px gaps) hid the sixth week - 30 November 2026 and every
    // month like it. DashboardCardTest measures the grid against this.
    { type: "calendar", label: "Month", icon: "󰃭", w: 1, h: 5, minH: 5 },
    { type: "events", label: "The day's events", icon: "󰃰", w: 1, h: 3, minH: 2 },
    // The two readouts the dashboard was planned with and never got. Their
    // start heights are *not* the control center's: a row there is 30 px and
    // here it is 64, so the same step count is more than twice the room.
    // `media` at the quick panel's h:5 would open as a 320 px player.
    //
    // A player at one row is not a smaller player, it is not a player, and
    // three meters with nothing to read them by is not a readout - hence the
    // minimums.
    { type: "media", label: "Playing", icon: "󰎆", w: 1, h: 3, minH: 2 },
    { type: "system", label: "System", icon: "󰻠", w: 1, h: 3, minH: 2 }
]

function entry(type) {
    return catalogue.find(card => card.type === String(type || "")) || null
}

function label(type) {
    const found = entry(type)
    return found ? found.label : String(type || "")
}

function icon(type) {
    const found = entry(type)
    return found ? found.icon : ""
}

// How big a card starts: `w` columns wide and `h` rows tall in the dashboard's
// grid. Both are the user's from then on - a corner is dragged - so this is
// only where a card begins, and it begins roughly where it used to sit.
function size(type) {
    const found = entry(type)
    // Anything not in the table is a desktop widget the dashboard accepts.
    // One of its 64 px rows, not three: a widget is a line, not a card.
    return found ? { w: found.w, h: found.h } : { w: 1, h: 1 }
}

// The smallest cell this card may be pulled to. A month grid below five rows
// loses its last week, and a forecast below two is a heading; the clock is
// happy at a single step, so it says nothing here.
function minSize(type) {
    return Fit.minSize(entry(type))
}

// The cell a stored card is drawn in: its own size, but never below the
// card's minimum. A layout from before a minimum was raised (the month at
// four rows, Default's own) is drawn at the new one rather than cut off,
// and nothing is written - the stored size stays the user's until they
// pull the corner.
function shownSize(type, w, h) {
    const least = minSize(type)
    return { w: Math.max(least.w, Number(w) || 1), h: Math.max(least.h, Number(h) || 1) }
}

// How tall a cell of `rows` steps is, gaps between them included.
function cellHeight(rows, unit, gap) {
    return rows * unit + Math.max(0, rows - 1) * gap
}

function isKnown(type) {
    return entry(type) !== null
}

// What the picker offers: everything that is not on the dashboard already.
function missing(types) {
    const shown = types || []
    return catalogue.filter(card => shown.indexOf(card.type) < 0)
}
