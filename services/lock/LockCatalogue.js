.pragma library
.import "../arrange/FitLogic.js" as Fit

// What the lock screen can show above its login block, for the picker in
// Settings and for the labels beside it.
//
// Its own table rather than the control center's or the dashboard's, for the
// same reason theirs are separate: "clock" here is the lock screen's rolling
// digits, not a pill and not a dashboard card. What is shared is the model
// and the arranging, not the list.
//
// **Nothing here is interactive.** The lock screen's whole job is to be a
// wall, and a control on it is a way around it; a media pill is the one
// exception the lock screen already made, and it stays the only one.
//
// A row is `Metrics.lockGridUnit` and a layout file clamps every cell to six
// of them, so nothing may start above six.
var catalogue = [
    { type: "clock", label: "Time", icon: "󰥔", w: 2, h: 3, minW: 2, minH: 2 },
    { type: "date", label: "Date", icon: "󰃭", w: 2, h: 1 },
    { type: "weather", label: "Weather", icon: "󰖐", w: 1, h: 2 },
    { type: "media", label: "Now playing", icon: "󰎈", w: 2, h: 2, minW: 2, minH: 2 },
    { type: "events", label: "Next event", icon: "󰃰", w: 2, h: 1 },
    { type: "battery", label: "Battery", icon: "󰁽", w: 1, h: 1 },
    { type: "keyboard", label: "Keyboard layout", icon: "󰌌", w: 1, h: 1 }
]

function entry(type) {
    return catalogue.find(item => item.type === String(type || "")) || null
}

function label(type) {
    const found = entry(type)
    return found ? found.label : String(type || "")
}

function icon(type) {
    const found = entry(type)
    return found ? found.icon : ""
}

// Where an item begins. It is the user's from then on - a corner is dragged.
function size(type) {
    const found = entry(type)
    return found ? { w: found.w, h: found.h } : { w: 1, h: 1 }
}

// The smallest cell an item is worth. Rolling digits and a player have one.
function minSize(type) {
    return Fit.minSize(entry(type))
}

function isKnown(type) {
    return entry(type) !== null
}

// What the picker offers: everything not on the lock screen already.
function missing(types) {
    const shown = types || []
    return catalogue.filter(item => shown.indexOf(item.type) < 0)
}
